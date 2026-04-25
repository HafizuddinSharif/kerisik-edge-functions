# Browsable Collection Public Read Handoff

**Status:** Implemented  
**Created:** April 24, 2026  
**Last Updated:** April 24, 2026  
**Scope:** Supabase backend for public browsable collection detail reads

---

## Summary

This repo now has a dedicated backend read path for public browsable collection pages.

The canonical browsable collection URL should resolve by slug when available:

- `https://kerisik.app/browse/collection/<slug>`

The route should call:

- `/functions/v1/get-browsable-collection`

This function supports lookup by either collection slug or collection UUID, but web should prefer slug-based routing.

---

## Implemented Files

### Edge function

- [get-browsable-collection/index.ts](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/functions/get-browsable-collection/index.ts)
- [get-browsable-collection/deno.json](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/functions/get-browsable-collection/deno.json)

### Existing source tables used by the function

- [20260202000000_create_recipe_collections.sql](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/migrations/20260202000000_create_recipe_collections.sql)
- [20260219000003_add_get_collection_recipes_rpc.sql](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/migrations/20260219000003_add_get_collection_recipes_rpc.sql)
- [browsable_recipes.sql](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/schemas/browsable_recipes.sql)
- [imported_content.sql](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/schemas/imported_content.sql)

---

## Current Backend Design

### Resource model

Browsable collections are first-class curated records in `public.collections`.

The edge function combines:

1. `collections`
2. `collection_recipes`
3. `browsable_recipes`
4. `imported_content.content` for preview image fallback

### Visibility rules

The public edge function returns `active` only when:

- a matching `collections` row exists
- `collections.visibility = 'public'`

Collections in `private`, `unlisted`, or `dev_only` are treated as not found by this public path.

Recipes included in the preview list are returned only when:

- `browsable_recipes.visibility_status = 'published'`

Recipes in `draft`, `archived`, `removed`, or `dev_only` are excluded from the preview list and from the visible count.

### Ordering rules

This endpoint preserves explicit collection curation order from the database:

- recipes are ordered by `collection_recipes.sort_order ASC`

This is intentionally different from the current `get_collection_recipes` RPC, which sorts by `posted_date`.

---

## Edge Function Interface

### `get-browsable-collection`

Route:

- `/functions/v1/get-browsable-collection`

Method:

- `GET`

Auth:

- not required

Supported inputs:

- query param: `?slug=<slug>`
- query param: `?id=<uuid>`

Lookup precedence:

- if both are provided, `slug` wins

Validation:

- either `slug` or `id` is required
- `id` must be a valid UUID when used
- `slug` is matched as an opaque string value

### Response envelope

Successful responses use the existing edge-function envelope:

```json
{
  "success": true,
  "error": null,
  "error_code": null,
  "data": {
    "status": "active",
    "canonicalSlug": "ramadan-dinner-ideas",
    "collection": {
      "title": "Ramadan Dinner Ideas",
      "description": "A curated set of easy meals for buka puasa.",
      "coverImageUrl": "https://example.com/collection-cover.jpg"
    },
    "recipes": [
      {
        "title": "Nasi Goreng Kampung",
        "imageUrl": "https://example.com/recipe-1.jpg"
      },
      {
        "title": "Ayam Masak Merah",
        "imageUrl": "https://example.com/recipe-2.jpg"
      }
    ],
    "totalVisibleRecipeCount": 14
  }
}
```

Possible `status` values:

- `active`
- `not_found`

### Inner payload shape

```ts
type BrowsableCollectionStatus = "active" | "not_found"

type BrowsableCollectionPreviewRecipe = {
  title: string
  imageUrl: string | null
}

type BrowsableCollectionPayload = {
  title: string | null
  description: string | null
  coverImageUrl: string | null
}

type BrowsableCollectionResponse = {
  status: BrowsableCollectionStatus
  canonicalSlug: string | null
  collection: BrowsableCollectionPayload | null
  recipes: BrowsableCollectionPreviewRecipe[]
  totalVisibleRecipeCount: number
}
```

### Not-found response

Missing or non-public collections return a successful response with `status: "not_found"`:

```json
{
  "success": true,
  "error": null,
  "error_code": null,
  "data": {
    "status": "not_found",
    "canonicalSlug": null,
    "collection": null,
    "recipes": [],
    "totalVisibleRecipeCount": 0
  }
}
```

### Validation and method errors

Example missing-identifier response:

```json
{
  "success": false,
  "error": "slug or id is required",
  "error_code": "MISSING_COLLECTION_IDENTIFIER",
  "data": null
}
```

Example invalid-UUID response:

```json
{
  "success": false,
  "error": "id must be a valid UUID",
  "error_code": "INVALID_COLLECTION_ID",
  "data": null
}
```

Behavior:

- successful public reads return `status: "active"`
- missing or non-public collections return `status: "not_found"`
- successful public reads trigger `increment_collection_views`
- view count is not incremented for `not_found`
- preview results are capped at 8 recipes
- `totalVisibleRecipeCount` is computed before the 8-item cap

---

## Payload Mapping

Current output mapping:

- `collections.name` -> `collection.title`
- `collections.description` -> `collection.description`
- `collections.cover_image_url` -> `collection.coverImageUrl`
- `collections.slug` -> `canonicalSlug`
- `browsable_recipes.meal_name` -> `recipes[].title`
- `browsable_recipes.image_url` -> `recipes[].imageUrl`

Image fallback rules:

- prefer `browsable_recipes.image_url`
- if null or blank, fallback to `imported_content.content.imageUrl`
- if still missing, fallback to `imported_content.content.image_url`

Normalization rules:

- blank strings are normalized to `null` for nullable collection/image fields
- preview recipe title falls back to an empty string only if the source field is unexpectedly blank

---

## Client Integration Notes

Recommended web behavior:

1. Prefer slug-based collection routes.
2. Call `/functions/v1/get-browsable-collection?slug=<slug>`.
3. If entering from an ID-based source, call `/functions/v1/get-browsable-collection?id=<uuid>`.
4. When an `active` response is returned from an ID lookup, use `canonicalSlug` to redirect to the canonical slug route.
5. Treat `not_found` as a normal empty-state/not-found page, not as a transport failure.

Notes:

- This endpoint is intentionally separate from collection listing/search RPCs.
- The function reads with service-role credentials, so public access is enforced in function logic rather than anon RLS reads.
- `dev_only` collections and recipes are intentionally excluded from this public path.
