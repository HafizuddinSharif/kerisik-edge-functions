-- Migration: Add RLS to authors table
-- Created: 2026-02-01
-- Description: Enables Row Level Security on authors. Authenticated users can read;
-- INSERT/UPDATE/DELETE are restricted to SECURITY DEFINER functions (get_or_create_author).

-- Enable RLS on authors
ALTER TABLE authors ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read all authors (for recipe attribution display)
CREATE POLICY "authenticated_read_authors"
ON authors
FOR SELECT
TO authenticated
USING (true);
