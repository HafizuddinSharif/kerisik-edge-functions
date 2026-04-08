-- Migration: 20260408000000_create_shared_recipe_links
-- Description: Temporary public share snapshots for personal recipes.

-- Keep the shared updated_at trigger function available for this table.
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS public.shared_recipe_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token text NOT NULL,
  owner_user_profile_id uuid REFERENCES public.user_profile(id) ON DELETE SET NULL,
  recipe_payload jsonb NOT NULL,
  image_path text,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  view_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT shared_recipe_links_token_unique UNIQUE (token),
  CONSTRAINT shared_recipe_links_token_not_blank CHECK (btrim(token) <> ''),
  CONSTRAINT shared_recipe_links_recipe_payload_is_object CHECK (jsonb_typeof(recipe_payload) = 'object'),
  CONSTRAINT shared_recipe_links_view_count_non_negative CHECK (view_count >= 0),
  CONSTRAINT shared_recipe_links_expires_after_create CHECK (expires_at > created_at),
  CONSTRAINT shared_recipe_links_revoked_after_create CHECK (
    revoked_at IS NULL OR revoked_at >= created_at
  )
);

CREATE INDEX IF NOT EXISTS idx_shared_recipe_links_owner_created_at
  ON public.shared_recipe_links (owner_user_profile_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_shared_recipe_links_expires_at
  ON public.shared_recipe_links (expires_at);

CREATE INDEX IF NOT EXISTS idx_shared_recipe_links_active_expires_at
  ON public.shared_recipe_links (expires_at)
  WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_shared_recipe_links_active_token
  ON public.shared_recipe_links (token)
  WHERE revoked_at IS NULL;

DROP TRIGGER IF EXISTS set_shared_recipe_links_updated_at ON public.shared_recipe_links;
CREATE TRIGGER set_shared_recipe_links_updated_at
  BEFORE UPDATE ON public.shared_recipe_links
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.shared_recipe_links ENABLE ROW LEVEL SECURITY;

-- Keep direct table access private. Reads and writes should go through edge functions
-- using token-based validation and service role access.

GRANT ALL ON TABLE public.shared_recipe_links TO service_role;
