-- Migration: Add functions that use dev_only (run after enum values are committed).
-- PostgreSQL does not allow using a newly added enum value in the same transaction.

-- Replace get_published_recipes with version that optionally includes dev_only (app passes true only in development)
DROP FUNCTION IF EXISTS public.get_published_recipes(INTEGER, INTEGER, public.social_media_platform, TEXT[]);

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
        br.published_at
    FROM public.browsable_recipes br
    WHERE (br.visibility_status = 'published' OR (br.visibility_status = 'dev_only' AND p_include_dev_only))
    AND (p_platform IS NULL OR br.platform = p_platform)
    AND (p_tags IS NULL OR br.tags && p_tags)
    ORDER BY br.published_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_published_recipes(INTEGER, INTEGER, public.social_media_platform, TEXT[], BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_published_recipes(INTEGER, INTEGER, public.social_media_platform, TEXT[], BOOLEAN) TO service_role;

-- Collections: get_featured_collections optionally includes dev_only (app passes true only in development)
DROP FUNCTION IF EXISTS public.get_featured_collections(INTEGER);

CREATE OR REPLACE FUNCTION public.get_featured_collections(
  p_limit INTEGER DEFAULT 5,
  p_include_dev_only BOOLEAN DEFAULT false
)
RETURNS SETOF collections
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT *
  FROM collections
  WHERE (visibility = 'public' OR (visibility = 'dev_only' AND p_include_dev_only))
    AND is_featured = true
  ORDER BY featured_order ASC NULLS LAST, view_count DESC
  LIMIT p_limit;
$$;

COMMENT ON FUNCTION public.get_featured_collections(INTEGER, BOOLEAN) IS 'Returns featured collections; set p_include_dev_only true only in development to include dev_only.';
