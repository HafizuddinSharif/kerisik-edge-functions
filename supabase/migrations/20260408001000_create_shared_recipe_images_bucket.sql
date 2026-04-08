-- Migration: 20260408001000_create_shared_recipe_images_bucket
-- Description: Private Storage bucket and owner-scoped policies for temporary shared recipe images.
-- Object naming: shares/{auth.uid()}/{token}/{filename}

INSERT INTO storage.buckets (id, name, public)
VALUES ('shared-recipe-images', 'shared-recipe-images', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "shared_recipe_images_select_own" ON storage.objects;
CREATE POLICY "shared_recipe_images_select_own"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'shared-recipe-images'
  AND name LIKE ('shares/' || auth.uid()::text || '/%')
);

DROP POLICY IF EXISTS "shared_recipe_images_insert_own" ON storage.objects;
CREATE POLICY "shared_recipe_images_insert_own"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'shared-recipe-images'
  AND name LIKE ('shares/' || auth.uid()::text || '/%')
);

DROP POLICY IF EXISTS "shared_recipe_images_update_own" ON storage.objects;
CREATE POLICY "shared_recipe_images_update_own"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'shared-recipe-images'
  AND name LIKE ('shares/' || auth.uid()::text || '/%')
)
WITH CHECK (
  bucket_id = 'shared-recipe-images'
  AND name LIKE ('shares/' || auth.uid()::text || '/%')
);

DROP POLICY IF EXISTS "shared_recipe_images_delete_own" ON storage.objects;
CREATE POLICY "shared_recipe_images_delete_own"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'shared-recipe-images'
  AND name LIKE ('shares/' || auth.uid()::text || '/%')
);
