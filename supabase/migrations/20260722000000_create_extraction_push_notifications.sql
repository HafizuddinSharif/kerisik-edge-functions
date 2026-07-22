-- Native APNs/FCM device registrations and recipe-extraction delivery outbox.

CREATE TABLE public.native_push_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_profile_id uuid NOT NULL REFERENCES public.user_profile(id) ON DELETE CASCADE,
  provider text NOT NULL CHECK (provider IN ('apns', 'fcm')),
  environment text NOT NULL CHECK (environment IN ('development', 'production')),
  token text NOT NULL CHECK (length(token) BETWEEN 16 AND 4096),
  platform text NOT NULL CHECK (platform IN ('ios', 'android')),
  language text NOT NULL DEFAULT 'EN' CHECK (language IN ('EN', 'BM')),
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT native_push_devices_provider_platform_check CHECK (
    (provider = 'apns' AND platform = 'ios') OR
    (provider = 'fcm' AND platform = 'android')
  ),
  CONSTRAINT native_push_devices_fcm_environment_check CHECK (
    provider <> 'fcm' OR environment = 'production'
  ),
  CONSTRAINT native_push_devices_provider_token_key UNIQUE (provider, environment, token)
);

ALTER TABLE public.native_push_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.native_push_devices FROM anon, authenticated;
GRANT ALL ON TABLE public.native_push_devices TO service_role;

ALTER TABLE public.imported_content
  ADD COLUMN notification_device_id uuid NULL
    REFERENCES public.native_push_devices(id) ON DELETE SET NULL,
  ADD COLUMN notification_generation integer NOT NULL DEFAULT 0;

CREATE TABLE public.extraction_push_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  imported_content_id uuid NOT NULL REFERENCES public.imported_content(id) ON DELETE CASCADE,
  device_id uuid NULL REFERENCES public.native_push_devices(id) ON DELETE SET NULL,
  generation integer NOT NULL DEFAULT 0,
  outcome text NOT NULL CHECK (outcome IN ('success', 'failed', 'not_recipe')),
  title text NOT NULL,
  body text NOT NULL,
  data jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed')),
  attempt_count integer NOT NULL DEFAULT 0,
  provider_message_id text NULL,
  last_error_code text NULL,
  last_error_message text NULL,
  sent_at timestamptz NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT extraction_push_deliveries_generation_key UNIQUE (imported_content_id, generation)
);

ALTER TABLE public.extraction_push_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.extraction_push_deliveries FROM anon, authenticated;
GRANT ALL ON TABLE public.extraction_push_deliveries TO service_role;

CREATE OR REPLACE FUNCTION public.register_native_push_device(
  p_provider text,
  p_environment text,
  p_token text,
  p_platform text,
  p_language text DEFAULT 'EN'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_profile_id uuid;
  v_device_id uuid;
  v_language text := upper(coalesce(p_language, 'EN'));
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_provider NOT IN ('apns', 'fcm') THEN
    RAISE EXCEPTION 'Unsupported push provider';
  END IF;
  IF p_environment NOT IN ('development', 'production') THEN
    RAISE EXCEPTION 'Unsupported push environment';
  END IF;
  IF (p_provider = 'apns' AND p_platform <> 'ios')
     OR (p_provider = 'fcm' AND p_platform <> 'android')
     OR (p_provider = 'fcm' AND p_environment <> 'production') THEN
    RAISE EXCEPTION 'Push provider does not match platform/environment';
  END IF;
  IF p_token IS NULL OR length(p_token) NOT BETWEEN 16 AND 4096 THEN
    RAISE EXCEPTION 'Invalid push token';
  END IF;
  IF v_language NOT IN ('EN', 'BM') THEN
    v_language := 'EN';
  END IF;

  SELECT id INTO v_profile_id
  FROM public.user_profile
  WHERE auth_id = auth.uid();
  IF v_profile_id IS NULL THEN
    RAISE EXCEPTION 'User profile not found';
  END IF;

  INSERT INTO public.native_push_devices (
    user_profile_id, provider, environment, token, platform, language,
    enabled, updated_at, last_seen_at
  ) VALUES (
    v_profile_id, p_provider, p_environment, p_token, p_platform, v_language,
    true, now(), now()
  )
  ON CONFLICT (provider, environment, token) DO UPDATE SET
    user_profile_id = EXCLUDED.user_profile_id,
    platform = EXCLUDED.platform,
    language = EXCLUDED.language,
    enabled = true,
    updated_at = now(),
    last_seen_at = now()
  RETURNING id INTO v_device_id;

  RETURN v_device_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.disable_native_push_device(p_device_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_updated integer;
BEGIN
  UPDATE public.native_push_devices d
  SET enabled = false, updated_at = now()
  WHERE d.id = p_device_id
    AND EXISTS (
      SELECT 1 FROM public.user_profile up
      WHERE up.id = d.user_profile_id AND up.auth_id = auth.uid()
    );
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_extraction_push_notification(p_imported_content_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_updated integer;
BEGIN
  UPDATE public.imported_content ic
  SET notification_device_id = NULL
  WHERE ic.id = p_imported_content_id
    AND ic.status = 'PROCESSING'
    AND EXISTS (
      SELECT 1 FROM public.user_profile up
      WHERE up.id = ic.user_id AND up.auth_id = auth.uid()
    );
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.register_native_push_device(text, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.disable_native_push_device(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_extraction_push_notification(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.register_native_push_device(text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.disable_native_push_device(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_extraction_push_notification(uuid) TO authenticated;
