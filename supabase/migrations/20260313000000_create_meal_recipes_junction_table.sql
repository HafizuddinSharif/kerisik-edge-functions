-- Migration: 20260313000000_create_meal_recipes_junction_table
-- Description: Add kerisik.meal_recipes junction table (meals <-> recipes) with RLS.
-- Reference: docs/ref_only_create_kerisik_sync_schema.sql

-- Ensure required extensions exist (for gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Ensure schema and trigger function exist (no-op if already present)
CREATE SCHEMA IF NOT EXISTS kerisik;

CREATE OR REPLACE FUNCTION kerisik.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- meal_recipes (junction: many-to-many meals <-> recipes)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS kerisik.meal_recipes (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  uuid text NOT NULL DEFAULT gen_random_uuid()::text,
  meal_uuid text NOT NULL,
  recipe_uuid text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  created_date text,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, uuid),
  CONSTRAINT fk_meal_recipes_meal
    FOREIGN KEY (user_id, meal_uuid) REFERENCES kerisik.meals(user_id, uuid) ON DELETE CASCADE,
  CONSTRAINT fk_meal_recipes_recipe
    FOREIGN KEY (user_id, recipe_uuid) REFERENCES kerisik.recipes(user_id, uuid) ON DELETE CASCADE
);

-- If the table existed already, ensure FK constraints exist (best-effort).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'kerisik' AND table_name = 'meal_recipes'
  ) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint c
      JOIN pg_class t ON t.oid = c.conrelid
      JOIN pg_namespace n ON n.oid = t.relnamespace
      WHERE n.nspname = 'kerisik'
        AND t.relname = 'meal_recipes'
        AND c.conname = 'fk_meal_recipes_meal'
    ) THEN
      ALTER TABLE kerisik.meal_recipes
        ADD CONSTRAINT fk_meal_recipes_meal
        FOREIGN KEY (user_id, meal_uuid) REFERENCES kerisik.meals(user_id, uuid) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint c
      JOIN pg_class t ON t.oid = c.conrelid
      JOIN pg_namespace n ON n.oid = t.relnamespace
      WHERE n.nspname = 'kerisik'
        AND t.relname = 'meal_recipes'
        AND c.conname = 'fk_meal_recipes_recipe'
    ) THEN
      ALTER TABLE kerisik.meal_recipes
        ADD CONSTRAINT fk_meal_recipes_recipe
        FOREIGN KEY (user_id, recipe_uuid) REFERENCES kerisik.recipes(user_id, uuid) ON DELETE CASCADE;
    END IF;
  END IF;
END $$;

-- Trigger (recreate to be safe)
DROP TRIGGER IF EXISTS set_meal_recipes_updated_at ON kerisik.meal_recipes;
CREATE TRIGGER set_meal_recipes_updated_at
  BEFORE UPDATE ON kerisik.meal_recipes
  FOR EACH ROW EXECUTE FUNCTION kerisik.set_updated_at();

-- Indexes
CREATE INDEX IF NOT EXISTS idx_kerisik_meal_recipes_user_updated
  ON kerisik.meal_recipes(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_kerisik_meal_recipes_user_meal
  ON kerisik.meal_recipes(user_id, meal_uuid);
CREATE INDEX IF NOT EXISTS idx_kerisik_meal_recipes_user_recipe
  ON kerisik.meal_recipes(user_id, recipe_uuid);
CREATE INDEX IF NOT EXISTS idx_kerisik_meal_recipes_user_updated_active
  ON kerisik.meal_recipes(user_id, updated_at DESC) WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- Row Level Security (no DELETE policy — deletes via deleted_at)
-- ---------------------------------------------------------------------------
ALTER TABLE kerisik.meal_recipes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "kerisik_meal_recipes_select" ON kerisik.meal_recipes;
DROP POLICY IF EXISTS "kerisik_meal_recipes_insert" ON kerisik.meal_recipes;
DROP POLICY IF EXISTS "kerisik_meal_recipes_update" ON kerisik.meal_recipes;

CREATE POLICY "kerisik_meal_recipes_select" ON kerisik.meal_recipes
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "kerisik_meal_recipes_insert" ON kerisik.meal_recipes
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "kerisik_meal_recipes_update" ON kerisik.meal_recipes
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA kerisik TO authenticated;
GRANT USAGE ON SCHEMA kerisik TO service_role;

GRANT SELECT, INSERT, UPDATE ON kerisik.meal_recipes TO authenticated;
GRANT ALL ON kerisik.meal_recipes TO service_role;

