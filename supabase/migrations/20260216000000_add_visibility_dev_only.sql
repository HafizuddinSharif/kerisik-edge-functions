-- Migration: Add dev_only to visibility enums (browsable_recipes + collections)
-- Enables development-only visibility; enforced at app level per Option B.

ALTER TYPE public.visibility_status ADD VALUE 'dev_only';
ALTER TYPE public.collection_visibility ADD VALUE 'dev_only';

-- (Function updates are in 20260216000001 so new enum values are committed first.)
