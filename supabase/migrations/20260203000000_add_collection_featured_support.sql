-- Migration: 20260203000000_add_collection_featured_support
-- Description: Add featured collection support for the Recipe Collections Feature Page.
-- See docs/collection_feature_page.md for full design.
-- Requires: 20260202000000_create_recipe_collections.sql

-- 1. Add featured columns to collections table
ALTER TABLE collections
ADD COLUMN is_featured BOOLEAN DEFAULT false,
ADD COLUMN featured_order INTEGER,
ADD COLUMN featured_at TIMESTAMPTZ;

-- Add index for performance
CREATE INDEX idx_collections_featured
ON collections(is_featured, featured_order)
WHERE is_featured = true;

-- Add comments
COMMENT ON COLUMN collections.is_featured IS 'Whether this collection is featured on the main page';
COMMENT ON COLUMN collections.featured_order IS 'Sort order for featured collections (lower = higher priority)';
COMMENT ON COLUMN collections.featured_at IS 'When this collection was marked as featured';

-- 2. Create function for featured collections
CREATE OR REPLACE FUNCTION get_featured_collections(p_limit INTEGER DEFAULT 5)
RETURNS SETOF collections
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT *
  FROM collections
  WHERE visibility = 'public' AND is_featured = true
  ORDER BY featured_order ASC NULLS LAST, view_count DESC
  LIMIT p_limit;
$$;

COMMENT ON FUNCTION get_featured_collections IS 'Returns featured collections ordered by featured_order, then by popularity';

-- 3. Create function to set featured collection
CREATE OR REPLACE FUNCTION set_collection_featured(
  p_collection_id UUID,
  p_is_featured BOOLEAN,
  p_featured_order INTEGER DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE collections
  SET
    is_featured = p_is_featured,
    featured_order = p_featured_order,
    featured_at = CASE
      WHEN p_is_featured = true AND is_featured = false THEN now()
      WHEN p_is_featured = false THEN NULL
      ELSE featured_at
    END,
    updated_at = now()
  WHERE id = p_collection_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Collection with id % not found', p_collection_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION set_collection_featured IS 'Mark a collection as featured or unfeatured with optional order';

-- 4. Optional: Create collection_metrics table for tracking trends over time
CREATE TABLE collection_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  views INTEGER DEFAULT 0,
  recipe_additions INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(collection_id, date)
);

-- Add index for querying by collection and date range
CREATE INDEX idx_collection_metrics_collection_date
ON collection_metrics(collection_id, date DESC);

COMMENT ON TABLE collection_metrics IS 'Daily metrics for tracking collection performance over time';
