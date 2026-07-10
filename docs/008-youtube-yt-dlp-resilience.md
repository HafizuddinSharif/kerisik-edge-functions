# 008 YouTube yt-dlp Resilience

## Purpose

FastAPI now raises a dedicated `YOUTUBE_EXTRACTION_FAILED` code when all configured yt-dlp YouTube player clients fail. Supabase owns the user-facing error-message catalogue row for that code.

Related FastAPI implementation notes are in `fastapi/docs/008-youtube-yt-dlp-resilience.md`.

## Affected Files

- `supabase/migrations/20260710000000_add_youtube_extraction_failed_error_message.sql`: upserts English and Bahasa Melayu catalogue rows.
- `docs/003-import-error-messages.md`: existing import error-message architecture remains unchanged; this feature adds one catalogue code.

## Data Contract

The migration upserts these rows into `public.error_messages`:

| error_code | language | title |
| --- | --- | --- |
| `YOUTUBE_EXTRACTION_FAILED` | `EN` | `YouTube import failed` |
| `YOUTUBE_EXTRACTION_FAILED` | `BM` | `Import YouTube gagal` |

English message:

`We could not access this YouTube video right now. Try again later or use another recipe link.`

Bahasa Melayu message:

`Kami tidak dapat mengakses video YouTube ini buat masa ini. Cuba lagi kemudian atau gunakan pautan resepi lain.`

`is_active` is set to `true` on insert and conflict update.

## Migration Notes

No schema change is required. `public.imported_content.error_code` is already text and can store the new code. The lifecycle layer continues resolving `error_display` from `public.error_messages`, falling back to `IMPORT_FAILED` if a specific active row is unavailable.

## Verification

Apply or inspect the migration in the Supabase workflow:

```bash
cd supabase-dev
supabase migration list
```

After migration, verify:

```sql
select error_code, language, title, message, is_active
from public.error_messages
where error_code = 'YOUTUBE_EXTRACTION_FAILED'
order by language;
```

Expected result: active `EN` and `BM` rows with the copy documented above.
