-- Migration: Add posted_date to get_collection_recipes and get_published_recipes response payloads.
-- Return type change requires DROP then CREATE (PostgreSQL does not allow changing return type with CREATE OR REPLACE).

DROP FUNCTION IF EXISTS public.get_collection_recipes(uuid, integer, integer, text, boolean);

-- get_collection_recipes: include posted_date in return
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
  posted_date timestamptz,
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
    br.posted_date,
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
  ORDER BY br.posted_date DESC NULLS LAST
  LIMIT p_limit
  OFFSET p_offset;
$$;

COMMENT ON FUNCTION public.get_collection_recipes(uuid, integer, integer, text, boolean)
IS 'List recipes in a collection with optional text search. Sorted by posted_date (newest first). p_include_dev_only should be true only in development.';

GRANT EXECUTE ON FUNCTION public.get_collection_recipes(uuid, integer, integer, text, boolean) TO anon, authenticated;

DROP FUNCTION IF EXISTS public.get_published_recipes(integer, integer, public.social_media_platform, text[], boolean);

-- get_published_recipes: include posted_date in return
CREATE OR REPLACE FUNCTION public.get_published_recipes(
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0,
    p_platform public.social_media_platform DEFAULT NULL,
    p_tags TEXT[] DEFAULT NULL,
    p_include_dev_only BOOLEAN DEFAULT false
) RETURNS TABLE (
    id UUID,
    meal_name TEXT,
    meal_description TEXT,
    image_url TEXT,
    cooking_time INTEGER,
    platform public.social_media_platform,
    tags TEXT[],
    view_count INTEGER,
    posted_date TIMESTAMPTZ,
    published_at TIMESTAMPTZ
)
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        br.id,
        br.meal_name,
        br.meal_description,
        br.image_url,
        br.cooking_time,
        br.platform,
        br.tags,
        br.view_count,
        br.posted_date,
        br.published_at
    FROM public.browsable_recipes br
    WHERE (br.visibility_status = 'published' OR (br.visibility_status = 'dev_only' AND p_include_dev_only))
    AND (p_platform IS NULL OR br.platform = p_platform)
    AND (p_tags IS NULL OR br.tags && p_tags)
    ORDER BY br.posted_date DESC NULLS LAST
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_published_recipes(INTEGER, INTEGER, public.social_media_platform, TEXT[], BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_published_recipes(INTEGER, INTEGER, public.social_media_platform, TEXT[], BOOLEAN) TO service_role;
