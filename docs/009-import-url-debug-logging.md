# 009 Import URL Debug Logging

## Purpose

Adds request-correlated logging to the `import-recipe` Edge Function so URL-import failures can be matched to FastAPI intake logs.

This helps diagnose cases where the app shows an import error but no `imported_content` row can be found.

Related FastAPI implementation notes are in `fastapi/docs/009-import-url-debug-logging.md`.

## Affected Files

- `supabase/functions/import-recipe/index.ts`
  - Generates a per-call `requestId`.
  - Logs auth, URL resolution/sanitization, backend URL, retry attempts, backend response status, and backend response summary.
  - Sends `X-Request-ID` to FastAPI.
  - Adds `request_id` to the proxied body for fallback correlation.
  - Returns `X-Request-ID` to the client.

## Data/API Contract

No behavior change is intended. The Edge Function still proxies to:

```text
POST {MS_LLM_BASE_URL}/api/v2/import-from-url
```

The proxied request now includes:

```json
{
  "url": "https://www.youtube.com/watch?v=...",
  "email": "user@example.com",
  "mode": "async",
  "request_id": "<uuid>"
}
```

and header:

```text
X-Request-ID: <uuid>
```

## Debug Signals

Look for this prefix in Edge Function logs:

```text
[IMPORT URL][<request_id>]
```

Important cases:

- Auth failure before backend call: no `imported_content` row should be expected.
- URL resolution/sanitization exception before backend call: no `imported_content` row should be expected.
- Backend response summary with no `extract_id`: FastAPI did not create or reuse an `imported_content` row.
- Backend response summary with `extract_id`: an `imported_content` row should exist.

## YouTube Redirect Resolution Guard

YouTube URLs intentionally skip the Edge Function `resolveToFinalUrl()` fetch. Production logs showed YouTube requests being resolved to Google's anti-bot page:

```text
https://www.google.com/sorry/index
```

That caused FastAPI to cache and reuse a non-recipe row for the Google CAPTCHA page instead of processing the original YouTube URL. The Edge Function should sanitize YouTube directly from the submitted URL:

- `youtube.com/watch?v=<id>` -> `https://www.youtube.com/watch?v=<id>`
- `youtube.com/shorts/<id>` -> `https://www.youtube.com/shorts/<id>`
- `youtu.be/<id>` -> `https://www.youtube.com/watch?v=<id>`

TikTok and other URLs can still use redirect resolution.

## Verification

After deploying the Edge Function and FastAPI:

1. Trigger an import from the app.
2. Find `[IMPORT URL][<request_id>]` in Edge Function logs.
3. Confirm `Backend response summary` includes either an `extract_id` or a pre-row error.
4. Search FastAPI logs for the same request ID.
