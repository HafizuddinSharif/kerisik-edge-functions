-- Migration: Add general collection listing RPC that can optionally include dev_only.
-- Needed because RLS hides dev_only from anon users on direct selects.

CREATE OR REPLACE FUNCTION public.get_collections(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0,
  p_type text DEFAULT NULL,
  p_search text DEFAULT NULL,
  p_is_featured boolean DEFAULT NULL,
  p_include_dev_only boolean DEFAULT false
)
RETURNS TABLE (
  id uuid,
  name text,
  description text,
  type text,
  visibility text,
  cover_image_url text,
  icon text,
  color_theme text,
  created_by_user_id uuid,
  author_id uuid,
  recipe_count integer,
  view_count integer,
  slug text,
  tags text[],
  created_at timestamptz,
  updated_at timestamptz,
  is_featured boolean,
  featured_order integer,
  featured_at timestamptz,
  total_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id,
    c.name,
    c.description,
    c.type::text AS type,
    c.visibility::text AS visibility,
    c.cover_image_url,
    c.icon,
    c.color_theme,
    c.created_by_user_id,
    c.author_id,
    c.recipe_count,
    c.view_count,
    c.slug,
    c.tags,
    c.created_at,
    c.updated_at,
    c.is_featured,
    c.featured_order,
    c.featured_at,
    count(*) OVER() AS total_count
  FROM public.collections c
  WHERE
    (
      CASE
        WHEN p_include_dev_only
          THEN c.visibility::text IN ('public', 'dev_only')
        ELSE c.visibility::text = 'public'
      END
    )
    AND (p_type IS NULL OR c.type::text = p_type)
    AND (p_is_featured IS NULL OR c.is_featured = p_is_featured)
    AND (
      p_search IS NULL
      OR c.name ILIKE '%' || p_search || '%'
      OR coalesce(c.description, '') ILIKE '%' || p_search || '%'
    )
  ORDER BY c.view_count DESC
  LIMIT p_limit
  OFFSET p_offset;
$$;

COMMENT ON FUNCTION public.get_collections(integer, integer, text, text, boolean, boolean)
IS 'General collection listing RPC. p_include_dev_only should be true only in development.';

GRANT EXECUTE ON FUNCTION public.get_collections(integer, integer, text, text, boolean, boolean) TO anon, authenticated;
