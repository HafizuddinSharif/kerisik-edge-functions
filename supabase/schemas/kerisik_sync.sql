-- Kerisik Cloud Sync Schema
-- Mirrors SQLite syncable tables for offline-first backup/sync. Local SQLite is source of truth.
-- Phase 2: Supabase Setup (cloud-sync-implementation-plan.md)

CREATE SCHEMA IF NOT EXISTS kerisik;

-- Trigger to set updated_at on row change
CREATE OR REPLACE FUNCTION kerisik.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------------
-- meals
-- ---------------------------------------------------------------------------
CREATE TABLE kerisik.meals (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  uuid text NOT NULL DEFAULT gen_random_uuid()::text,
  meal_name text NOT NULL,
  description text NOT NULL,
  image_url text,
  recipe_link text,
  created_date text,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, uuid)
);

CREATE TRIGGER set_meals_updated_at
  BEFORE UPDATE ON kerisik.meals
  FOR EACH ROW EXECUTE FUNCTION kerisik.set_updated_at();

-- ---------------------------------------------------------------------------
-- recipes (meal_uuid nullable for standalone recipes)
-- ---------------------------------------------------------------------------
CREATE TABLE kerisik.recipes (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  uuid text NOT NULL DEFAULT gen_random_uuid()::text,
  meal_uuid text,
  recipe_name text NOT NULL,
  description text,
  cooking_guide text,
  image_url text,
  recipe_link text,
  cooking_time integer,
  serving_suggestions integer,
  sort_order integer NOT NULL DEFAULT 0,
  created_date text,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, uuid),
  CONSTRAINT fk_recipes_meal
    FOREIGN KEY (user_id, meal_uuid) REFERENCES kerisik.meals(user_id, uuid) ON DELETE CASCADE
);

CREATE TRIGGER set_recipes_updated_at
  BEFORE UPDATE ON kerisik.recipes
  FOR EACH ROW EXECUTE FUNCTION kerisik.set_updated_at();

-- ---------------------------------------------------------------------------
-- ingredients
-- ---------------------------------------------------------------------------
CREATE TABLE kerisik.ingredients (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  uuid text NOT NULL DEFAULT gen_random_uuid()::text,
  recipe_uuid text NOT NULL,
  item_name text NOT NULL,
  quantity real NOT NULL,
  unit varchar(20),
  sort_order integer NOT NULL DEFAULT 0,
  created_date text,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, uuid),
  CONSTRAINT fk_ingredients_recipe
    FOREIGN KEY (user_id, recipe_uuid) REFERENCES kerisik.recipes(user_id, uuid) ON DELETE CASCADE
);

CREATE TRIGGER set_ingredients_updated_at
  BEFORE UPDATE ON kerisik.ingredients
  FOR EACH ROW EXECUTE FUNCTION kerisik.set_updated_at();

-- ---------------------------------------------------------------------------
-- sub_ingredients (quantity as text for fractions)
-- ---------------------------------------------------------------------------
CREATE TABLE kerisik.sub_ingredients (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  uuid text NOT NULL DEFAULT gen_random_uuid()::text,
  ingredient_uuid text NOT NULL,
  item_name text NOT NULL,
  quantity text NOT NULL,
  unit varchar(20),
  sort_order integer NOT NULL DEFAULT 0,
  created_date text,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, uuid),
  CONSTRAINT fk_sub_ingredients_ingredient
    FOREIGN KEY (user_id, ingredient_uuid) REFERENCES kerisik.ingredients(user_id, uuid) ON DELETE CASCADE
);

CREATE TRIGGER set_sub_ingredients_updated_at
  BEFORE UPDATE ON kerisik.sub_ingredients
  FOR EACH ROW EXECUTE FUNCTION kerisik.set_updated_at();

-- ---------------------------------------------------------------------------
-- steps
-- ---------------------------------------------------------------------------
CREATE TABLE kerisik.steps (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  uuid text NOT NULL DEFAULT gen_random_uuid()::text,
  recipe_uuid text NOT NULL,
  step_number integer NOT NULL,
  step_description text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  created_date text,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, uuid),
  CONSTRAINT fk_steps_recipe
    FOREIGN KEY (user_id, recipe_uuid) REFERENCES kerisik.recipes(user_id, uuid) ON DELETE CASCADE
);

