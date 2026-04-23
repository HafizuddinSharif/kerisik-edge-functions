-- Migration: Add recipe tag taxonomy columns to browsable_recipes
-- Created: 2026-04-23
-- Description: Adds taxonomy array columns, backfills meal_types from meal_type,
-- and creates GIN indexes for the new tag categories.

ALTER TABLE public.browsable_recipes
    ADD COLUMN IF NOT EXISTS meal_types text[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS course text[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS main_ingredient text[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS cooking_method text[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS flavor text[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS occasion text[] NOT NULL DEFAULT '{}',
    ADD COLUMN IF NOT EXISTS texture text[] NOT NULL DEFAULT '{}';

UPDATE public.browsable_recipes
SET meal_types = ARRAY[trim(meal_type)]
WHERE nullif(trim(meal_type), '') IS NOT NULL
  AND coalesce(array_length(meal_types, 1), 0) = 0;

CREATE INDEX IF NOT EXISTS idx_browsable_recipes_meal_types
    ON public.browsable_recipes USING GIN (meal_types);

CREATE INDEX IF NOT EXISTS idx_browsable_recipes_course
    ON public.browsable_recipes USING GIN (course);

CREATE INDEX IF NOT EXISTS idx_browsable_recipes_main_ingredient
    ON public.browsable_recipes USING GIN (main_ingredient);

CREATE INDEX IF NOT EXISTS idx_browsable_recipes_cooking_method
    ON public.browsable_recipes USING GIN (cooking_method);

CREATE INDEX IF NOT EXISTS idx_browsable_recipes_flavor
    ON public.browsable_recipes USING GIN (flavor);

CREATE INDEX IF NOT EXISTS idx_browsable_recipes_occasion
    ON public.browsable_recipes USING GIN (occasion);

CREATE INDEX IF NOT EXISTS idx_browsable_recipes_texture
    ON public.browsable_recipes USING GIN (texture);
