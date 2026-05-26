# Import Error Messages

## Purpose

URL import failures should carry backend-owned error codes and user-facing copy so the mobile client does not need a release every time the backend adds or changes an import failure message.

Supabase owns the persistent contract:

- a canonical message catalogue keyed by backend error code
- denormalized terminal error fields on `public.imported_content`
- best-effort backfill for existing failed imports

Related docs:

- `fastapi/docs/003-import-error-messages.md`
- `nak-beli-apa-v2/docs/003-import-error-messages.md`

## Affected Database Objects

### `public.error_messages`

Create a small seeded catalogue table.

| Column | Type | Notes |
| --- | --- | --- |
| `error_code` | `text` | Machine-readable code. Part of primary key. |
| `language` | `text` | `EN` or `BM`. Part of primary key. |
| `title` | `text` | Short UI title. |
| `message` | `text` | User-facing explanation. |
| `is_active` | `boolean` | Defaults to `true`; inactive rows are ignored by backend resolution. |
| `created_at` | `timestamptz` | Default `now()`. |
| `updated_at` | `timestamptz` | Updated by the standard trigger. |

Constraints:

- Primary key: `(error_code, language)`.
- `language` check: `language in ('EN', 'BM')`.
- `title` and `message` should be non-empty after trimming.

RLS:

- Enable RLS.
- Allow `authenticated` users to `SELECT` active rows.
- Do not allow client `INSERT`, `UPDATE`, or `DELETE`.
- `service_role` may manage rows.

The client should not depend on this table for normal Realtime failure rendering. It exists as the canonical catalogue and as a possible diagnostic/fallback source.

### `public.imported_content`

Add terminal error snapshot columns.

| Column | Type | Notes |
| --- | --- | --- |
| `error_code` | `text` | Backend error code for terminal import errors. Null while processing and on successful recipe imports. |
| `error_display` | `jsonb` | Snapshot of display copy by language. Null while processing and on successful recipe imports. |

Expected `error_display` shape:

```json
{
  "EN": {
    "title": "Video too long",
    "message": "This video is over 10 minutes. Try a shorter recipe video."
  },
  "BM": {
    "title": "Video terlalu panjang",
    "message": "Video ini melebihi 10 minit. Cuba video resepi yang lebih pendek."
  }
}
```

The snapshot is intentionally denormalized because `imported_content` is the async job event stream sent through Supabase Realtime. A terminal row should contain everything the mobile client needs to render the failure modal without a second query.

## Initial Catalogue

Seed only codes the backend already emits or needs as safe fallback:

| Error code | Purpose |
| --- | --- |
| `NOT_RECIPE_CONTENT` | LLM decided the URL content is not a recipe. |
| `VIDEO_TOO_LONG` | Video exceeds the supported duration. |
| `NO_CONTENT_FOUND` | Extractor or scraper found no usable content. |
| `UNSUPPORTED_MEDIA_TYPE` | Platform media type is unsupported, for example mixed Instagram sidecar. |
| `DOMAIN_NOT_ALLOWED` | URL domain is blocked or unsupported by website extraction. |
| `INVALID_URL` | URL is malformed or cannot be handled. |
| `FIRECRAWL_SCRAPE_FAILED` | Firecrawl scrape failed. |
| `IMPORT_RETRY_LIMIT_REACHED` | Existing failed import has reached retry limit. |
| `IMPORT_FAILED` | Generic fallback for unexpected or unmapped failures. |

`IMPORT_FAILED` must always exist in both languages and should be used whenever no active catalogue row exists for a more specific code.

## State Transition Rules

When an import starts or retries, clear stale error fields:

- `status = 'PROCESSING'`
- `error_code = null`
- `error_display = null`
- `content = null`
- `is_recipe_content = null`
- `video_duration = null`

When an import fails with retryable processing failure:

- `status = 'FAILED'`
- `retry_count` increments
- `error_code` is set
- `error_display` is resolved from `error_messages`

When content is not a recipe:

- Keep existing semantic status: `status = 'COMPLETED'`
- `is_recipe_content = false`
- `content = null`
- `error_code = 'NOT_RECIPE_CONTENT'`
- `error_display` is resolved from `error_messages`

Successful recipe imports must clear or omit error fields:

- `status = 'COMPLETED'`
- `is_recipe_content = true`
- `error_code = null`
- `error_display = null`

## Backfill

Backfill existing terminal rows best-effort only:

- `status = 'FAILED'` and `video_duration > 600` -> `VIDEO_TOO_LONG`
- `status = 'FAILED'` otherwise -> `IMPORT_FAILED`
- `status = 'COMPLETED'` and `is_recipe_content = false` -> `NOT_RECIPE_CONTENT`
- successful recipe rows remain untouched

Old rows may not preserve exact failure cause. Prefer generic safe copy over inventing precision.

## Phased Rollout

### Phase 1: Schema and Seeds

- Add `error_messages`.
- Add `imported_content.error_code`.
- Add `imported_content.error_display`.
- Seed initial EN/BM copy.
- Backfill terminal rows best-effort.
- Update database documentation for `imported_content`.

### Phase 2: FastAPI Writes

- FastAPI resolves active catalogue rows using service-role Supabase access.
- `ImportedContentLifecycle` writes error fields during terminal transitions.
- Retry/reset transitions clear old error fields.
- Unexpected exceptions use the generic `IMPORT_FAILED` display snapshot.

### Phase 3: Mobile Read Path

- Mobile Realtime handling reads `error_code` and `error_display` from `imported_content`.
- Mobile displays `error_display[preferredLanguage]` when present.
- Existing local text remains fallback for old rows, transport failures, timeout, and client-only validation.

### Phase 4: Hardening

- Add tests for catalogue resolution, fallback behavior, retry clearing, and not-recipe terminal state.
- Add diagnostics for missing catalogue rows.
- Consider future back-office editing only after audit, permissions, and preview requirements are defined.

## Verification

Database checks:

- `error_messages` rejects unsupported languages.
- Authenticated users can select active message rows.
- Authenticated users cannot write message rows.
- `imported_content.error_display` is null for processing and successful recipe rows.
- Best-effort backfill assigns expected codes to old terminal rows.

Realtime contract checks:

- A terminal `FAILED` update includes `error_code` and `error_display`.
- A terminal non-recipe update uses `COMPLETED`, `is_recipe_content=false`, and includes `NOT_RECIPE_CONTENT` display copy.
- A retry update clears stale error fields before returning to `PROCESSING`.