CREATE TRIGGER set_steps_updated_at
  BEFORE UPDATE ON kerisik.steps
  FOR EACH ROW EXECUTE FUNCTION kerisik.set_updated_at();

-- ---------------------------------------------------------------------------
-- sub_steps
-- ---------------------------------------------------------------------------
CREATE TABLE kerisik.sub_steps (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  uuid text NOT NULL DEFAULT gen_random_uuid()::text,
  step_uuid text NOT NULL,
  sub_step_number integer NOT NULL,
  sub_step_description text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  created_date text,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, uuid),
  CONSTRAINT fk_sub_steps_step
    FOREIGN KEY (user_id, step_uuid) REFERENCES kerisik.steps(user_id, uuid) ON DELETE CASCADE
);

CREATE TRIGGER set_sub_steps_updated_at
  BEFORE UPDATE ON kerisik.sub_steps
  FOR EACH ROW EXECUTE FUNCTION kerisik.set_updated_at();

-- ---------------------------------------------------------------------------
-- recipe_tags
-- ---------------------------------------------------------------------------
CREATE TABLE kerisik.recipe_tags (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  uuid text NOT NULL DEFAULT gen_random_uuid()::text,
  recipe_uuid text NOT NULL,
  tag text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('tag', 'dietary')),
  sort_order integer NOT NULL DEFAULT 0,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, uuid),
  CONSTRAINT fk_recipe_tags_recipe
    FOREIGN KEY (user_id, recipe_uuid) REFERENCES kerisik.recipes(user_id, uuid) ON DELETE CASCADE
);

CREATE TRIGGER set_recipe_tags_updated_at
  BEFORE UPDATE ON kerisik.recipe_tags
  FOR EACH ROW EXECUTE FUNCTION kerisik.set_updated_at();

-- ---------------------------------------------------------------------------
-- Indexes for fast sync (user_id, updated_at) and relationship lookups
-- ---------------------------------------------------------------------------
CREATE INDEX idx_kerisik_meals_user_updated
  ON kerisik.meals(user_id, updated_at DESC);
CREATE INDEX idx_kerisik_meals_user_updated_active
  ON kerisik.meals(user_id, updated_at DESC) WHERE deleted_at IS NULL;

CREATE INDEX idx_kerisik_recipes_user_updated
  ON kerisik.recipes(user_id, updated_at DESC);
CREATE INDEX idx_kerisik_recipes_user_meal
  ON kerisik.recipes(user_id, meal_uuid);
CREATE INDEX idx_kerisik_recipes_user_updated_active
  ON kerisik.recipes(user_id, updated_at DESC) WHERE deleted_at IS NULL;

CREATE INDEX idx_kerisik_ingredients_user_updated
  ON kerisik.ingredients(user_id, updated_at DESC);
CREATE INDEX idx_kerisik_ingredients_user_recipe
  ON kerisik.ingredients(user_id, recipe_uuid);
CREATE INDEX idx_kerisik_ingredients_user_updated_active
  ON kerisik.ingredients(user_id, updated_at DESC) WHERE deleted_at IS NULL;

CREATE INDEX idx_kerisik_sub_ingredients_user_updated
  ON kerisik.sub_ingredients(user_id, updated_at DESC);
CREATE INDEX idx_kerisik_sub_ingredients_user_ingredient
  ON kerisik.sub_ingredients(user_id, ingredient_uuid);
CREATE INDEX idx_kerisik_sub_ingredients_user_updated_active
  ON kerisik.sub_ingredients(user_id, updated_at DESC) WHERE deleted_at IS NULL;

CREATE INDEX idx_kerisik_steps_user_updated
  ON kerisik.steps(user_id, updated_at DESC);
CREATE INDEX idx_kerisik_steps_user_recipe
  ON kerisik.steps(user_id, recipe_uuid);
CREATE INDEX idx_kerisik_steps_user_updated_active
  ON kerisik.steps(user_id, updated_at DESC) WHERE deleted_at IS NULL;

