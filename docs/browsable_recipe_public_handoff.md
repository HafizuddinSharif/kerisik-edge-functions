# Browsable Recipe Public Read Handoff

**Status:** In progress  
**Created:** April 10, 2026  
**Last Updated:** April 10, 2026  
**Scope:** Supabase backend for public browsable recipe detail reads

---

## Summary

This repo now has a dedicated backend read path for public browsable recipe pages.

The canonical browsable recipe URL stays:

- `https://kerisik.app/browse/recipe/<recipeId>`

That route should resolve a `browsable_recipes.id` UUID and call the new edge function:

- `/functions/v1/get-browsable-recipe`

This is intentionally separate from personal share links:

- `/shared/recipe/<token>` uses `get-shared-recipe`
- `/browse/recipe/<recipeId>` uses `get-browsable-recipe`

The goal is to keep public browsable recipes and temporary personal shares as two explicit resource types with different backend semantics.

---

## Implemented Files

### Edge function

- [get-browsable-recipe/index.ts](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/functions/get-browsable-recipe/index.ts)
- [get-browsable-recipe/deno.json](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/functions/get-browsable-recipe/deno.json)

### Existing source tables used by the function

- [browsable_recipes.sql](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/schemas/browsable_recipes.sql)
- [imported_content.sql](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/schemas/imported_content.sql)
- [20260201000000_create_authors_and_refactor_browsable_recipes.sql](/Users/hafizuddinsharif/Projects/KERISIK/supabase-dev/supabase/migrations/20260201000000_create_authors_and_refactor_browsable_recipes.sql)

---

## Current Backend Design

### Resource model

Browsable recipes are first-class curated records in `public.browsable_recipes`.

They differ from shared recipe links in a few important ways:

- identified by recipe UUID, not share token
- public visibility depends on `visibility_status`, not expiration
- no share TTL
- no revoked state
- no token-specific rate limiting
- view counts increment through browsable recipe metrics, not shared-link metrics

### Visibility rules

The public edge function currently returns data only when:

- `browsable_recipes.id = <recipeId>`
- `visibility_status = 'published'`

Rows in `draft`, `archived`, `removed`, or `dev_only` are treated as not found by this public path.

### Source data used for the response

The function combines three sources:

1. `browsable_recipes`
2. `imported_content.content`
3. `authors` when `author_id` is present

Field ownership is currently:

- title/description/image/cooking metadata: primarily from `browsable_recipes`
- ingredients/steps: from `imported_content.content`
- attribution metadata: assembled from browsable row + author row + any existing `content.attribution`

---

## Edge Function Interface

### `get-browsable-recipe`

Route:

- `/functions/v1/get-browsable-recipe`

Method:

- `GET`

Auth:

- not required

Supported recipe ID input:

- query param: `?recipeId=<uuid>`
- last path segment if routed that way upstream

Validation:

- `recipeId` is required
- `recipeId` must be a valid UUID

Response data shape:

```json
{
  "status": "active",
  "recipe": {
    "title": "Nasi Goreng Kampung",
    "description": "Savory fried rice with anchovies",
    "imageUrl": "https://example.com/image.jpg",
    "cookingTime": 20,
    "servingSuggestions": 2,
    "ingredients": [
      {
        "name": "Ingredients",
        "sortOrder": 1,
        "sub_ingredients": [
          {
            "name": "Rice",
            "quantity": "2",
            "unit": "cups",
            "sortOrder": 1
          }
        ]
      }
    ],
    "steps": [
      {
        "name": "Steps",
        "sub_steps": [
          "Heat oil"
        ]
      }
    ],
    "attribution": {
      "source": "browsable_recipe",
      "recipeId": "d7aa49f9-b41e-48d9-8e23-761d9810d5b5",
      "platform": "instagram",
      "originalPostUrl": "https://example.com/post",
      "postedDate": "2026-04-01T00:00:00.000Z",
      "author": {
        "id": "11111111-2222-3333-4444-555555555555",
        "name": "Chef Example",
        "handle": "@chefexample",
        "profileUrl": "https://example.com/chefexample",
        "profilePicUrl": "https://example.com/avatar.jpg",
        "platform": "instagram"
      }
    }
  },
  "imageUrl": "https://example.com/image.jpg"
}
```

Possible `status` values:

- `active`
- `not_found`

Behavior:

- successful reads return `status: "active"` and the normalized recipe payload
- missing or non-public recipes return `status: "not_found"` with `recipe: null`
- successful reads trigger `increment_recipe_views`
- the function does not return `expiresAt`
- the function does not return `expired` or `revoked`
- the function does not enforce shared-link rate limiting

---

## Payload Mapping

Current output mapping:

- `meal_name` -> `recipe.title`
- `meal_description` -> `recipe.description`
- `image_url` -> `recipe.imageUrl`
- `cooking_time` -> `recipe.cookingTime`
- `serving_suggestions` -> `recipe.servingSuggestions`
- `imported_content.content.ingredients` -> `recipe.ingredients`
- `imported_content.content.steps` -> `recipe.steps`

Normalization rules:

- flat ingredient arrays are wrapped into one default `"Ingredients"` group
- grouped ingredient arrays preserve `sub_ingredients`
- flat step arrays are wrapped into one default `"Steps"` group
- grouped step arrays preserve `sub_steps`
- mixed or malformed items are filtered out

Attribution rules:

- preserve any existing `imported_content.content.attribution` object if present
- add `source: "browsable_recipe"`
- add `recipeId`, `platform`, `originalPostUrl`, and `postedDate`
- add nested `author` metadata when `author_id` resolves

---

## Client Integration Notes

The app should keep explicit route-to-endpoint mapping:

- `/shared/recipe/<token>` -> `get-shared-recipe`
- `/browse/recipe/<recipeId>` -> `get-browsable-recipe`

Recommended client behavior:

1. Parse the route param as `recipeId`
2. Call `/functions/v1/get-browsable-recipe?recipeId=<uuid>`
3. If `status = "active"`, render the shared recipe viewer UI with the returned `recipe`
4. If `status = "not_found"`, show the public not-found state for browsable recipes

The renderer can stay shared as long as fetch selection happens before rendering.

---

## Known Constraints

- The public browsable route currently supports UUIDs only; there is no browsable recipe slug.
- Ingredients and steps depend on `imported_content.content` having the expected recipe shape.
- The function reads with service-role credentials, so public access is enforced in function logic, not through `anon` RLS access.
- `dev_only` rows are intentionally excluded from this public path.

---

## Suggested Manual Checks

1. Open a published browsable recipe URL:
   `https://kerisik.app/browse/recipe/d7aa49f9-b41e-48d9-8e23-761d9810d5b5`
2. Confirm the app calls:
   `/functions/v1/get-browsable-recipe?recipeId=d7aa49f9-b41e-48d9-8e23-761d9810d5b5`
3. Confirm the response contains `status: "active"`
4. Confirm ingredients and steps render in the same UI used by shared recipes
5. Confirm a non-published or invalid UUID produces the not-found state
6. Confirm `browsable_recipes.view_count` increments after a successful read

