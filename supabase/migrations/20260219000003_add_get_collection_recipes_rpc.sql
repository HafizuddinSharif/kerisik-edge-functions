-- Migration: Add get_collection_recipes RPC for listing recipes in a collection with optional search.
-- Joins collection_recipes, browsable_recipes, and authors; supports visibility and text filter.

CREATE OR REPLACE FUNCTION public.get_collection_recipes(
  p_collection_id uuid,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0,
  p_search text DEFAULT NULL,
  p_include_dev_only boolean DEFAULT false
)
RETURNS TABLE (
  id uuid,
  meal_name text,
  meal_description text,
  image_url text,
  cooking_time integer,
  author_id uuid,
  author jsonb,
  platform public.social_media_platform,
  tags text[],
  cuisine_type text,
  difficulty_level public.recipe_difficulty,
  featured boolean,
  view_count integer,
  total_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    br.id,
    br.meal_name,
    br.meal_description,
    br.image_url,
    br.cooking_time,
    br.author_id,
    CASE
      WHEN a.id IS NOT NULL THEN jsonb_build_object(
        'id', a.id,
        'name', a.name,
        'handle', a.handle,
        'profile_url', a.profile_url,
        'profile_pic_url', a.profile_pic_url,
        'platform', a.platform::text
      )
      ELSE NULL
    END AS author,
    br.platform,
    br.tags,
    br.cuisine_type,
    br.difficulty_level,
    br.featured,
    br.view_count,
    count(*) OVER() AS total_count
  FROM public.collection_recipes cr
  INNER JOIN public.browsable_recipes br ON br.id = cr.recipe_id
  LEFT JOIN public.authors a ON a.id = br.author_id
  WHERE cr.collection_id = p_collection_id
    AND (
      br.visibility_status = 'published'
      OR (br.visibility_status = 'dev_only' AND p_include_dev_only)
    )
    AND (
      NULLIF(trim(p_search), '') IS NULL
      OR br.meal_name ILIKE '%' || trim(p_search) || '%'
      OR coalesce(br.meal_description, '') ILIKE '%' || trim(p_search) || '%'
      OR array_to_string(br.tags, ' ') ILIKE '%' || trim(p_search) || '%'
    )
  ORDER BY cr.sort_order ASC
  LIMIT p_limit
  OFFSET p_offset;
$$;

COMMENT ON FUNCTION public.get_collection_recipes(uuid, integer, integer, text, boolean)
IS 'List recipes in a collection with optional text search. p_include_dev_only should be true only in development.';

GRANT EXECUTE ON FUNCTION public.get_collection_recipes(uuid, integer, integer, text, boolean) TO anon, authenticated;
