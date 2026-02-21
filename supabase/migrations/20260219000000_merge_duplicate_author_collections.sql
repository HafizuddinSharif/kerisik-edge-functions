-- Migration: Merge duplicate author collections into a canonical collection per author_id,
-- recompute recipe_count, and enforce unique author collection per author_id.

-- 1) Merge duplicate author collections into a canonical collection per author_id
WITH author_dupes AS (
  SELECT
    author_id,
    id AS collection_id,
    created_at,
    FIRST_VALUE(id) OVER (PARTITION BY author_id ORDER BY created_at ASC) AS canonical_id
  FROM collections
  WHERE type = 'author' AND author_id IS NOT NULL
),
move_recipes AS (
  INSERT INTO collection_recipes (collection_id, recipe_id, sort_order, added_by_user_id, curator_note, is_featured, added_at)
  SELECT
    d.canonical_id,
    cr.recipe_id,
    cr.sort_order,
    cr.added_by_user_id,
    cr.curator_note,
    cr.is_featured,
    cr.added_at
  FROM author_dupes d
  JOIN collection_recipes cr ON cr.collection_id = d.collection_id
  WHERE d.collection_id <> d.canonical_id
  ON CONFLICT (collection_id, recipe_id) DO NOTHING
  RETURNING 1
),
remove_duplicate_collections AS (
  DELETE FROM collections c
  USING author_dupes d
  WHERE c.id = d.collection_id
    AND d.collection_id <> d.canonical_id
  RETURNING c.id
)
SELECT
  (SELECT COUNT(*) FROM move_recipes) AS moved_recipe_rows,
  (SELECT COUNT(*) FROM remove_duplicate_collections) AS removed_collections;

-- 2) Recompute recipe_count for author collections (safe + idempotent)
UPDATE collections c
SET recipe_count = sub.cnt
FROM (
  SELECT collection_id, COUNT(*)::int AS cnt
  FROM collection_recipes
  GROUP BY collection_id
) sub
WHERE c.id = sub.collection_id;

-- 3) Enforce uniqueness: one author collection per author_id
CREATE UNIQUE INDEX IF NOT EXISTS unique_author_collection_per_author
ON collections (author_id)
WHERE type = 'author';
