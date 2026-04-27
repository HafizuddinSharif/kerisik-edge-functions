-- Migration: Add filtered browsable recipe search RPC.
-- Extends recipe search/listing with deterministic taxonomy filters, author filter,
-- pagination metadata, and compatibility with the existing recipe-card payload.

CREATE OR REPLACE FUNCTION public.search_browsable_recipes_filtered(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0,
  p_search text DEFAULT NULL,
  p_author_search text DEFAULT NULL,
  p_cuisine_types text[] DEFAULT NULL,
  p_meal_types text[] DEFAULT NULL,
  p_main_ingredient text[] DEFAULT NULL,
  p_cooking_method text[] DEFAULT NULL,
  p_flavor text[] DEFAULT NULL,
  p_texture text[] DEFAULT NULL,
  p_dietary_tags text[] DEFAULT NULL,
  p_max_cooking_time integer DEFAULT NULL,
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
  posted_date timestamptz,
  total_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH raw_params AS (
    SELECT
      NULLIF(btrim(p_search), '') AS search_query,
      NULLIF(lower(btrim(p_author_search)), '') AS author_search,
      ARRAY(
        SELECT DISTINCT lower(btrim(value))
        FROM unnest(coalesce(p_cuisine_types, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS cuisine_types,
      ARRAY(
        SELECT DISTINCT lower(btrim(value))
        FROM unnest(coalesce(p_meal_types, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS meal_types,
      ARRAY(
        SELECT DISTINCT lower(btrim(value))
        FROM unnest(coalesce(p_main_ingredient, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS main_ingredient,
      ARRAY(
        SELECT DISTINCT lower(btrim(value))
        FROM unnest(coalesce(p_cooking_method, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS cooking_method,
      ARRAY(
        SELECT DISTINCT lower(btrim(value))
        FROM unnest(coalesce(p_flavor, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS flavor,
      ARRAY(
        SELECT DISTINCT lower(btrim(value))
        FROM unnest(coalesce(p_texture, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS texture,
      ARRAY(
        SELECT DISTINCT lower(btrim(value))
        FROM unnest(coalesce(p_dietary_tags, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS dietary_tags,
      ARRAY(
        SELECT DISTINCT lower(btrim(value))
        FROM unnest(coalesce(p_tags, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS tags,
      p_max_cooking_time AS max_cooking_time
  ),
  params AS (
    SELECT
      search_query,
      author_search,
      CASE WHEN cardinality(cuisine_types) = 0 THEN NULL ELSE cuisine_types END AS cuisine_types,
      CASE WHEN cardinality(meal_types) = 0 THEN NULL ELSE meal_types END AS meal_types,
      CASE WHEN cardinality(main_ingredient) = 0 THEN NULL ELSE main_ingredient END AS main_ingredient,
      CASE WHEN cardinality(cooking_method) = 0 THEN NULL ELSE cooking_method END AS cooking_method,
      CASE WHEN cardinality(flavor) = 0 THEN NULL ELSE flavor END AS flavor,
      CASE WHEN cardinality(texture) = 0 THEN NULL ELSE texture END AS texture,
      CASE WHEN cardinality(dietary_tags) = 0 THEN NULL ELSE dietary_tags END AS dietary_tags,
      CASE WHEN cardinality(tags) = 0 THEN NULL ELSE tags END AS tags,
      max_cooking_time
    FROM raw_params
  ),
  visible_recipes AS (
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
      br.imported_content_id,
      lower(btrim(coalesce(br.cuisine_type, ''))) AS normalized_cuisine_type,
      ARRAY(
        SELECT lower(btrim(value))
        FROM unnest(coalesce(br.meal_types, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_meal_types,
      ARRAY(
        SELECT lower(btrim(value))
        FROM unnest(coalesce(br.main_ingredient, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_main_ingredient,
      ARRAY(
        SELECT lower(btrim(value))
        FROM unnest(coalesce(br.cooking_method, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_cooking_method,
      ARRAY(
        SELECT lower(btrim(value))
        FROM unnest(coalesce(br.flavor, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_flavor,
      ARRAY(
        SELECT lower(btrim(value))
        FROM unnest(coalesce(br.texture, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_texture,
      ARRAY(
        SELECT lower(btrim(value))
        FROM unnest(coalesce(br.dietary_tags, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_dietary_tags,
      ARRAY(
        SELECT lower(btrim(value))
        FROM unnest(coalesce(br.tags, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_tags,
      lower(btrim(coalesce(a.name, ''))) AS normalized_author_name,
      lower(btrim(coalesce(a.handle, ''))) AS normalized_author_handle
    FROM public.browsable_recipes br
    LEFT JOIN public.authors a ON a.id = br.author_id
    WHERE (
        br.visibility_status = 'published'
        OR (br.visibility_status = 'dev_only' AND p_include_dev_only)
      )
      AND (p_platform IS NULL OR br.platform = p_platform)
  )
  SELECT
    vr.id,
    vr.meal_name,
    vr.meal_description,
    vr.image_url,
    vr.cooking_time,
    vr.author_id,
    vr.author,
    vr.platform,
    vr.tags,
    vr.cuisine_type,
    vr.difficulty_level,
    vr.featured,
    vr.view_count,
    vr.posted_date,
    count(*) OVER() AS total_count
  FROM visible_recipes vr
  CROSS JOIN params
  WHERE (params.tags IS NULL OR vr.normalized_tags && params.tags)
    AND (params.cuisine_types IS NULL OR vr.normalized_cuisine_type = ANY(params.cuisine_types))
    AND (params.meal_types IS NULL OR vr.normalized_meal_types && params.meal_types)
    AND (params.main_ingredient IS NULL OR vr.normalized_main_ingredient && params.main_ingredient)
    AND (params.cooking_method IS NULL OR vr.normalized_cooking_method && params.cooking_method)
    AND (params.flavor IS NULL OR vr.normalized_flavor && params.flavor)
    AND (params.texture IS NULL OR vr.normalized_texture && params.texture)
    AND (params.dietary_tags IS NULL OR vr.normalized_dietary_tags @> params.dietary_tags)
    AND (params.max_cooking_time IS NULL OR vr.cooking_time <= params.max_cooking_time)
    AND (
      params.author_search IS NULL
      OR vr.normalized_author_name LIKE '%' || params.author_search || '%'
      OR vr.normalized_author_handle LIKE '%' || params.author_search || '%'
    )
    AND (
      params.search_query IS NULL
      OR NOT EXISTS (
        SELECT 1
        FROM unnest(
          regexp_split_to_array(lower(params.search_query), '[,[:space:]]+')
        ) AS token(value)
        WHERE token.value <> ''
          AND NOT (
            lower(vr.meal_name) LIKE '%' || token.value || '%'
            OR lower(coalesce(vr.meal_description, '')) LIKE '%' || token.value || '%'
            OR lower(array_to_string(vr.tags, ' ')) LIKE '%' || token.value || '%'
            OR EXISTS (
              SELECT 1
              FROM public.imported_content_ingredients ici
              INNER JOIN public.imported_content_sub_ingredients icsi
                ON icsi.imported_content_ingredient_id = ici.id
              WHERE ici.imported_content_id = vr.imported_content_id
                AND lower(icsi.name) LIKE '%' || token.value || '%'
            )
          )
      )
    )
  ORDER BY vr.posted_date DESC NULLS LAST
  LIMIT p_limit
  OFFSET p_offset;
$$;

COMMENT ON FUNCTION public.search_browsable_recipes_filtered(
  integer,
  integer,
  text,
  text,
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  integer,
  public.social_media_platform,
  text[],
  boolean
)
IS 'List published browsable recipes with tokenized text search, author filter, taxonomy filters, and row-level total_count. p_include_dev_only should be true only in development.';

GRANT EXECUTE ON FUNCTION public.search_browsable_recipes_filtered(
  integer,
  integer,
  text,
  text,
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  integer,
  public.social_media_platform,
  text[],
  boolean
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.search_browsable_recipes_filtered(
  integer,
  integer,
  text,
  text,
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  integer,
  public.social_media_platform,
  text[],
  boolean
) TO service_role;
