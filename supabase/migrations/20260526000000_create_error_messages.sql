-- Migration: 20260526000000_create_error_messages
-- Description: Add backend-owned import error message catalogue and terminal error snapshots.

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS public.error_messages (
    error_code text NOT NULL,
    language text NOT NULL,
    title text NOT NULL,
    message text NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT error_messages_pkey PRIMARY KEY (error_code, language),
    CONSTRAINT error_messages_language_check
        CHECK (language IN ('EN', 'BM')),
    CONSTRAINT error_messages_title_non_empty
        CHECK (btrim(title) <> ''),
    CONSTRAINT error_messages_message_non_empty
        CHECK (btrim(message) <> '')
);

DROP TRIGGER IF EXISTS set_error_messages_updated_at ON public.error_messages;
CREATE TRIGGER set_error_messages_updated_at
    BEFORE UPDATE ON public.error_messages
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.error_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can view active error messages" ON public.error_messages;
CREATE POLICY "Authenticated users can view active error messages"
ON public.error_messages
FOR SELECT
TO authenticated
USING (is_active = true);

REVOKE ALL ON TABLE public.error_messages FROM anon;
REVOKE ALL ON TABLE public.error_messages FROM authenticated;
GRANT SELECT ON TABLE public.error_messages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.error_messages TO service_role;

ALTER TABLE public.imported_content
    ADD COLUMN IF NOT EXISTS error_code text,
    ADD COLUMN IF NOT EXISTS error_display jsonb;

INSERT INTO public.error_messages (error_code, language, title, message)
VALUES
    ('NOT_RECIPE_CONTENT', 'EN', 'Not a recipe', 'This link does not look like a recipe. Try importing a recipe post, article, or video.'),
    ('NOT_RECIPE_CONTENT', 'BM', 'Bukan resepi', 'Pautan ini tidak kelihatan seperti resepi. Cuba import hantaran, artikel, atau video resepi.'),
    ('VIDEO_TOO_LONG', 'EN', 'Video too long', 'This video is over 10 minutes. Try a shorter recipe video.'),
    ('VIDEO_TOO_LONG', 'BM', 'Video terlalu panjang', 'Video ini melebihi 10 minit. Cuba video resepi yang lebih pendek.'),
    ('NO_CONTENT_FOUND', 'EN', 'No content found', 'We could not find usable recipe content at this link. Try another recipe URL.'),
    ('NO_CONTENT_FOUND', 'BM', 'Tiada kandungan ditemui', 'Kami tidak dapat mencari kandungan resepi yang boleh digunakan di pautan ini. Cuba URL resepi lain.'),
    ('UNSUPPORTED_MEDIA_TYPE', 'EN', 'Unsupported media type', 'This post type is not supported yet. Try a recipe article or a single recipe video.'),
    ('UNSUPPORTED_MEDIA_TYPE', 'BM', 'Jenis media tidak disokong', 'Jenis hantaran ini belum disokong. Cuba artikel resepi atau satu video resepi.'),
    ('DOMAIN_NOT_ALLOWED', 'EN', 'Website not supported', 'This website cannot be imported right now. Try a recipe link from another source.'),
    ('DOMAIN_NOT_ALLOWED', 'BM', 'Laman web tidak disokong', 'Laman web ini tidak boleh diimport buat masa ini. Cuba pautan resepi daripada sumber lain.'),
    ('INVALID_URL', 'EN', 'Invalid link', 'This link is invalid or cannot be handled. Check the URL and try again.'),
    ('INVALID_URL', 'BM', 'Pautan tidak sah', 'Pautan ini tidak sah atau tidak dapat diproses. Semak URL dan cuba lagi.'),
    ('FIRECRAWL_SCRAPE_FAILED', 'EN', 'Could not read website', 'We could not read this website. Try again later or use another recipe link.'),
    ('FIRECRAWL_SCRAPE_FAILED', 'BM', 'Tidak dapat membaca laman web', 'Kami tidak dapat membaca laman web ini. Cuba lagi kemudian atau gunakan pautan resepi lain.'),
    ('IMPORT_RETRY_LIMIT_REACHED', 'EN', 'Import retry limit reached', 'This import has failed too many times. Try importing the recipe again from a fresh link.'),
    ('IMPORT_RETRY_LIMIT_REACHED', 'BM', 'Had cubaan import dicapai', 'Import ini telah gagal terlalu banyak kali. Cuba import semula resepi daripada pautan baharu.'),
    ('IMPORT_FAILED', 'EN', 'Import failed', 'We could not import this recipe. Try again later or use another recipe link.'),
    ('IMPORT_FAILED', 'BM', 'Import gagal', 'Kami tidak dapat mengimport resepi ini. Cuba lagi kemudian atau gunakan pautan resepi lain.')
ON CONFLICT (error_code, language) DO UPDATE
SET
    title = EXCLUDED.title,
    message = EXCLUDED.message,
    is_active = true,
    updated_at = now();

WITH display_snapshots AS (
    SELECT
        error_code,
        jsonb_object_agg(
            language,
            jsonb_build_object(
                'title', title,
                'message', message
            )
            ORDER BY language
        ) AS display
    FROM public.error_messages
    WHERE is_active = true
    GROUP BY error_code
),
terminal_rows AS (
    SELECT
        id,
        CASE
            WHEN status = 'FAILED'::public.imported_content_status AND video_duration > 600 THEN 'VIDEO_TOO_LONG'
            WHEN status = 'FAILED'::public.imported_content_status THEN 'IMPORT_FAILED'
            WHEN status = 'COMPLETED'::public.imported_content_status AND is_recipe_content = false THEN 'NOT_RECIPE_CONTENT'
        END AS backfill_error_code
    FROM public.imported_content
    WHERE
        status = 'FAILED'::public.imported_content_status
        OR (
            status = 'COMPLETED'::public.imported_content_status
            AND is_recipe_content = false
        )
)
UPDATE public.imported_content ic
SET
    error_code = terminal_rows.backfill_error_code,
    error_display = display_snapshots.display
FROM terminal_rows
JOIN display_snapshots
    ON display_snapshots.error_code = terminal_rows.backfill_error_code
WHERE ic.id = terminal_rows.id;
