-- Migration: Add onboarding starter recipes RPC.
-- Fetches scored starter recipe candidates for onboarding taxonomy selections.

CREATE OR REPLACE FUNCTION public.get_onboarding_starter_recipes(
  p_cuisine_types text[] DEFAULT NULL,
  p_meal_types text[] DEFAULT NULL,
  p_course text[] DEFAULT NULL,
  p_main_ingredient text[] DEFAULT NULL,
  p_dietary_tags text[] DEFAULT NULL,
  p_cooking_method text[] DEFAULT NULL,
  p_flavor text[] DEFAULT NULL,
  p_occasion text[] DEFAULT NULL,
  p_texture text[] DEFAULT NULL,
  p_difficulty_levels public.recipe_difficulty[] DEFAULT NULL,
  p_tags text[] DEFAULT NULL,
  p_legacy_meal_types text[] DEFAULT NULL,
  p_max_cooking_time integer DEFAULT NULL,
  p_limit integer DEFAULT 8,
  p_include_dev_only boolean DEFAULT false
)
RETURNS TABLE (
  id uuid,
  meal_name text,
  meal_description text,
  image_url text,
  cooking_time integer,
  cuisine_type text,
  meal_types text[],
  course text[],
  main_ingredient text[],
  dietary_tags text[],
  cooking_method text[],
  flavor text[],
  occasion text[],
  texture text[],
  difficulty_level public.recipe_difficulty,
  tags text[],
  author_id uuid,
  author jsonb,
  platform public.social_media_platform,
  original_post_url text,
  view_count integer,
  save_count integer,
  published_at timestamptz,
  match_score integer,
  matched_fields text[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH raw_params AS (
    SELECT
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
        FROM unnest(coalesce(p_course, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS course,
      ARRAY(
        SELECT DISTINCT lower(btrim(value))
        FROM unnest(coalesce(p_main_ingredient, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS main_ingredient,
      ARRAY(
        SELECT DISTINCT lower(btrim(value))
        FROM unnest(coalesce(p_dietary_tags, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS dietary_tags,
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
        FROM unnest(coalesce(p_occasion, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS occasion,
      ARRAY(
        SELECT DISTINCT lower(btrim(value))
        FROM unnest(coalesce(p_texture, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS texture,
      ARRAY(
        SELECT DISTINCT value
        FROM unnest(coalesce(p_difficulty_levels, ARRAY[]::public.recipe_difficulty[])) AS value
      ) AS difficulty_levels,
      ARRAY(
        SELECT DISTINCT lower(btrim(value))
        FROM unnest(coalesce(p_tags, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS tags,
      ARRAY(
        SELECT DISTINCT lower(btrim(value))
        FROM unnest(coalesce(p_legacy_meal_types, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS legacy_meal_types,
      p_max_cooking_time AS max_cooking_time,
      greatest(1, least(coalesce(p_limit, 8), 50)) AS result_limit
  ),
  params AS (
    SELECT
      CASE WHEN cardinality(cuisine_types) = 0 THEN NULL ELSE cuisine_types END AS cuisine_types,
      CASE WHEN cardinality(meal_types) = 0 THEN NULL ELSE meal_types END AS meal_types,
      CASE WHEN cardinality(course) = 0 THEN NULL ELSE course END AS course,
      CASE WHEN cardinality(main_ingredient) = 0 THEN NULL ELSE main_ingredient END AS main_ingredient,
      CASE WHEN cardinality(dietary_tags) = 0 THEN NULL ELSE dietary_tags END AS dietary_tags,
      CASE WHEN cardinality(cooking_method) = 0 THEN NULL ELSE cooking_method END AS cooking_method,
      CASE WHEN cardinality(flavor) = 0 THEN NULL ELSE flavor END AS flavor,
      CASE WHEN cardinality(occasion) = 0 THEN NULL ELSE occasion END AS occasion,
      CASE WHEN cardinality(texture) = 0 THEN NULL ELSE texture END AS texture,
      CASE WHEN cardinality(difficulty_levels) = 0 THEN NULL ELSE difficulty_levels END AS difficulty_levels,
      CASE WHEN cardinality(tags) = 0 THEN NULL ELSE tags END AS tags,
      CASE WHEN cardinality(legacy_meal_types) = 0 THEN NULL ELSE legacy_meal_types END AS legacy_meal_types,
      max_cooking_time,
      result_limit,
      greatest(result_limit * 4, 24) AS candidate_limit
    FROM raw_params
  ),
  visible_recipes AS (
    SELECT
      br.id,
      br.meal_name,
      br.meal_description,
      br.image_url,
      br.cooking_time,
      br.cuisine_type,
      coalesce(br.meal_types, ARRAY[]::text[]) AS meal_types,
      coalesce(br.course, ARRAY[]::text[]) AS course,
      coalesce(br.main_ingredient, ARRAY[]::text[]) AS main_ingredient,
      coalesce(br.dietary_tags, ARRAY[]::text[]) AS dietary_tags,
      coalesce(br.cooking_method, ARRAY[]::text[]) AS cooking_method,
      coalesce(br.flavor, ARRAY[]::text[]) AS flavor,
      coalesce(br.occasion, ARRAY[]::text[]) AS occasion,
      coalesce(br.texture, ARRAY[]::text[]) AS texture,
      br.difficulty_level,
      coalesce(br.tags, ARRAY[]::text[]) AS tags,
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
      br.original_post_url,
      coalesce(br.view_count, 0) AS view_count,
      coalesce(br.save_count, 0) AS save_count,
      br.published_at,
      lower(btrim(coalesce(br.cuisine_type, ''))) AS normalized_cuisine_type,
      ARRAY(
        SELECT lower(btrim(value))
        FROM unnest(coalesce(br.meal_types, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_meal_types,
      ARRAY(
        SELECT lower(btrim(value))
        FROM unnest(coalesce(br.course, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_course,
      ARRAY(
        SELECT lower(btrim(value))
        FROM unnest(coalesce(br.main_ingredient, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_main_ingredient,
      ARRAY(
        SELECT lower(btrim(value))
        FROM unnest(coalesce(br.dietary_tags, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_dietary_tags,
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
        FROM unnest(coalesce(br.occasion, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_occasion,
      ARRAY(
        SELECT lower(btrim(value))
        FROM unnest(coalesce(br.texture, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_texture,
      ARRAY(
        SELECT lower(btrim(value))
        FROM unnest(coalesce(br.tags, ARRAY[]::text[])) AS value
        WHERE btrim(value) <> ''
      ) AS normalized_tags,
      lower(btrim(coalesce(br.meal_type, ''))) AS normalized_legacy_meal_type
    FROM public.browsable_recipes br
    LEFT JOIN public.authors a ON a.id = br.author_id
    WHERE (
        br.visibility_status = 'published'
        OR (br.visibility_status = 'dev_only' AND p_include_dev_only)
      )
  ),
  match_eval AS (
    SELECT
      vr.*,
      params.result_limit,
      params.candidate_limit,
      (
        params.cuisine_types IS NOT NULL
        AND vr.normalized_cuisine_type = ANY(params.cuisine_types)
      ) AS cuisine_match,
      (
        params.meal_types IS NOT NULL
        AND vr.normalized_meal_types && params.meal_types
      ) AS meal_types_match,
      (
        params.occasion IS NOT NULL
        AND vr.normalized_occasion && params.occasion
      ) AS occasion_match,
      (
        params.course IS NOT NULL
        AND vr.normalized_course && params.course
      ) AS course_match,
      (
        params.main_ingredient IS NOT NULL
        AND vr.normalized_main_ingredient && params.main_ingredient
      ) AS main_ingredient_match,
      (
        params.cooking_method IS NOT NULL
        AND vr.normalized_cooking_method && params.cooking_method
      ) AS cooking_method_match,
      (
        params.flavor IS NOT NULL
        AND vr.normalized_flavor && params.flavor
      ) AS flavor_match,
      (
        params.texture IS NOT NULL
        AND vr.normalized_texture && params.texture
      ) AS texture_match,
      (
        params.dietary_tags IS NOT NULL
        AND vr.normalized_dietary_tags && params.dietary_tags
      ) AS dietary_tags_match,
      (
        params.difficulty_levels IS NOT NULL
        AND vr.difficulty_level = ANY(params.difficulty_levels)
      ) AS difficulty_level_match,
      (
        params.max_cooking_time IS NOT NULL
        AND vr.cooking_time IS NOT NULL
        AND vr.cooking_time <= params.max_cooking_time
      ) AS cooking_time_match,
      (
        params.tags IS NOT NULL
        AND vr.normalized_tags && params.tags
      ) AS tags_match,
      (
        params.legacy_meal_types IS NOT NULL
        AND vr.normalized_legacy_meal_type = ANY(params.legacy_meal_types)
      ) AS legacy_meal_type_match
    FROM visible_recipes vr
    CROSS JOIN params
  ),
  scored AS (
    SELECT
      me.*,
      (
        CASE WHEN cuisine_match THEN 30 ELSE 0 END
        + CASE WHEN meal_types_match THEN 30 ELSE 0 END
        + CASE WHEN occasion_match THEN 30 ELSE 0 END
        + CASE WHEN course_match THEN 20 ELSE 0 END
        + CASE WHEN main_ingredient_match THEN 15 ELSE 0 END
        + CASE WHEN cooking_method_match THEN 15 ELSE 0 END
        + CASE WHEN flavor_match THEN 15 ELSE 0 END
        + CASE WHEN texture_match THEN 10 ELSE 0 END
        + CASE WHEN dietary_tags_match THEN 10 ELSE 0 END
        + CASE WHEN difficulty_level_match THEN 10 ELSE 0 END
        + CASE WHEN cooking_time_match THEN 10 ELSE 0 END
        + CASE WHEN tags_match THEN 8 ELSE 0 END
        + CASE WHEN legacy_meal_type_match THEN 5 ELSE 0 END
      ) AS match_score,
      array_remove(ARRAY[
        CASE WHEN cuisine_match THEN 'cuisine_type' END,
        CASE WHEN meal_types_match THEN 'meal_types' END,
        CASE WHEN occasion_match THEN 'occasion' END,
        CASE WHEN course_match THEN 'course' END,
        CASE WHEN main_ingredient_match THEN 'main_ingredient' END,
        CASE WHEN cooking_method_match THEN 'cooking_method' END,
        CASE WHEN flavor_match THEN 'flavor' END,
        CASE WHEN texture_match THEN 'texture' END,
        CASE WHEN dietary_tags_match THEN 'dietary_tags' END,
        CASE WHEN difficulty_level_match THEN 'difficulty_level' END,
        CASE WHEN cooking_time_match THEN 'cooking_time' END,
        CASE WHEN tags_match THEN 'tags' END,
        CASE WHEN legacy_meal_type_match THEN 'legacy_meal_type' END
      ], NULL) AS matched_fields
    FROM match_eval me
  ),
  pooled AS (
    SELECT *
    FROM (
      SELECT
        scored.*,
        row_number() OVER (
          ORDER BY
            scored.match_score DESC,
            (scored.image_url IS NOT NULL) DESC,
            (scored.cooking_time IS NOT NULL) DESC,
            scored.save_count DESC,
            scored.view_count DESC,
            scored.published_at DESC NULLS LAST,
            scored.id
        ) AS pool_rank
      FROM scored
    ) ranked_pool
    WHERE ranked_pool.pool_rank <= ranked_pool.candidate_limit
  ),
  deduped AS (
    SELECT *
    FROM (
      SELECT
        pooled.*,
        row_number() OVER (
          PARTITION BY lower(btrim(pooled.meal_name))
          ORDER BY
            pooled.match_score DESC,
            (pooled.image_url IS NOT NULL) DESC,
            (pooled.cooking_time IS NOT NULL) DESC,
            pooled.save_count DESC,
            pooled.view_count DESC,
            pooled.published_at DESC NULLS LAST,
            pooled.id
        ) AS meal_name_rank
      FROM pooled
    ) ranked_names
    WHERE ranked_names.meal_name_rank = 1
  ),
  variety_ranked AS (
    SELECT
      deduped.*,
      row_number() OVER (
        PARTITION BY coalesce(nullif(deduped.normalized_cuisine_type, ''), deduped.id::text)
        ORDER BY
          deduped.match_score DESC,
          (deduped.image_url IS NOT NULL) DESC,
          (deduped.cooking_time IS NOT NULL) DESC,
          deduped.save_count DESC,
          deduped.view_count DESC,
          deduped.published_at DESC NULLS LAST,
          deduped.id
      ) AS cuisine_rank
    FROM deduped
  )
  SELECT
    variety_ranked.id,
    variety_ranked.meal_name,
    variety_ranked.meal_description,
    variety_ranked.image_url,
    variety_ranked.cooking_time,
    variety_ranked.cuisine_type,
    variety_ranked.meal_types,
    variety_ranked.course,
    variety_ranked.main_ingredient,
    variety_ranked.dietary_tags,
    variety_ranked.cooking_method,
    variety_ranked.flavor,
    variety_ranked.occasion,
    variety_ranked.texture,
    variety_ranked.difficulty_level,
    variety_ranked.tags,
    variety_ranked.author_id,
    variety_ranked.author,
    variety_ranked.platform,
    variety_ranked.original_post_url,
    variety_ranked.view_count,
    variety_ranked.save_count,
    variety_ranked.published_at,
    variety_ranked.match_score,
    variety_ranked.matched_fields
  FROM variety_ranked
  ORDER BY
    CASE WHEN variety_ranked.cuisine_rank <= 2 THEN 0 ELSE 1 END,
    variety_ranked.match_score DESC,
    (variety_ranked.image_url IS NOT NULL) DESC,
    (variety_ranked.cooking_time IS NOT NULL) DESC,
    variety_ranked.save_count DESC,
    variety_ranked.view_count DESC,
    variety_ranked.published_at DESC NULLS LAST,
    variety_ranked.id
  LIMIT (SELECT result_limit FROM params);
$$;

COMMENT ON FUNCTION public.get_onboarding_starter_recipes(
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  public.recipe_difficulty[],
  text[],
  text[],
  integer,
  integer,
  boolean
)
IS 'Return scored starter recipe candidates for onboarding taxonomy selections, with fallback to popular/newer published recipes. p_include_dev_only should be true only in development.';

GRANT EXECUTE ON FUNCTION public.get_onboarding_starter_recipes(
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  public.recipe_difficulty[],
  text[],
  text[],
  integer,
  integer,
  boolean
) TO anon, authenticated, service_role;