CREATE INDEX idx_kerisik_sub_steps_user_updated
  ON kerisik.sub_steps(user_id, updated_at DESC);
CREATE INDEX idx_kerisik_sub_steps_user_step
  ON kerisik.sub_steps(user_id, step_uuid);
CREATE INDEX idx_kerisik_sub_steps_user_updated_active
  ON kerisik.sub_steps(user_id, updated_at DESC) WHERE deleted_at IS NULL;

CREATE INDEX idx_kerisik_recipe_tags_user_updated
  ON kerisik.recipe_tags(user_id, updated_at DESC);
CREATE INDEX idx_kerisik_recipe_tags_user_recipe
  ON kerisik.recipe_tags(user_id, recipe_uuid);
CREATE INDEX idx_kerisik_recipe_tags_kind_tag
  ON kerisik.recipe_tags(user_id, kind, tag);
CREATE INDEX idx_kerisik_recipe_tags_user_updated_active
  ON kerisik.recipe_tags(user_id, updated_at DESC) WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- Row Level Security (no DELETE policy — deletes via deleted_at)
-- ---------------------------------------------------------------------------
ALTER TABLE kerisik.meals ENABLE ROW LEVEL SECURITY;
ALTER TABLE kerisik.recipes ENABLE ROW LEVEL SECURITY;
ALTER TABLE kerisik.ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE kerisik.sub_ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE kerisik.steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE kerisik.sub_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE kerisik.recipe_tags ENABLE ROW LEVEL SECURITY;

CREATE POLICY "kerisik_meals_select" ON kerisik.meals FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "kerisik_meals_insert" ON kerisik.meals FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "kerisik_meals_update" ON kerisik.meals FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "kerisik_recipes_select" ON kerisik.recipes FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "kerisik_recipes_insert" ON kerisik.recipes FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "kerisik_recipes_update" ON kerisik.recipes FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "kerisik_ingredients_select" ON kerisik.ingredients FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "kerisik_ingredients_insert" ON kerisik.ingredients FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "kerisik_ingredients_update" ON kerisik.ingredients FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "kerisik_sub_ingredients_select" ON kerisik.sub_ingredients FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "kerisik_sub_ingredients_insert" ON kerisik.sub_ingredients FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "kerisik_sub_ingredients_update" ON kerisik.sub_ingredients FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "kerisik_steps_select" ON kerisik.steps FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "kerisik_steps_insert" ON kerisik.steps FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "kerisik_steps_update" ON kerisik.steps FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "kerisik_sub_steps_select" ON kerisik.sub_steps FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "kerisik_sub_steps_insert" ON kerisik.sub_steps FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "kerisik_sub_steps_update" ON kerisik.sub_steps FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "kerisik_recipe_tags_select" ON kerisik.recipe_tags FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "kerisik_recipe_tags_insert" ON kerisik.recipe_tags FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
CREATE POLICY "kerisik_recipe_tags_update" ON kerisik.recipe_tags FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
GRANT USAGE ON SCHEMA kerisik TO authenticated;
GRANT USAGE ON SCHEMA kerisik TO service_role;

GRANT SELECT, INSERT, UPDATE ON kerisik.meals TO authenticated;
GRANT ALL ON kerisik.meals TO service_role;

GRANT SELECT, INSERT, UPDATE ON kerisik.recipes TO authenticated;
GRANT ALL ON kerisik.recipes TO service_role;

GRANT SELECT, INSERT, UPDATE ON kerisik.ingredients TO authenticated;
GRANT ALL ON kerisik.ingredients TO service_role;

GRANT SELECT, INSERT, UPDATE ON kerisik.sub_ingredients TO authenticated;
GRANT ALL ON kerisik.sub_ingredients TO service_role;

GRANT SELECT, INSERT, UPDATE ON kerisik.steps TO authenticated;
GRANT ALL ON kerisik.steps TO service_role;

GRANT SELECT, INSERT, UPDATE ON kerisik.sub_steps TO authenticated;
GRANT ALL ON kerisik.sub_steps TO service_role;

GRANT SELECT, INSERT, UPDATE ON kerisik.recipe_tags TO authenticated;
GRANT ALL ON kerisik.recipe_tags TO service_role;
