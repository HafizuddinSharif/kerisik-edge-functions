-- Authors Table Schema
-- This file defines the authors table structure declaratively
-- Depends on: social_media_platform enum (from browsable_recipes migration)

CREATE TABLE IF NOT EXISTS public.authors (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    name text,
    handle text,
    profile_url text,
    profile_pic_url text,
    platform public.social_media_platform NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Partial unique index: (platform, profile_url) unique when profile_url is provided
-- Allows multiple authors with NULL profile_url (e.g. anonymous website authors)
CREATE UNIQUE INDEX IF NOT EXISTS unique_author_per_platform
    ON public.authors (platform, profile_url)
    WHERE profile_url IS NOT NULL;

-- Index for lookups by platform and profile_url
CREATE INDEX IF NOT EXISTS idx_authors_platform_profile_url
    ON public.authors (platform, profile_url);

-- Enable RLS
ALTER TABLE public.authors ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated_read_authors"
ON public.authors
FOR SELECT
TO authenticated
USING (true);

-- Grant permissions
GRANT ALL ON TABLE public.authors TO authenticated;
GRANT ALL ON TABLE public.authors TO service_role;
