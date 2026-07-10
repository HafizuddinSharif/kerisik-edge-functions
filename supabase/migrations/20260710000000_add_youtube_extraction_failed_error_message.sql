-- Migration: 20260710000000_add_youtube_extraction_failed_error_message
-- Description: Add user-facing catalogue copy for YouTube yt-dlp extraction failures.

INSERT INTO public.error_messages (error_code, language, title, message)
VALUES
    (
        'YOUTUBE_EXTRACTION_FAILED',
        'EN',
        'YouTube import failed',
        'We could not access this YouTube video right now. Try again later or use another recipe link.'
    ),
    (
        'YOUTUBE_EXTRACTION_FAILED',
        'BM',
        'Import YouTube gagal',
        'Kami tidak dapat mengakses video YouTube ini buat masa ini. Cuba lagi kemudian atau gunakan pautan resepi lain.'
    )
ON CONFLICT (error_code, language) DO UPDATE
SET
    title = EXCLUDED.title,
    message = EXCLUDED.message,
    is_active = true,
    updated_at = now();
