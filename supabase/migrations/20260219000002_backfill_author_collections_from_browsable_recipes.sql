-- Migration: Backfill author collections from existing browsable_recipes.
-- For every browsable_recipes row with author_id set, ensure that author has an
-- author collection and that the recipe is linked in collection_recipes.
-- Idempotent: re-running inserts no duplicate collections or collection_recipes.

-- 1) Create any missing author collections (one per distinct author_id in browsable_recipes)
INSERT INTO collections (type, name, author_id, created_by_user_id)
SELECT
  'author'::collection_type,
  COALESCE(a.name, a.handle, 'Unknown author'),
  a.id,
  NULL
FROM authors a
WHERE a.id IN (SELECT DISTINCT author_id FROM browsable_recipes WHERE author_id IS NOT NULL)
  AND NOT EXISTS (
    SELECT 1 FROM collections c
    WHERE c.type = 'author' AND c.author_id = a.id
  );

-- 2) Insert missing recipe-to-collection links with stable sort_order per collection
WITH missing AS (
  SELECT c.id AS collection_id, br.id AS recipe_id, br.created_at
  FROM browsable_recipes br
  JOIN collections c ON c.type = 'author' AND c.author_id = br.author_id
  WHERE br.author_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM collection_recipes cr
      WHERE cr.collection_id = c.id AND cr.recipe_id = br.id
    )
),
base_sort AS (
  SELECT collection_id, COALESCE(MAX(sort_order), 0) AS base
  FROM collection_recipes
  WHERE collection_id IN (SELECT collection_id FROM missing)
  GROUP BY collection_id
),
numbered AS (
  SELECT
    m.collection_id,
    m.recipe_id,
    (COALESCE(b.base, 0) + ROW_NUMBER() OVER (PARTITION BY m.collection_id ORDER BY m.created_at))::integer AS sort_order
  FROM missing m
  LEFT JOIN base_sort b ON b.collection_id = m.collection_id
)
INSERT INTO collection_recipes (collection_id, recipe_id, sort_order, added_by_user_id, curator_note, is_featured, added_at)
SELECT collection_id, recipe_id, sort_order, NULL, NULL, false, now()
FROM numbered
ON CONFLICT (collection_id, recipe_id) DO NOTHING;

-- Trigger update_collection_recipe_count runs on INSERT, so recipe_count is updated automatically.
-- Optional: uncomment below to log counts (run separately or in same transaction).
-- SELECT
--   (SELECT count(*) FROM browsable_recipes WHERE author_id IS NOT NULL) AS recipes_with_author,
--   (SELECT count(*) FROM collection_recipes cr
--    JOIN collections c ON c.id = cr.collection_id AND c.type = 'author') AS author_collection_recipe_links;
