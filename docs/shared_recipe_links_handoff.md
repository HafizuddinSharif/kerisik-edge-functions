# Shared Recipe Links Handoff

**Status:** In progress  
**Created:** April 8, 2026  
**Last Updated:** April 8, 2026  
**Scope:** Supabase backend for temporary personal recipe sharing

---

## Summary

This repo now has the backend foundation for temporary personal recipe shares:

- `shared_recipe_links` table for 3-day tokenized recipe snapshots
- private Storage bucket for temporary shared images
- `create-recipe-share` edge function
- `get-shared-recipe` edge function
- cleanup edge function + scheduled cron migration

Browsable recipe sharing is not part of these changes. That should continue using the canonical browsable recipe route.

---

## Implemented Files

### Database migrations

- [20260408000000_create_shared_recipe_links.sql](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/migrations/20260408000000_create_shared_recipe_links.sql)
- [20260408001000_create_shared_recipe_images_bucket.sql](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/migrations/20260408001000_create_shared_recipe_images_bucket.sql)
- [20260408002000_add_increment_shared_recipe_link_views_rpc.sql](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/migrations/20260408002000_add_increment_shared_recipe_link_views_rpc.sql)
- [20260408003000_schedule_shared_recipe_cleanup.sql](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/migrations/20260408003000_schedule_shared_recipe_cleanup.sql)

### Edge functions

- [create-recipe-share/index.ts](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/functions/api/create-recipe-share/index.ts)
- [get-shared-recipe/index.ts](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/functions/api/get-shared-recipe/index.ts)
- [cleanup-expired-recipe-shares/index.ts](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/functions/api/cleanup-expired-recipe-shares/index.ts)

---

## Current Backend Design

### Share table

`public.shared_recipe_links`

Columns:
- `id uuid primary key`
- `token text unique not null`
- `owner_user_profile_id uuid null references public.user_profile(id) on delete set null`
- `recipe_payload jsonb not null`
- `image_path text null`
- `expires_at timestamptz not null`
- `revoked_at timestamptz null`
- `view_count integer not null default 0`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Behavior:
- RLS enabled
- no client-facing policies
- direct access intended only through service-role edge functions

### Storage bucket

Bucket:
- `shared-recipe-images`

Behavior:
- private bucket
- objects stored under `shares/{auth.uid()}/{token}/{filename}`
- authenticated users can manage only their own prefix
- recipients do not access bucket directly
- `get-shared-recipe` returns a signed image URL for active shares

### Cleanup strategy

- expired or revoked shares are fetched in batches
- temporary images are deleted first
- DB rows are deleted only when image deletion succeeded, or when no image exists
- scheduled hourly via `pg_cron` + `pg_net`

---

## Edge Function Interfaces

### `create-recipe-share`

Route:
- `/functions/v1/create-recipe-share`

Method:
- `POST`

Auth:
- required

Request body:

```json
{
  "recipe": {
    "title": "Nasi Goreng",
    "description": "Quick fried rice",
    "imageUrl": "https://example.com/image.jpg",
    "cookingTime": 20,
    "servingSuggestions": 2,
    "ingredients": [
      {
        "name": "Rice",
        "quantity": "2",
        "unit": "cups",
        "sortOrder": 1
      }
    ],
    "steps": [
      {
        "text": "Heat oil",
        "sortOrder": 1
      }
    ],
    "attribution": {
      "appVersion": "1.0.0"
    }
  },
  "imageUpload": {
    "base64Data": "data:image/jpeg;base64,...",
    "contentType": "image/jpeg",
    "fileName": "recipe.jpg"
  }
}
```

Response data:

```json
{
  "shareUrl": "https://kerisik.app/shared/recipe/<token>",
  "token": "<token>",
  "expiresAt": "2026-04-11T12:00:00.000Z"
}
```

Notes:
- `imageUpload` is optional
- if image upload fails, share creation continues without image
- share TTL is fixed at 3 days
- base URL defaults to `https://kerisik.app/shared/recipe`
- override via `RECIPE_SHARE_BASE_URL`

### `get-shared-recipe`

Route:
- `/functions/v1/get-shared-recipe`

Method:
- `GET`

Auth:
- not required

Supported token input:
- query param: `?token=<token>`
- last path segment if routed that way upstream

Response data shape:

```json
{
  "status": "active",
  "recipe": {
    "title": "Nasi Goreng",
    "description": "Quick fried rice",
    "imageUrl": "https://signed-url...",
    "cookingTime": 20,
    "servingSuggestions": 2,
    "ingredients": [],
    "steps": [],
    "attribution": {}
  },
  "expiresAt": "2026-04-11T12:00:00.000Z",
  "imageUrl": "https://signed-url..."
}
```

Possible `status` values:
- `active`
- `expired`
- `revoked`
- `not_found`

Behavior:
- active shares return payload
- expired/revoked/not_found return `recipe: null`
- active reads increment `view_count` through SQL RPC

### `cleanup-expired-recipe-shares`

Route:
- `/functions/v1/cleanup-expired-recipe-shares`

Method:
- `POST`

Auth:
- internal cron use only

Required header:
- `x-cron-secret: <RECIPE_SHARE_CLEANUP_CRON_SECRET>`

Optional query param:
- `batchSize=<n>` capped at `500`

Response data:

```json
{
  "deletedShareCount": 10,
  "deletedImageCount": 7,
  "skippedShareCount": 3
}
```

---

## Required Secrets

### Edge function env

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `RECIPE_SHARE_BASE_URL` optional
- `RECIPE_SHARE_CLEANUP_CRON_SECRET` required for cleanup function

### Vault secrets used by cron migration

- `project_url`
- `anon_key` or `publishable_key`
- `recipe_share_cleanup_cron_secret`

If Vault or the required secrets are missing, the cleanup cron migration skips scheduling and emits a notice.

---

## Known Assumptions

- App uploads temporary local images to `create-recipe-share` as base64 JSON, not multipart.
- Shared image access is always via signed URL, never via public bucket.
- Cleanup is hourly, not immediate.
- Revoked shares should be deleted by the same cleanup path as expired shares.
- This backend does not yet include a revoke-share endpoint or owner-facing list endpoint.

---

## Remaining Work

### High priority

1. Wire the mobile app to `create-recipe-share`
2. Add Expo Router route for `/shared/recipe/[token]`
3. Build shared recipe viewer screen
4. Implement expired-state UI
5. Implement Save to My Recipes flow from shared payload

### Backend follow-ups

1. Add revoke endpoint for active shares
2. Add owner-facing list endpoint for active/recent shares
3. Consider deduping/regenerating shares per local recipe within active TTL
4. Add observability/logging for cleanup success/failure rates

### Deployment/setup

1. Apply Supabase migrations
2. Deploy the three edge functions
3. Set function env vars
4. Set Vault secrets so the cron schedule is created
5. Verify cron job exists after migration

---

## Suggested App Integration Notes

### Personal recipe share flow

1. Load the local recipe in app
2. Map it to the `recipe` payload shape expected by `create-recipe-share`
3. If local image exists, compress it client-side if needed
4. Send base64 image payload only when available
5. Share returned `shareUrl`

### Recipient flow

1. Open `/shared/recipe/[token]`
2. Call `get-shared-recipe`
3. Render read-only UI for `status = active`
4. Render dedicated expired/revoked/not-found states otherwise
5. Save into local SQLite using existing local recipe persistence

---

## Verification Already Done

- `deno check` passed for:
  - `create-recipe-share`
  - `get-shared-recipe`
  - `cleanup-expired-recipe-shares`

Not done:
- no local migration run
- no deployed function test
- no end-to-end app wiring yet

