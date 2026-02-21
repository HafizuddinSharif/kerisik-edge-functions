-- Add unique constraint on collections.author_id so each author has at most one collection.
-- Idempotent: skip if constraint already exists (e.g. applied via dashboard or prior run).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'unique_collections_author_id'
      AND conrelid = 'public.collections'::regclass
  ) THEN
    ALTER TABLE collections
      ADD CONSTRAINT unique_collections_author_id UNIQUE (author_id);
  END IF;
END $$;
