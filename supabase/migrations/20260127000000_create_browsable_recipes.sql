-- Migration: Create browsable_recipes table and supporting infrastructure
-- Created: 2026-01-27
-- Description: Phase 1 implementation of browsable recipes feature
-- This migration creates the database infrastructure for browsable recipes including
-- custom types, table, indexes, triggers, functions, and RLS policies.

-- Step 1: Create custom enum types
CREATE TYPE social_media_platform AS ENUM (
    'tiktok',
    'youtube',
    'instagram',
    'website',
    'other'
);

CREATE TYPE visibility_status AS ENUM (
    'draft',
    'published',
    'archived',
    'removed'
);

CREATE TYPE recipe_difficulty AS ENUM (
    'easy',
    'medium',
    'hard'
);

-- Step 2: Create browsable_recipes table
CREATE TABLE browsable_recipes (
    -- Primary identifiers
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    imported_content_id UUID NOT NULL,
    
    -- Core recipe information (denormalized for performance)
    meal_name TEXT NOT NULL,
    meal_description TEXT,
    image_url TEXT,
    cooking_time INTEGER, -- in minutes
    serving_suggestions INTEGER,
    
    -- Social media metadata
    author_name TEXT,
    author_handle TEXT,
    author_profile_url TEXT,
    platform social_media_platform NOT NULL,
    original_post_url TEXT NOT NULL,
    posted_date TIMESTAMPTZ,
    engagement_metrics JSONB, -- likes, shares, comments, views
    
    -- Categorization and discovery
    tags TEXT[] DEFAULT '{}',
    cuisine_type TEXT,
    meal_type TEXT, -- breakfast, lunch, dinner, snack, dessert
    dietary_tags TEXT[] DEFAULT '{}', -- vegan, vegetarian, gluten-free, etc.
    difficulty_level recipe_difficulty,
    
    -- Platform-specific metadata
    platform_metadata JSONB, -- flexible storage for platform-specific data
    
    -- Curation and visibility
    visibility_status visibility_status NOT NULL DEFAULT 'draft',
    featured BOOLEAN DEFAULT false,
    featured_until TIMESTAMPTZ,
    curator_id UUID, -- user_profile.id of who added this to browsable
    curation_notes TEXT,
    
    -- Engagement tracking
    view_count INTEGER DEFAULT 0,
    save_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,
    
    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ,
    
    -- Constraints
    CONSTRAINT fk_imported_content 
        FOREIGN KEY (imported_content_id) 
        REFERENCES imported_content(id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_curator 
        FOREIGN KEY (curator_id) 
        REFERENCES user_profile(id) 
        ON DELETE SET NULL,
    CONSTRAINT unique_browsable_recipe 
        UNIQUE (imported_content_id)
);

-- Step 3: Create indexes for performance
CREATE INDEX idx_browsable_recipes_platform ON browsable_recipes(platform);
CREATE INDEX idx_browsable_recipes_visibility ON browsable_recipes(visibility_status);
CREATE INDEX idx_browsable_recipes_featured ON browsable_recipes(featured, featured_until);
CREATE INDEX idx_browsable_recipes_published ON browsable_recipes(published_at DESC);
CREATE INDEX idx_browsable_recipes_tags ON browsable_recipes USING gin(tags);
CREATE INDEX idx_browsable_recipes_dietary ON browsable_recipes USING gin(dietary_tags);
CREATE INDEX idx_browsable_recipes_cuisine ON browsable_recipes(cuisine_type);
CREATE INDEX idx_browsable_recipes_meal_type ON browsable_recipes(meal_type);
CREATE INDEX idx_browsable_recipes_imported_content ON browsable_recipes(imported_content_id);
CREATE INDEX idx_browsable_recipes_curator ON browsable_recipes(curator_id);

-- Step 4: Create trigger function for updated_at
CREATE OR REPLACE FUNCTION update_browsable_recipes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_browsable_recipes_timestamp
    BEFORE UPDATE ON browsable_recipes
    FOR EACH ROW
    EXECUTE FUNCTION update_browsable_recipes_updated_at();

-- Step 5: Create helper functions

-- Function: create_browsable_recipe()
-- Creates a new browsable recipe from an imported content record
CREATE OR REPLACE FUNCTION create_browsable_recipe(
    p_imported_content_id UUID,
    p_author_name TEXT DEFAULT NULL,
    p_author_handle TEXT DEFAULT NULL,
    p_platform social_media_platform DEFAULT 'website',
    p_tags TEXT[] DEFAULT '{}',
    p_curator_id UUID DEFAULT NULL
) RETURNS UUID
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
DECLARE
    v_recipe_id UUID;
    v_content JSONB;
    v_metadata JSONB;
    v_source_url TEXT;
    v_serving_suggestions INTEGER;
BEGIN
    -- Fetch the imported content
    SELECT content, metadata, source_url
    INTO v_content, v_metadata, v_source_url
    FROM imported_content
    WHERE id = p_imported_content_id
    AND is_recipe_content = true
    AND status = 'COMPLETED';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Recipe content not found or not completed';
    END IF;
    
    -- Handle serving_suggestions (support both singular and plural)
    v_serving_suggestions := NULL;
    IF v_content ? 'serving_suggestion' THEN
        v_serving_suggestions := (v_content->>'serving_suggestion')::INTEGER;
    ELSIF v_content ? 'serving_suggestions' THEN
        v_serving_suggestions := (v_content->>'serving_suggestions')::INTEGER;
    END IF;
    
    -- Insert browsable recipe
    INSERT INTO browsable_recipes (
        imported_content_id,
        meal_name,
        meal_description,
        image_url,
        cooking_time,
        serving_suggestions,
        author_name,
        author_handle,
        platform,
        original_post_url,
        tags,
        curator_id,
        visibility_status
    ) VALUES (
        p_imported_content_id,
        v_content->>'meal_name',
        v_content->>'meal_description',
        v_content->>'image_url', -- NULL if not present
        (v_content->>'cooking_time')::INTEGER,
        v_serving_suggestions,
        p_author_name,
        p_author_handle,
        p_platform,
        v_source_url,
        p_tags,
        p_curator_id,
        'draft'
    )
    RETURNING id INTO v_recipe_id;
    
    RETURN v_recipe_id;
END;
$$;

-- Function: publish_browsable_recipe()
-- Publishes a draft recipe, making it visible to users
CREATE OR REPLACE FUNCTION publish_browsable_recipe(
    p_recipe_id UUID
) RETURNS BOOLEAN
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE browsable_recipes
    SET 
        visibility_status = 'published',
        published_at = now(),
        updated_at = now()
    WHERE id = p_recipe_id
    AND visibility_status = 'draft';
    
    RETURN FOUND;
END;
$$;

-- Function: increment_recipe_views()
-- Increments the view count for a recipe
CREATE OR REPLACE FUNCTION increment_recipe_views(
    p_recipe_id UUID
) RETURNS INTEGER
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
DECLARE
    v_new_count INTEGER;
BEGIN
    UPDATE browsable_recipes
    SET 
        view_count = view_count + 1,
        updated_at = now()
    WHERE id = p_recipe_id
    RETURNING view_count INTO v_new_count;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Recipe not found';
    END IF;
    
    RETURN v_new_count;
END;
$$;

-- Function: get_published_recipes()
-- Retrieves published recipes with pagination and filtering
CREATE OR REPLACE FUNCTION get_published_recipes(
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0,
    p_platform social_media_platform DEFAULT NULL,
    p_tags TEXT[] DEFAULT NULL
) RETURNS TABLE (
    id UUID,
    meal_name TEXT,
    meal_description TEXT,
    image_url TEXT,
    cooking_time INTEGER,
    platform social_media_platform,
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
    FROM browsable_recipes br
    WHERE br.visibility_status = 'published'
    AND (p_platform IS NULL OR br.platform = p_platform)
    AND (p_tags IS NULL OR br.tags && p_tags)
    ORDER BY br.published_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;

-- Step 6: Enable RLS and create policies
ALTER TABLE browsable_recipes ENABLE ROW LEVEL SECURITY;

-- Policy 1: All authenticated users can view published recipes
CREATE POLICY "view_published_recipes"
ON browsable_recipes
FOR SELECT
TO authenticated
USING (visibility_status = 'published');

-- Policy 2: Curators can view all recipes (including drafts)
CREATE POLICY "curators_view_all"
ON browsable_recipes
FOR SELECT
TO authenticated
USING (
    curator_id IN (
        SELECT id FROM user_profile 
        WHERE auth_id = auth.uid() 
        AND is_pro = true
    )
);

-- Policy 3: Curators can insert new browsable recipes
CREATE POLICY "curators_insert_recipes"
ON browsable_recipes
FOR INSERT
TO authenticated
WITH CHECK (
    curator_id IN (
        SELECT id FROM user_profile 
        WHERE auth_id = auth.uid() 
        AND is_pro = true
    )
);

-- Policy 4: Curators can update recipes they curated
CREATE POLICY "curators_update_own_recipes"
ON browsable_recipes
FOR UPDATE
TO authenticated
USING (
    curator_id IN (
        SELECT id FROM user_profile 
        WHERE auth_id = auth.uid()
    )
);

-- Note: No DELETE policy - use visibility_status = 'removed' for soft deletes

-- Step 7: Grant permissions
GRANT ALL ON TABLE browsable_recipes TO authenticated;
GRANT ALL ON TABLE browsable_recipes TO service_role;

-- Grant execute permissions on functions
GRANT EXECUTE ON FUNCTION create_browsable_recipe(UUID, TEXT, TEXT, social_media_platform, TEXT[], UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION create_browsable_recipe(UUID, TEXT, TEXT, social_media_platform, TEXT[], UUID) TO service_role;

GRANT EXECUTE ON FUNCTION publish_browsable_recipe(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION publish_browsable_recipe(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION increment_recipe_views(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION increment_recipe_views(UUID) TO service_role;

GRANT EXECUTE ON FUNCTION get_published_recipes(INTEGER, INTEGER, social_media_platform, TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION get_published_recipes(INTEGER, INTEGER, social_media_platform, TEXT[]) TO service_role;
