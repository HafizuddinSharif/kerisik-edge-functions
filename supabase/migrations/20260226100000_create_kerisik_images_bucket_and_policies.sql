-- Migration: Create kerisik-images bucket and per-user Storage RLS
-- Phase 2: Supabase Setup — Kerisik cloud sync (recipe/meal images).
-- Object naming: {user_id}/meals/<uuid>.<ext>, {user_id}/recipes/<uuid>.<ext>

INSERT INTO storage.buckets (id, name, public)
VALUES ('kerisik-images', 'kerisik-images', false)
ON CONFLICT (id) DO NOTHING;

-- Authenticated users can only read/write objects under their own prefix (auth.uid()/...)
CREATE POLICY "kerisik_images_select_own"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'kerisik-images'
  AND name LIKE (auth.uid()::text || '/%')
);

CREATE POLICY "kerisik_images_insert_own"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'kerisik-images'
  AND name LIKE (auth.uid()::text || '/%')
);

CREATE POLICY "kerisik_images_update_own"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'kerisik-images'
  AND name LIKE (auth.uid()::text || '/%')
)
WITH CHECK (
  bucket_id = 'kerisik-images'
  AND name LIKE (auth.uid()::text || '/%')
);

CREATE POLICY "kerisik_images_delete_own"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'kerisik-images'
  AND name LIKE (auth.uid()::text || '/%')
);
