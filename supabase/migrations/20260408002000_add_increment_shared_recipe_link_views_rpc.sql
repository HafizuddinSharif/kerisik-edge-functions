-- Migration: 20260408002000_add_increment_shared_recipe_link_views_rpc
-- Description: Atomic view counter increment for active shared recipe links.

CREATE OR REPLACE FUNCTION public.increment_shared_recipe_link_views(p_share_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.shared_recipe_links
  SET view_count = view_count + 1
  WHERE id = p_share_id
    AND revoked_at IS NULL
    AND expires_at > now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.increment_shared_recipe_link_views(uuid) TO service_role;
