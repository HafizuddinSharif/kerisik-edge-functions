-- Migration: 20260302000000_add_local_recipe_metadata_to_kerisik_sync
-- Description: Align kerisik.recipes (cloud sync) with local SQLite recipes (v2.0.2+ fields).
-- Idempotent: safe to run multiple times; no-ops if table is missing.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'kerisik' AND table_name = 'recipes'
  ) THEN
    RETURN;
  END IF;

  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS is_synced integer NOT NULL DEFAULT 0;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS browsable_recipe_id text;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS imported_content_id text;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS original_post_url text;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS platform text;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS cuisine_type text;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS meal_type text;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS difficulty_level text;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS featured integer NOT NULL DEFAULT 0;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS view_count integer NOT NULL DEFAULT 0;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS save_count integer NOT NULL DEFAULT 0;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS share_count integer NOT NULL DEFAULT 0;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS published_at text;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS author_id text;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS author_name text;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS author_handle text;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS author_profile_url text;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS author_profile_pic_url text;
  ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS author_platform text;
END $$;

