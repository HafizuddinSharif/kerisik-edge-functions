-- Migration: Create authors table and refactor browsable_recipes to use author_id
-- Created: 2026-02-01
-- Description: Extracts author data from browsable_recipes into a dedicated authors table,
-- adds author_id FK to browsable_recipes, and updates create_browsable_recipe function.

-- Step 1: Create authors table
CREATE TABLE authors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT,
    handle TEXT,
    profile_url TEXT,
    profile_pic_url TEXT,
    platform social_media_platform NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Partial unique index: (platform, profile_url) unique when profile_url is provided
-- Allows multiple authors with NULL profile_url (e.g. anonymous website authors)
CREATE UNIQUE INDEX unique_author_per_platform ON authors (platform, profile_url) WHERE profile_url IS NOT NULL;

-- Index for lookups by platform and profile_url
CREATE INDEX idx_authors_platform_profile_url ON authors (platform, profile_url);

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_authors_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_authors_timestamp
    BEFORE UPDATE ON authors
    FOR EACH ROW
    EXECUTE FUNCTION update_authors_updated_at();

-- Step 2: Insert distinct authors from existing browsable_recipes
-- Only migrate rows where at least one author field is non-null
INSERT INTO authors (name, handle, profile_url, profile_pic_url, platform)
SELECT DISTINCT ON (br.platform, COALESCE(br.author_profile_url, ''), COALESCE(br.author_handle, ''), COALESCE(br.author_name, ''))
    br.author_name,
    br.author_handle,
    br.author_profile_url,
    NULL,  -- profile_pic_url not stored previously
    br.platform
FROM browsable_recipes br
WHERE br.author_name IS NOT NULL
   OR br.author_handle IS NOT NULL
   OR br.author_profile_url IS NOT NULL
ORDER BY br.platform, COALESCE(br.author_profile_url, ''), COALESCE(br.author_handle, ''), COALESCE(br.author_name, ''), br.id;

-- Step 3: Add author_id column to browsable_recipes
ALTER TABLE browsable_recipes ADD COLUMN author_id UUID;

-- Step 4: Update browsable_recipes.author_id by matching authors
UPDATE browsable_recipes br
SET author_id = a.id
FROM authors a
WHERE a.platform = br.platform
  AND (
    (br.author_profile_url IS NOT NULL AND a.profile_url = br.author_profile_url)
    OR (br.author_profile_url IS NULL AND br.author_handle IS NOT NULL AND a.handle = br.author_handle AND a.profile_url IS NULL AND (br.author_name IS NULL OR a.name = br.author_name))
    OR (br.author_profile_url IS NULL AND br.author_handle IS NULL AND br.author_name IS NOT NULL AND a.name = br.author_name AND a.profile_url IS NULL AND a.handle IS NULL)
  );

-- Step 5: Drop author columns from browsable_recipes
ALTER TABLE browsable_recipes DROP COLUMN author_name;
ALTER TABLE browsable_recipes DROP COLUMN author_handle;
ALTER TABLE browsable_recipes DROP COLUMN author_profile_url;

-- Step 6: Add FK constraint
ALTER TABLE browsable_recipes
    ADD CONSTRAINT fk_author
    FOREIGN KEY (author_id)
    REFERENCES authors(id)
    ON DELETE SET NULL;

-- Step 7: Add index on author_id
CREATE INDEX idx_browsable_recipes_author ON browsable_recipes(author_id);

-- Step 8: Create get_or_create_author helper function
CREATE OR REPLACE FUNCTION get_or_create_author(
    p_platform social_media_platform,
    p_name TEXT DEFAULT NULL,
    p_handle TEXT DEFAULT NULL,
    p_profile_url TEXT DEFAULT NULL,
    p_profile_pic_url TEXT DEFAULT NULL
) RETURNS UUID
SECURITY DEFINER
LANGUAGE plpgsql
AS $$
DECLARE
    v_author_id UUID;
