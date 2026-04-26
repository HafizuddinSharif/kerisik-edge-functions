-- Migration: add first-class like_count to browsable_recipes.
-- Keeps the live table append-only while aligning logical schema ordering in declarative files.

ALTER TABLE public.browsable_recipes
ADD COLUMN like_count integer NOT NULL DEFAULT 0;

UPDATE public.browsable_recipes
SET like_count = CASE
  WHEN jsonb_typeof(engagement_metrics->'likes') = 'number' THEN
    GREATEST((engagement_metrics->>'likes')::integer, 0)
  WHEN jsonb_typeof(engagement_metrics->'likes') = 'string'
    AND btrim(engagement_metrics->>'likes') ~ '^[0-9]+$' THEN
    (btrim(engagement_metrics->>'likes'))::integer
  ELSE
    0
END;

ALTER TABLE public.browsable_recipes
ADD CONSTRAINT browsable_recipes_like_count_non_negative
CHECK (like_count >= 0);
