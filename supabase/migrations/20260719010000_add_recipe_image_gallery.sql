-- Ordered gallery for personal recipes. image_url remains the legacy cover.
ALTER TABLE kerisik.recipes ADD COLUMN IF NOT EXISTS image_urls jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE kerisik.recipes DROP CONSTRAINT IF EXISTS recipes_image_urls_max_ten;
ALTER TABLE kerisik.recipes ADD CONSTRAINT recipes_image_urls_max_ten
  CHECK (jsonb_typeof(image_urls) = 'array' AND jsonb_array_length(image_urls) <= 10);

UPDATE kerisik.recipes
SET image_urls = CASE WHEN image_url IS NULL OR image_url = '' THEN '[]'::jsonb ELSE jsonb_build_array(image_url) END
WHERE image_urls = '[]'::jsonb;
