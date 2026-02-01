-- Migration: Add non-partial unique constraint for authors (platform, profile_url)
-- Created: 2026-02-01
-- Description: Enables PostgREST/Supabase upserts with ON CONFLICT (platform, profile_url).
-- Fixes 42P10 "there is no unique or exclusion constraint matching the ON CONFLICT specification".
-- In PostgreSQL, multiple NULLs are allowed in unique constraints (NULL != NULL), so anonymous
-- authors with (platform, NULL) remain supported.

ALTER TABLE authors
ADD CONSTRAINT authors_platform_profile_url_unique
UNIQUE (platform, profile_url);
