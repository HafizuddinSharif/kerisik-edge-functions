-- Browsable Recipes Table Schema
-- This file defines the browsable_recipes table structure declaratively

-- Custom enum types
CREATE TYPE public.social_media_platform AS ENUM (
    'tiktok',
    'youtube',
    'instagram',
    'website',
    'other'
);

CREATE TYPE public.visibility_status AS ENUM (
    'draft',
    'published',
    'archived',
    'removed'
);

CREATE TYPE public.recipe_difficulty AS ENUM (
    'easy',
    'medium',
    'hard'
);

-- Create table for storing browsable recipes
CREATE TABLE IF NOT EXISTS public.browsable_recipes (
    -- Primary identifiers
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    imported_content_id uuid NOT NULL,
    
    -- Core recipe information (denormalized for performance)
    meal_name text NOT NULL,
    meal_description text,
    image_url text,
    cooking_time integer, -- in minutes
    serving_suggestions integer,
    
    -- Social media metadata
    author_id uuid,
    platform social_media_platform NOT NULL,
    original_post_url text NOT NULL,
    posted_date timestamp with time zone,
    engagement_metrics jsonb, -- likes, shares, comments, views
    
    -- Categorization and discovery
    tags text[] DEFAULT '{}',
    cuisine_type text,
    meal_type text, -- breakfast, lunch, dinner, snack, dessert
    dietary_tags text[] DEFAULT '{}', -- vegan, vegetarian, gluten-free, etc.
    difficulty_level recipe_difficulty,
    
    -- Platform-specific metadata
    platform_metadata jsonb, -- flexible storage for platform-specific data
    
    -- Curation and visibility
    visibility_status visibility_status NOT NULL DEFAULT 'draft',
    featured boolean DEFAULT false,
    featured_until timestamp with time zone,
    curator_id uuid, -- user_profile.id of who added this to browsable
    curation_notes text,
    
    -- Engagement tracking
    view_count integer DEFAULT 0,
    save_count integer DEFAULT 0,
    share_count integer DEFAULT 0,
    
    -- Timestamps
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    published_at timestamp with time zone,
    
    -- Constraints
    CONSTRAINT fk_imported_content 
        FOREIGN KEY (imported_content_id) 
        REFERENCES public.imported_content(id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_curator 
        FOREIGN KEY (curator_id) 
        REFERENCES public.user_profile(id) 
        ON DELETE SET NULL,
    CONSTRAINT fk_author 
        FOREIGN KEY (author_id) 
        REFERENCES public.authors(id) 
        ON DELETE SET NULL,
    CONSTRAINT unique_browsable_recipe 
        UNIQUE (imported_content_id)
);

-- Enable RLS
ALTER TABLE public.browsable_recipes ENABLE ROW LEVEL SECURITY;

-- Policy 1: All authenticated users can view published recipes
CREATE POLICY "view_published_recipes"
ON public.browsable_recipes
FOR SELECT
TO authenticated
USING (visibility_status = 'published');

-- Policy 2: Curators can view all recipes (including drafts)
CREATE POLICY "curators_view_all"
ON public.browsable_recipes
FOR SELECT
TO authenticated
USING (
  curator_id IN (
    SELECT id FROM public.user_profile 
    WHERE auth_id = auth.uid() 
    AND is_pro = true
  )
);

-- Policy 3: Curators can insert new browsable recipes
CREATE POLICY "curators_insert_recipes"
ON public.browsable_recipes
FOR INSERT
TO authenticated
WITH CHECK (
  curator_id IN (
    SELECT id FROM public.user_profile 
    WHERE auth_id = auth.uid() 
    AND is_pro = true
  )
);

-- Policy 4: Curators can update recipes they curated
CREATE POLICY "curators_update_own_recipes"
ON public.browsable_recipes
FOR UPDATE
TO authenticated
USING (
  curator_id IN (
    SELECT id FROM public.user_profile 
    WHERE auth_id = auth.uid()
  )
);

-- Note: No DELETE policy - use visibility_status = 'removed' for soft deletes

-- Grant permissions
GRANT ALL ON TABLE public.browsable_recipes TO authenticated;
GRANT ALL ON TABLE public.browsable_recipes TO service_role;
