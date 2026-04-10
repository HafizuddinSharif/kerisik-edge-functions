-- Migration: 20260410090000_add_shared_recipe_rate_limiting
-- Description: Postgres-backed request throttling and deduped view counting for shared recipe links.

CREATE TABLE IF NOT EXISTS public.shared_recipe_link_request_windows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token text NOT NULL,
  client_ip_hash text NOT NULL,
  window_start timestamptz NOT NULL,
  request_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT shared_recipe_link_request_windows_token_not_blank CHECK (btrim(token) <> ''),
  CONSTRAINT shared_recipe_link_request_windows_client_ip_hash_not_blank CHECK (btrim(client_ip_hash) <> ''),
  CONSTRAINT shared_recipe_link_request_windows_request_count_positive CHECK (request_count >= 0),
  CONSTRAINT shared_recipe_link_request_windows_unique UNIQUE (token, client_ip_hash, window_start)
);

CREATE INDEX IF NOT EXISTS idx_shared_recipe_link_request_windows_cleanup
  ON public.shared_recipe_link_request_windows (window_start);

DROP TRIGGER IF EXISTS set_shared_recipe_link_request_windows_updated_at ON public.shared_recipe_link_request_windows;
CREATE TRIGGER set_shared_recipe_link_request_windows_updated_at
  BEFORE UPDATE ON public.shared_recipe_link_request_windows
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.shared_recipe_link_views (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  share_id uuid NOT NULL REFERENCES public.shared_recipe_links(id) ON DELETE CASCADE,
  viewer_key_hash text NOT NULL,
  last_viewed_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT shared_recipe_link_views_viewer_key_hash_not_blank CHECK (btrim(viewer_key_hash) <> ''),
  CONSTRAINT shared_recipe_link_views_unique UNIQUE (share_id, viewer_key_hash)
);

CREATE INDEX IF NOT EXISTS idx_shared_recipe_link_views_last_viewed_at
  ON public.shared_recipe_link_views (last_viewed_at);

DROP TRIGGER IF EXISTS set_shared_recipe_link_views_updated_at ON public.shared_recipe_link_views;
CREATE TRIGGER set_shared_recipe_link_views_updated_at
  BEFORE UPDATE ON public.shared_recipe_link_views
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.shared_recipe_link_request_windows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shared_recipe_link_views ENABLE ROW LEVEL SECURITY;

GRANT ALL ON TABLE public.shared_recipe_link_request_windows TO service_role;
GRANT ALL ON TABLE public.shared_recipe_link_views TO service_role;

CREATE OR REPLACE FUNCTION public.check_shared_recipe_link_rate_limit(
  p_token text,
  p_client_ip_hash text,
  p_window_started_at timestamptz,
  p_limit integer DEFAULT 30
)
RETURNS TABLE (
  allowed boolean,
  request_count integer,
  remaining integer,
  limit_value integer,
  reset_at timestamptz,
  retry_after_seconds integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_request_count integer;
  v_limit integer := GREATEST(COALESCE(p_limit, 30), 1);
  v_reset_at timestamptz := date_trunc('minute', p_window_started_at) + interval '1 minute';
BEGIN
  INSERT INTO public.shared_recipe_link_request_windows (
    token,
    client_ip_hash,
    window_start,
    request_count
  )
  VALUES (
    p_token,
    p_client_ip_hash,
    date_trunc('minute', p_window_started_at),
    1
  )
  ON CONFLICT (token, client_ip_hash, window_start)
  DO UPDATE
  SET
    request_count = public.shared_recipe_link_request_windows.request_count + 1,
    updated_at = now()
  RETURNING public.shared_recipe_link_request_windows.request_count
  INTO v_request_count;

  RETURN QUERY
  SELECT
    v_request_count <= v_limit,
    v_request_count,
    GREATEST(v_limit - v_request_count, 0),
    v_limit,
    v_reset_at,
    GREATEST(CEIL(EXTRACT(EPOCH FROM (v_reset_at - now())))::integer, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_shared_recipe_link_rate_limit(text, text, timestamptz, integer) TO service_role;

DROP FUNCTION IF EXISTS public.increment_shared_recipe_link_views(uuid);

CREATE OR REPLACE FUNCTION public.increment_shared_recipe_link_views(
  p_share_id uuid,
  p_viewer_key_hash text,
  p_dedupe_window interval DEFAULT interval '15 minutes'
)
RETURNS TABLE (counted boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_inserted integer := 0;
  v_updated integer := 0;
BEGIN
  PERFORM 1
  FROM public.shared_recipe_links
  WHERE id = p_share_id
    AND revoked_at IS NULL
    AND expires_at > v_now
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false;
    RETURN;
  END IF;

  INSERT INTO public.shared_recipe_link_views (
    share_id,
    viewer_key_hash,
    last_viewed_at
  )
  VALUES (
    p_share_id,
    p_viewer_key_hash,
    v_now
  )
  ON CONFLICT (share_id, viewer_key_hash) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  IF v_inserted > 0 THEN
    UPDATE public.shared_recipe_links
    SET view_count = view_count + 1
    WHERE id = p_share_id
      AND revoked_at IS NULL
      AND expires_at > v_now;

    RETURN QUERY SELECT true;
    RETURN;
  END IF;

  UPDATE public.shared_recipe_link_views
  SET
    last_viewed_at = v_now,
    updated_at = v_now
  WHERE share_id = p_share_id
    AND viewer_key_hash = p_viewer_key_hash
    AND last_viewed_at < (v_now - p_dedupe_window);

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated > 0 THEN
    UPDATE public.shared_recipe_links
    SET view_count = view_count + 1
    WHERE id = p_share_id
      AND revoked_at IS NULL
      AND expires_at > v_now;

    RETURN QUERY SELECT true;
    RETURN;
  END IF;

  RETURN QUERY SELECT false;
END;
$$;

GRANT EXECUTE ON FUNCTION public.increment_shared_recipe_link_views(uuid, text, interval) TO service_role;

CREATE OR REPLACE FUNCTION public.cleanup_shared_recipe_link_request_windows(
  p_older_than interval DEFAULT interval '1 day'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted_count integer;
BEGIN
  DELETE FROM public.shared_recipe_link_request_windows
  WHERE window_start < (now() - p_older_than);

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  RETURN v_deleted_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cleanup_shared_recipe_link_request_windows(interval) TO service_role;
