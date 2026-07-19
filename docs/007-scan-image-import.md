# 007 — Scan Image/PDF Import (Supabase)

Supabase slice of the scan-import feature. See root `docs/007-scan-image-import.md`
for the full cross-repo design. **Migrations are authored here and suggested to
the owner — not run from `fastapi/` or `backoffice/`.**

## Implementation status

Implemented in `supabase/migrations/20260719000000_create_scan_uploads_bucket.sql`
and `supabase/functions/import-recipe-image/index.ts`. Apply/deploy both before
shipping the mobile UI.

## New Storage bucket — `scan-uploads`

- **Private** bucket (not public).
- Path layout: `{auth_uid}/{uuid}.jpg` for images, `{auth_uid}/{uuid}.pdf` for a
  PDF, `{auth_uid}/{uuid}_cover.jpg` for the backend-rendered PDF cover.
- Allowed MIME: `image/jpeg`, `application/pdf` (cover written by service-role).

### RLS policies (both required)

The folder's first segment is the user's `auth.uid()`.

- **INSERT** (mobile uploads with the user JWT):
  `(storage.foldername(name))[1] = auth.uid()::text`
- **SELECT** (mobile mints a signed URL to download the cover — `downloadSupabaseUriToLocal`):
  `(storage.foldername(name))[1] = auth.uid()::text`

Backend reads/writes via the service-role key (bypasses RLS), so it needs no
policy. The SELECT policy is mandatory — without it the owner cannot create a
signed URL and scan covers fail to download.

## Edge function — `import-recipe-image`

- Clone `supabase/functions/import-recipe/index.ts`.
- **Drop** the URL normalize / resolve-redirect / sanitize block entirely.
- Authenticate the JWT (same `getAuthenticatedUserId` pattern; honor DEV bypass).
- **Add ownership assertion:** for every entry in `image_pointers`, the folder
  segment after `supabase://scan-uploads/` MUST equal the authenticated
  `auth.uid()`; return 403 on any mismatch. (Stops a crafted request feeding
  another user's pointer to the service-role signer.)
- Proxy `{ image_pointers, email, caption }` → `POST {MS_LLM_BASE_URL}/api/v2/import-from-image`
  with `x-api-key: MS_LLM_API_KEY`; return the backend response verbatim.
- MUST NOT perform any Supabase inserts/updates/RPC (same contract as
  `import-recipe`).

## Tables / RPC

- **No new tables** — the existing `imported_content` row is reused with a
  synthetic `source_url = image://<uuid>`.
- Reuse `increment_ai_imports_used` (called post-success by the backend).
- Optional (analytics, suggest only): an `import_source = 'image_scan'` marker.

## Cleanup (follow-up, not v1)

A scheduled sweeper may delete `scan-uploads` objects older than N days **only if
unreferenced** — i.e. no COMPLETED `imported_content.content.image_url` points at
them. A blanket TTL delete would destroy live recipe covers.

## Verification

- Upload to own folder succeeds; upload to another uid's folder is rejected by RLS.
- `createSignedUrl` on own object succeeds (SELECT policy); on another's fails.
- Edge fn returns 403 when a pointer's folder ≠ authenticated uid.
</content>
