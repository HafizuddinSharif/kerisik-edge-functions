-- Migration: Add ingredient-aware browsable recipe search RPC.

CREATE OR REPLACE FUNCTION public.search_browsable_recipes(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0,
  p_search text DEFAULT NULL,
  p_platform public.social_media_platform DEFAULT NULL,
  p_tags text[] DEFAULT NULL,
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
  posted_date timestamptz
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
    br.posted_date
  FROM public.browsable_recipes br
  LEFT JOIN public.authors a ON a.id = br.author_id
  WHERE (
      br.visibility_status = 'published'
      OR (br.visibility_status = 'dev_only' AND p_include_dev_only)
    )
    AND (p_platform IS NULL OR br.platform = p_platform)
    AND (p_tags IS NULL OR br.tags && p_tags)
    AND (
      NULLIF(btrim(p_search), '') IS NULL
      OR br.meal_name ILIKE '%' || btrim(p_search) || '%'
      OR coalesce(br.meal_description, '') ILIKE '%' || btrim(p_search) || '%'
      OR array_to_string(br.tags, ' ') ILIKE '%' || btrim(p_search) || '%'
      OR EXISTS (
        SELECT 1
        FROM public.imported_content_ingredients ici
        INNER JOIN public.imported_content_sub_ingredients icsi
          ON icsi.imported_content_ingredient_id = ici.id
        WHERE ici.imported_content_id = br.imported_content_id
          AND icsi.name ILIKE '%' || btrim(p_search) || '%'
      )
    )
  ORDER BY br.posted_date DESC NULLS LAST
  LIMIT p_limit
  OFFSET p_offset;
$$;

COMMENT ON FUNCTION public.search_browsable_recipes(
  integer,
  integer,
  text,
  public.social_media_platform,
  text[],
  boolean
)
IS 'List published browsable recipes with optional platform/tag filters and text search across recipe text, tags, and denormalized ingredient names. p_include_dev_only should be true only in development.';

GRANT EXECUTE ON FUNCTION public.search_browsable_recipes(
  integer,
  integer,
  text,
  public.social_media_platform,
  text[],
  boolean
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.search_browsable_recipes(
  integer,
  integer,
  text,
  public.social_media_platform,
  text[],
  boolean
) TO service_role;
