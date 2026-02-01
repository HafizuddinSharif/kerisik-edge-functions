# Product Requirements Document: Browsable Recipes Feature

**Version:** 1.0  
**Status:** Draft  
**Created:** January 15, 2026  
**Last Updated:** January 15, 2026  
**Owner:** [To be assigned]

---

## Executive Summary

This PRD outlines the implementation of a new Browsable Recipes feature that will enable users to discover and browse recipes from a curated collection. Phase 1 focuses on establishing the database infrastructure to store enriched recipe metadata, while Phase 2 (separate PRD) will cover the user-facing browsing experience.

---

## Table of Contents

1. [Background & Context](#background--context)
2. [Problem Statement](#problem-statement)
3. [Goals & Objectives](#goals--objectives)
4. [Scope](#scope)
5. [Phase 1: Database Schema & Infrastructure](#phase-1-database-schema--infrastructure)
6. [Technical Specifications](#technical-specifications)
7. [Data Model](#data-model)
8. [Migration Strategy](#migration-strategy)
9. [Security & Access Control](#security--access-control)
10. [Success Metrics](#success-metrics)
11. [Dependencies & Risks](#dependencies--risks)
12. [Timeline](#timeline)
13. [Appendix](#appendix)

---

## Background & Context

### Current State

The application currently supports recipe content extraction and storage through:
- **`imported_content` table**: Stores all imported content (recipes, videos, etc.)
- **Content extraction pipeline**: Processes URLs from social media platforms (TikTok, YouTube, Instagram) and websites
- **Recipe data format**: Structured as `RecipeResponseV2` with ingredients, steps, metadata stored in JSONB

### Current Limitations

1. **No curation mechanism**: All imported recipes are treated equally with no way to feature or highlight specific recipes
2. **Missing social context**: Recipe metadata lacks social media details (author, engagement metrics, original post date)
3. **No browse/discovery flow**: Users can only access recipes they've personally imported
4. **Limited searchability**: No tags or categorization system for content discovery

---

## Problem Statement

Users cannot discover recipes from other users or curated collections because:
1. There is no dedicated table for browsable/featured recipes
2. Social media metadata (author, posting date, platform-specific details) is not systematically captured
3. Categorization and tagging infrastructure does not exist

---

## Goals & Objectives

### Primary Goals

1. **Enable recipe discovery**: Create infrastructure to support a browsable recipe collection
2. **Preserve social context**: Capture and store original social media metadata for attribution and engagement
3. **Support curation**: Allow recipes to be marked as browsable/featured with proper categorization

### Secondary Goals

1. **Maintain data integrity**: Ensure browsable recipes remain linked to their source records
2. **Support future features**: Design schema to accommodate filtering, sorting, and recommendation systems
3. **Enable analytics**: Track which recipes are browsed and engaged with

---

## Scope

### Phase 1: In Scope

✅ Database schema design for `browsable_recipes` table  
✅ Migration scripts and implementation  
✅ Row Level Security (RLS) policies  
✅ Database functions for recipe management  
✅ Documentation and testing plan

### Phase 1: Out of Scope

❌ User interface for browsing recipes  
❌ API endpoints for recipe retrieval  
❌ Search and filtering logic  
❌ Recommendation algorithms  
❌ Admin interface for curating recipes

### Future Phases

**Phase 2**: Frontend implementation and API development (separate PRD)  
**Phase 3**: Advanced features (recommendations, user collections, sharing)

---

## Phase 1: Database Schema & Infrastructure

### Overview

Phase 1 establishes the foundational database infrastructure for browsable recipes by creating a new `browsable_recipes` table that extends the `imported_content` table with social metadata and curation features.

### Key Components

1. **New table**: `browsable_recipes`
2. **Custom types**: Enums for platforms, visibility, and content types
3. **Helper functions**: Recipe management and querying
4. **RLS policies**: Access control for browsable content
5. **Migration scripts**: Safe deployment to production

---

## Technical Specifications

### Database

- **Platform**: Supabase PostgreSQL
- **Schema**: `public`
- **RLS**: Enabled on all tables
- **Connection**: Uses existing Supabase instance

### Architecture Principles

1. **Referential integrity**: Foreign key from `browsable_recipes` to `imported_content`
2. **Denormalization for performance**: Store frequently accessed fields (meal_name, image_url) directly
3. **Flexibility**: JSONB for platform-specific metadata
4. **Extensibility**: Design to accommodate future features without breaking changes

---

## Data Model

### Entity Relationship

```
imported_content (existing)
    ↓ (1:1 relationship)
browsable_recipes (new)
    ↑ references via imported_content_id
    
user_profile (existing)
    ↑ (optional) references via curator_id
```

### Table: `browsable_recipes`

**Purpose**: Stores recipes that are available for browsing with enriched social media metadata and curation information.

#### Schema

```sql
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
```

#### Column Descriptions

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `gen_random_uuid()` | Primary key |
| `imported_content_id` | UUID | NO | - | FK to imported_content.id |
| `meal_name` | TEXT | NO | - | Name of the recipe |
| `meal_description` | TEXT | YES | NULL | Short description |
| `image_url` | TEXT | YES | NULL | Main recipe image URL |
| `cooking_time` | INTEGER | YES | NULL | Total cooking time in minutes |
| `serving_suggestions` | INTEGER | YES | NULL | Number of servings |
| `author_name` | TEXT | YES | NULL | Display name of content creator |
| `author_handle` | TEXT | YES | NULL | Social media handle (e.g., @username) |
| `author_profile_url` | TEXT | YES | NULL | Link to author's profile |
| `platform` | ENUM | NO | - | Source platform (tiktok, youtube, instagram, website) |
| `original_post_url` | TEXT | NO | - | Original URL of the recipe |
| `posted_date` | TIMESTAMPTZ | YES | NULL | When the content was posted on social media |
| `engagement_metrics` | JSONB | YES | NULL | Likes, shares, comments, views |
| `tags` | TEXT[] | YES | `'{}'` | General tags for filtering |
| `cuisine_type` | TEXT | YES | NULL | Cuisine category (Italian, Mexican, etc.) |
| `meal_type` | TEXT | YES | NULL | Meal category (breakfast, lunch, dinner, etc.) |
| `dietary_tags` | TEXT[] | YES | `'{}'` | Dietary restrictions/preferences |
| `difficulty_level` | ENUM | YES | NULL | easy, medium, hard |
| `platform_metadata` | JSONB | YES | NULL | Platform-specific additional data |
| `visibility_status` | ENUM | NO | 'draft' | draft, published, archived, removed |
| `featured` | BOOLEAN | NO | false | Whether recipe is featured |
| `featured_until` | TIMESTAMPTZ | YES | NULL | Expiry for featured status |
| `curator_id` | UUID | YES | NULL | User who curated this recipe |
| `curation_notes` | TEXT | YES | NULL | Internal notes about curation |
| `view_count` | INTEGER | NO | 0 | Number of views |
| `save_count` | INTEGER | NO | 0 | Number of saves |
| `share_count` | INTEGER | NO | 0 | Number of shares |
| `created_at` | TIMESTAMPTZ | NO | `now()` | Record creation timestamp |
| `updated_at` | TIMESTAMPTZ | NO | `now()` | Last update timestamp |
| `published_at` | TIMESTAMPTZ | YES | NULL | When recipe was published |

#### Indexes

```sql
-- Performance indexes
CREATE INDEX idx_browsable_recipes_platform ON browsable_recipes(platform);
CREATE INDEX idx_browsable_recipes_visibility ON browsable_recipes(visibility_status);
CREATE INDEX idx_browsable_recipes_featured ON browsable_recipes(featured, featured_until);
CREATE INDEX idx_browsable_recipes_published ON browsable_recipes(published_at DESC);
CREATE INDEX idx_browsable_recipes_tags ON browsable_recipes USING gin(tags);
CREATE INDEX idx_browsable_recipes_dietary ON browsable_recipes USING gin(dietary_tags);
CREATE INDEX idx_browsable_recipes_cuisine ON browsable_recipes(cuisine_type);
CREATE INDEX idx_browsable_recipes_meal_type ON browsable_recipes(meal_type);

-- Foreign key indexes
CREATE INDEX idx_browsable_recipes_imported_content ON browsable_recipes(imported_content_id);
CREATE INDEX idx_browsable_recipes_curator ON browsable_recipes(curator_id);
```

### Custom Types

#### `social_media_platform`

```sql
CREATE TYPE social_media_platform AS ENUM (
    'tiktok',
    'youtube',
    'instagram',
    'website',
    'other'
);
```

#### `visibility_status`

```sql
CREATE TYPE visibility_status AS ENUM (
    'draft',        -- Not yet published
    'published',    -- Live and browsable
    'archived',     -- No longer shown but preserved
    'removed'       -- Flagged or removed from browse
);
```

#### `recipe_difficulty`

```sql
CREATE TYPE recipe_difficulty AS ENUM (
    'easy',
    'medium',
    'hard'
);
```

### JSONB Schema Definitions

#### `engagement_metrics` Structure

```json
{
    "likes": 12500,
    "comments": 342,
    "shares": 856,
    "views": 125000,
    "saves": 3200,
    "engagement_rate": 0.0524,
    "last_updated": "2026-01-15T10:30:00Z"
}
```

#### `platform_metadata` Structure

**TikTok Example:**
```json
{
    "video_id": "7234567890123456789",
    "sound_name": "Original Sound - username",
    "hashtags": ["cooking", "recipe", "easymeal"],
    "video_duration": 45,
    "caption": "Quick 15-min pasta recipe 🍝",
    "trending_score": 8.5
}
```

**YouTube Example:**
```json
{
    "video_id": "dQw4w9WgXcQ",
    "channel_id": "UC1234567890",
    "channel_name": "Cooking Channel",
    "video_duration": 720,
    "category": "Howto & Style",
    "has_timestamp": true,
    "recipe_timestamp": "2:30"
}
```

**Instagram Example:**
```json
{
    "media_id": "1234567890123456789",
    "media_type": "reel",
    "music": "Trending Audio 2024",
    "location": "New York, NY",
    "hashtags": ["foodie", "recipe", "cooking"]
}
```

---

## Database Functions

### Function: `create_browsable_recipe()`

Creates a new browsable recipe from an imported content record.

```sql
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
        v_content->>'image_url',
        (v_content->>'cooking_time')::INTEGER,
        (v_content->>'serving_suggestions')::INTEGER,
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
```

### Function: `publish_browsable_recipe()`

Publishes a draft recipe, making it visible to users.

```sql
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
```

### Function: `increment_recipe_views()`

Increments the view count for a recipe.

```sql
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
```

### Function: `get_published_recipes()`

Retrieves published recipes with pagination.

```sql
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
```

---

## Migration Strategy

### Migration File: `20260115000000_create_browsable_recipes.sql`

```sql
-- Migration: Create browsable_recipes table and supporting infrastructure
-- Created: 2026-01-15

-- Step 1: Create custom types
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
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    imported_content_id UUID NOT NULL,
    
    meal_name TEXT NOT NULL,
    meal_description TEXT,
    image_url TEXT,
    cooking_time INTEGER,
    serving_suggestions INTEGER,
    
    author_name TEXT,
    author_handle TEXT,
    author_profile_url TEXT,
    platform social_media_platform NOT NULL,
    original_post_url TEXT NOT NULL,
    posted_date TIMESTAMPTZ,
    engagement_metrics JSONB,
    
    tags TEXT[] DEFAULT '{}',
    cuisine_type TEXT,
    meal_type TEXT,
    dietary_tags TEXT[] DEFAULT '{}',
    difficulty_level recipe_difficulty,
    
    platform_metadata JSONB,
    
    visibility_status visibility_status NOT NULL DEFAULT 'draft',
    featured BOOLEAN DEFAULT false,
    featured_until TIMESTAMPTZ,
    curator_id UUID,
    curation_notes TEXT,
    
    view_count INTEGER DEFAULT 0,
    save_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ,
    
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

-- Step 3: Create indexes
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

-- Step 4: Create trigger for updated_at
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

-- Step 5: Create helper functions (see Database Functions section above)
-- [Functions would be included here in the actual migration]
```

### Rollback Script

```sql
-- Rollback migration: Drop browsable_recipes infrastructure
DROP TRIGGER IF EXISTS trigger_update_browsable_recipes_timestamp ON browsable_recipes;
DROP FUNCTION IF EXISTS update_browsable_recipes_updated_at();
DROP FUNCTION IF EXISTS create_browsable_recipe(UUID, TEXT, TEXT, social_media_platform, TEXT[], UUID);
DROP FUNCTION IF EXISTS publish_browsable_recipe(UUID);
DROP FUNCTION IF EXISTS increment_recipe_views(UUID);
DROP FUNCTION IF EXISTS get_published_recipes(INTEGER, INTEGER, social_media_platform, TEXT[]);
DROP TABLE IF EXISTS browsable_recipes;
DROP TYPE IF EXISTS recipe_difficulty;
DROP TYPE IF EXISTS visibility_status;
DROP TYPE IF EXISTS social_media_platform;
```

### Deployment Steps

1. **Pre-deployment checks**:
   - Verify `imported_content` table has recipe data
   - Backup production database
   - Test migration on staging environment

2. **Execute migration**:
   - Run migration during low-traffic period
   - Monitor for errors
   - Verify indexes are created

3. **Post-deployment validation**:
   - Test function executions
   - Verify RLS policies
   - Check query performance

4. **Data seeding** (optional):
   - Populate initial browsable recipes from curated list
   - Backfill social metadata for existing recipes

---

## Security & Access Control

### Row Level Security Policies

```sql
-- Enable RLS on browsable_recipes
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
        AND is_pro = true  -- Assuming curators are pro users
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

-- Policy 5: No direct deletes (use visibility_status = 'removed' instead)
-- Intentionally no DELETE policy to prevent accidental data loss
```

### Security Considerations

1. **Data Privacy**: 
   - No personal user data from `user_profile` is exposed in browsable recipes
   - Social media metadata is publicly available information

2. **Content Moderation**:
   - Use `visibility_status` for soft deletes
   - `curation_notes` for internal tracking of removed content
   - Consider adding `removed_reason` field in future

3. **Rate Limiting**:
   - Implement rate limiting on view count increments (prevent abuse)
   - Consider implementing Supabase Edge Functions for this

4. **Input Validation**:
   - Validate URLs before storing
   - Sanitize tags to prevent injection
   - Validate JSONB structures

---

## Success Metrics

### Database Performance Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Query response time | < 100ms for paginated results | PostgreSQL slow query log |
| Index usage | > 95% for filtered queries | `pg_stat_user_indexes` |
| Table size growth | < 10GB in first 6 months | `pg_table_size()` |
| Concurrent connections | No degradation up to 100 | Connection pooling metrics |

### Data Quality Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Required field completeness | 100% for meal_name, platform, original_post_url | Data validation queries |
| Optional field completeness | > 70% for author_name, image_url | Completeness audit |
| Duplicate recipes | 0 (enforced by unique constraint) | Constraint violations |
| Valid foreign keys | 100% | Referential integrity checks |

### Operational Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Migration execution time | < 5 minutes | Deployment logs |
| Zero downtime deployment | Yes | Application availability monitoring |
| Rollback success rate | 100% in test environment | Testing logs |

---

## Dependencies & Risks

### Dependencies

| Dependency | Type | Status | Impact if Missing |
|------------|------|--------|-------------------|
| Supabase PostgreSQL | Infrastructure | ✅ Available | Blocker |
| `imported_content` table | Database | ✅ Exists | Blocker |
| `user_profile` table | Database | ✅ Exists | High |
| Recipe extraction pipeline | Application | ✅ Running | Medium (can populate later) |

### Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Schema changes break existing code | Medium | High | Comprehensive testing, gradual rollout |
| Performance degradation on large datasets | Low | High | Proper indexing, query optimization |
| Data migration errors | Low | Critical | Thorough testing, backup strategy |
| Missing social metadata in legacy recipes | High | Low | Accept as limitation, backfill over time |
| RLS policy misconfigurations | Medium | High | Security audit, automated tests |

### Risk Mitigation Plan

1. **Testing Strategy**:
   - Unit tests for all database functions
   - Integration tests for RLS policies
   - Load testing with realistic data volumes
   - Migration rehearsal on staging

2. **Rollback Plan**:
   - Keep rollback script tested and ready
   - Document rollback procedures
   - Maintain database backups before deployment

3. **Monitoring Plan**:
   - Set up alerts for slow queries
   - Monitor table growth
   - Track failed function executions

---

## Timeline

### Phase 1: Database Implementation

| Milestone | Duration | Target Date | Deliverables |
|-----------|----------|-------------|--------------|
| **Design Review** | 3 days | Week 1 | Finalized schema, approved PRD |
| **Development** | 5 days | Week 2 | Migration scripts, functions, tests |
| **Testing** | 5 days | Week 3 | Test results, performance benchmarks |
| **Staging Deployment** | 2 days | Week 3-4 | Deployed to staging, validation complete |
| **Production Deployment** | 1 day | Week 4 | Live in production, monitoring active |
| **Post-Launch Review** | Ongoing | Week 5 | Metrics review, optimization |

**Total Duration**: 4-5 weeks

---

## Appendix

### A. Sample Data

#### Example Browsable Recipe Record

```json
{
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "imported_content_id": "x9y8z7w6-v5u4-t3s2-r1q0-p9o8n7m6l5k4",
    "meal_name": "Quick 15-Minute Garlic Butter Shrimp",
    "meal_description": "Easy weeknight dinner with minimal ingredients",
    "image_url": "supabase://recipe-images/shrimp-garlic-butter.jpg",
    "cooking_time": 15,
    "serving_suggestions": 4,
    "author_name": "Chef Maria Rodriguez",
    "author_handle": "@chefmaria",
    "author_profile_url": "https://tiktok.com/@chefmaria",
    "platform": "tiktok",
    "original_post_url": "https://tiktok.com/@chefmaria/video/1234567890",
    "posted_date": "2026-01-10T18:30:00Z",
    "engagement_metrics": {
        "likes": 45000,
        "comments": 892,
        "shares": 2300,
        "views": 1200000,
        "saves": 8500,
        "engagement_rate": 0.0471
    },
    "tags": ["quick", "seafood", "weeknight", "easy"],
    "cuisine_type": "American",
    "meal_type": "dinner",
    "dietary_tags": ["gluten-free", "keto-friendly"],
    "difficulty_level": "easy",
    "platform_metadata": {
        "video_id": "7234567890123456789",
        "sound_name": "Original Sound - chefmaria",
        "hashtags": ["cooking", "recipe", "shrimp", "seafood"],
        "video_duration": 45,
        "caption": "15-min shrimp that'll change your life 🍤✨"
    },
    "visibility_status": "published",
    "featured": true,
    "featured_until": "2026-01-20T00:00:00Z",
    "curator_id": "c5d6e7f8-g9h0-i1j2-k3l4-m5n6o7p8q9r0",
    "view_count": 12450,
    "save_count": 856,
    "share_count": 124,
    "created_at": "2026-01-11T09:00:00Z",
    "updated_at": "2026-01-15T14:30:00Z",
    "published_at": "2026-01-11T12:00:00Z"
}
```

### B. Query Examples

#### Get Featured Recipes

```sql
SELECT 
    id,
    meal_name,
    image_url,
    author_name,
    platform,
    view_count
FROM browsable_recipes
WHERE visibility_status = 'published'
AND featured = true
AND (featured_until IS NULL OR featured_until > now())
ORDER BY published_at DESC
LIMIT 10;
```

#### Search Recipes by Tags

```sql
SELECT 
    id,
    meal_name,
    tags,
    cooking_time,
    difficulty_level
FROM browsable_recipes
WHERE visibility_status = 'published'
AND tags && ARRAY['quick', 'easy']  -- Any of these tags
AND dietary_tags @> ARRAY['vegan']  -- Must have all of these
ORDER BY view_count DESC
LIMIT 20;
```

#### Get Recipes by Platform

```sql
SELECT 
    platform,
    COUNT(*) as recipe_count,
    AVG(view_count) as avg_views
FROM browsable_recipes
WHERE visibility_status = 'published'
GROUP BY platform
ORDER BY recipe_count DESC;
```

### C. Future Enhancements

1. **User Collections**: Allow users to save browsable recipes to personal collections
2. **Recipe Ratings**: Add user ratings and reviews
3. **Advanced Search**: Full-text search across recipe content
4. **Trending Algorithm**: Calculate trending scores based on engagement velocity
5. **Related Recipes**: Recommendation system based on tags and user behavior
6. **Social Sharing**: Track external shares and attribute traffic
7. **Seasonal/Holiday Tags**: Time-based recipe promotion
8. **Nutrition Information**: Add nutritional data extraction and storage
9. **Video Timestamps**: Store specific timestamps for recipe steps in videos
10. **Multi-language Support**: Store translations of recipes

### D. Testing Checklist

**Schema Validation**:
- [ ] All columns have correct data types
- [ ] Foreign key constraints work correctly
- [ ] Unique constraints prevent duplicates
- [ ] Indexes improve query performance
- [ ] Default values are applied correctly

**Function Testing**:
- [ ] `create_browsable_recipe()` validates input
- [ ] `publish_browsable_recipe()` updates status correctly
- [ ] `increment_recipe_views()` handles concurrency
- [ ] `get_published_recipes()` filters and paginates correctly

**RLS Policy Testing**:
- [ ] Anonymous users cannot access any recipes
- [ ] Authenticated users can view only published recipes
- [ ] Curators can view draft recipes
- [ ] Curators can insert/update their recipes
- [ ] Users cannot delete recipes directly

**Performance Testing**:
- [ ] Queries execute within target time (< 100ms)
- [ ] Indexes are being used (check EXPLAIN ANALYZE)
- [ ] No N+1 query problems
- [ ] Concurrent access doesn't cause deadlocks

**Data Integrity**:
- [ ] Cascading deletes work correctly
- [ ] NULL handling is correct
- [ ] JSONB validation prevents invalid data
- [ ] Array operations work as expected

### E. Glossary

| Term | Definition |
|------|------------|
| **Browsable Recipe** | A recipe that has been curated and made available for discovery in the browse interface |
| **Curator** | A user (typically admin or pro user) who selects and publishes recipes to the browsable collection |
| **Engagement Metrics** | Social media statistics like likes, shares, comments, and views |
| **Platform Metadata** | Platform-specific data (TikTok video ID, YouTube timestamps, etc.) |
| **Visibility Status** | The publication state of a recipe (draft, published, archived, removed) |
| **Featured Recipe** | A recipe highlighted in the browse interface, optionally with an expiration date |
| **RLS (Row Level Security)** | PostgreSQL feature that controls row-level access based on user permissions |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-15 | [Your Name] | Initial draft - Phase 1 specifications |

---

## Approvals

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Product Manager | | | |
| Engineering Lead | | | |
| Database Administrator | | | |
| Security Lead | | | |

---

*End of Document*