BEGIN
    -- Try to find existing author by (platform, profile_url) when profile_url is provided
    IF p_profile_url IS NOT NULL THEN
        SELECT id INTO v_author_id
        FROM authors
        WHERE platform = p_platform AND profile_url = p_profile_url
        LIMIT 1;
        IF FOUND THEN
            -- Optionally update profile_pic_url if we have a new one
            IF p_profile_pic_url IS NOT NULL THEN
                UPDATE authors
                SET profile_pic_url = COALESCE(profile_pic_url, p_profile_pic_url),
                    name = COALESCE(name, p_name),
                    handle = COALESCE(handle, p_handle),
                    updated_at = now()
                WHERE id = v_author_id;
            END IF;
            RETURN v_author_id;
        END IF;
    END IF;

    -- Try to find by (platform, handle) when profile_url is NULL
    IF p_profile_url IS NULL AND p_handle IS NOT NULL THEN
        SELECT id INTO v_author_id
        FROM authors
        WHERE platform = p_platform AND profile_url IS NULL AND handle = p_handle
        LIMIT 1;
        IF FOUND THEN
            IF p_profile_pic_url IS NOT NULL THEN
                UPDATE authors
                SET profile_pic_url = COALESCE(profile_pic_url, p_profile_pic_url),
                    name = COALESCE(name, p_name),
                    updated_at = now()
                WHERE id = v_author_id;
            END IF;
            RETURN v_author_id;
        END IF;
    END IF;

    -- Insert new author
    INSERT INTO authors (name, handle, profile_url, profile_pic_url, platform)
    VALUES (p_name, p_handle, p_profile_url, p_profile_pic_url, p_platform)
    RETURNING id INTO v_author_id;
    RETURN v_author_id;
END;
$$;

-- Step 9: Rewrite create_browsable_recipe() with new signature
CREATE OR REPLACE FUNCTION create_browsable_recipe(
    p_imported_content_id UUID,
    p_author_name TEXT DEFAULT NULL,
    p_author_handle TEXT DEFAULT NULL,
    p_author_profile_url TEXT DEFAULT NULL,
    p_author_profile_pic_url TEXT DEFAULT NULL,
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
    v_author_id UUID;
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

    -- Resolve author_id if any author info provided
    v_author_id := NULL;
    IF p_author_name IS NOT NULL OR p_author_handle IS NOT NULL OR p_author_profile_url IS NOT NULL THEN
        v_author_id := get_or_create_author(
            p_platform,
            p_author_name,
            p_author_handle,
            p_author_profile_url,
            p_author_profile_pic_url
        );
    END IF;

    -- Insert browsable recipe
    INSERT INTO browsable_recipes (
        imported_content_id,
        meal_name,
        meal_description,
        image_url,
        cooking_time,
        serving_suggestions,
        author_id,
        platform,
        original_post_url,
        tags,
        curator_id,
        visibility_status
    ) VALUES (
        p_imported_content_id,
        v_content->>'meal_name',
        v_content->>'meal_description',
        v_content->>'image_url',
        (v_content->>'cooking_time')::INTEGER,
        v_serving_suggestions,
        v_author_id,
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

-- Step 10: Revoke old function grant and grant new signature
REVOKE EXECUTE ON FUNCTION create_browsable_recipe(UUID, TEXT, TEXT, social_media_platform, TEXT[], UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION create_browsable_recipe(UUID, TEXT, TEXT, social_media_platform, TEXT[], UUID) FROM service_role;

GRANT EXECUTE ON FUNCTION create_browsable_recipe(UUID, TEXT, TEXT, TEXT, TEXT, social_media_platform, TEXT[], UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION create_browsable_recipe(UUID, TEXT, TEXT, TEXT, TEXT, social_media_platform, TEXT[], UUID) TO service_role;

GRANT EXECUTE ON FUNCTION get_or_create_author(social_media_platform, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_or_create_author(social_media_platform, TEXT, TEXT, TEXT, TEXT) TO service_role;

-- Step 11: Grant permissions on authors table
GRANT ALL ON TABLE authors TO authenticated;
GRANT ALL ON TABLE authors TO service_role;
