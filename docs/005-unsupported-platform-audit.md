# Unsupported Platform Audit

## Purpose

Known unsupported social platform attempts should be stored in `public.imported_content` so product and support can inspect what users tried to import. User-facing copy remains generic and is resolved through the existing `public.error_messages` catalogue.

Related docs:

- `fastapi/docs/005-unsupported-platform-audit.md`
- `nak-beli-apa-v2/docs/005-unsupported-platform-audit.md`
- `backoffice/docs/005-unsupported-platform-audit.md`
- `supabase-dev/docs/003-import-error-messages.md`

## Affected Database Objects

### `public.imported_content`

No new database columns are required if `metadata`, `error_code`, and `error_display` already exist.

Unsupported-platform audit rows should use:

| Column | Expected value |
| --- | --- |
| `source_url` | Canonical URL when available, otherwise submitted URL |
| `status` | `FAILED` |
| `retry_count` | `0` |
| `is_recipe_content` | `null` |
| `content` | `null` |
| `error_code` | `DOMAIN_NOT_ALLOWED` |
| `error_display` | Snapshot resolved from `public.error_messages` |
| `metadata` | Unsupported-platform diagnostic object |

Expected metadata shape:

```json
{
  "blocked_reason": "unsupported_platform",
  "unsupported_platform": "facebook",
  "matched_domain": "facebook.com"
}
```

`unsupported_platform` must be a lowercase machine value. `matched_domain` should record the domain family that triggered detection, for example `facebook.com`, `fb.watch`, `threads.net`, or `threads.com`.

### `public.error_messages`

Unsupported-platform audit rows reuse existing `DOMAIN_NOT_ALLOWED` catalogue rows. Do not add per-platform display rows unless a later feature changes the copy model.

## State Rules

When an import is rejected because the URL belongs to a known unsupported social platform:

- create a new `imported_content` row for every attempt
- `status = 'FAILED'`
- `retry_count = 0`
- `is_recipe_content = null`
- `content = null`
- `error_code = 'DOMAIN_NOT_ALLOWED'`
- `error_display` is resolved from `error_messages`
- `metadata.blocked_reason = 'unsupported_platform'`
- `metadata.unsupported_platform` identifies the platform
- `metadata.matched_domain` identifies the matched domain family

These rows are terminal audit records and are not eligible for retry/reset. Repeated submissions of the same unsupported URL should create separate rows so attempt volume remains visible.

## Backfill

Do not backfill historical unsupported-platform attempts from URL patterns without an explicit migration decision. Old terminal rows may not preserve exact cause, and broad URL-pattern backfills could invent precision.

## Verification

Database checks:

- Unsupported-platform audit rows contain generic `DOMAIN_NOT_ALLOWED` display copy.
- Metadata includes `blocked_reason`, `unsupported_platform`, and `matched_domain`.
- Repeated submissions create separate rows.
- Successful recipe rows still have `error_code = null` and `error_display = null`.
