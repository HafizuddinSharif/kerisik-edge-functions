# Client Search Filter RPC Gap

## Purpose

The authenticated Kerisik mobile search screen needs a deterministic recipe search/list backend for the filter sheet UI. Supabase now exposes `search_browsable_recipes_filtered` for this use case, while the older RPCs remain useful for narrower flows.

Related client documentation: `nak-beli-apa-v2/docs/001-client-search-filter.md`.

## Current Usable RPCs

### `search_browsable_recipes`

Defined in `supabase/migrations/20260407001000_tokenize_search_browsable_recipes_rpc.sql`.

Use this for authenticated global recipe text search when the client only needs:

- `p_search`
- `p_platform`
- `p_tags`
- `p_limit`
- `p_offset`
- `p_include_dev_only`

The RPC searches all tokens from `p_search` across recipe name, recipe description, tags, and denormalized ingredient names. It sorts by `posted_date DESC NULLS LAST` and returns recipe summary rows with author JSON.

Limitations for the screenshot filter UI:

- no `cuisine_type` filter
- no taxonomy array filters for `meal_types`, `main_ingredient`, `cooking_method`, `flavor`, or `texture`
- no `dietary_tags` filter
- no `max_cooking_time` filter
- no exact `total_count`; callers infer `hasMore` from returned row count

### `search_browsable_recipes_filtered`

Defined in `supabase/migrations/20260427000000_add_search_browsable_recipes_filtered_rpc.sql`.

Use this for authenticated global recipe search/listing when the client needs deterministic hard filters, author filtering, and pagination metadata. It accepts:

- `p_search`
- `p_author_search`
- `p_cuisine_types`
- `p_meal_types`
- `p_main_ingredient`
- `p_cooking_method`
- `p_flavor`
- `p_texture`
- `p_dietary_tags`
- `p_max_cooking_time`
- `p_platform`
- `p_tags`
- `p_limit`
- `p_offset`
- `p_include_dev_only`

It preserves the recipe-card summary payload from `search_browsable_recipes` and adds `total_count` as a row-level pagination value.

### `get_collection_recipes`

Defined in `supabase/migrations/20260219000003_add_get_collection_recipes_rpc.sql`, then updated by later migrations including `20260221000000_sort_rpcs_by_posted_date.sql` and `20260222000000_add_posted_date_to_rpc_payloads.sql`.

Use this for collection-scoped recipe listing and text search only. It accepts:

- `p_collection_id`
- `p_limit`
- `p_offset`
- `p_search`
- `p_include_dev_only`

It is not a global search endpoint and does not accept the screenshot filter taxonomy fields.

### `get_onboarding_starter_recipes`

Defined in `supabase/migrations/20260423180000_add_onboarding_starter_recipes_rpc.sql`.

This RPC accepts many taxonomy inputs, including cuisine, meal types, main ingredient, dietary tags, cooking method, flavor, texture, difficulty, tags, and max cooking time.

Do not use it for the search filter sheet. It is recommendation-oriented, not search/list-oriented:

- it computes `match_score` and `matched_fields`
- it fetches a larger candidate pool internally
- it de-duplicates and applies variety ranking
- it fills sparse matches with popular/newer recipes
- it has `p_limit` but no `p_offset`
- it does not provide stable pagination or a total count

Those behaviors are useful for onboarding starter recommendations, but they are wrong for deterministic search filters.

## Implemented Backend Shape

The new authenticated recipe search/list RPC lets the mobile search screen send filter sheet state directly to Supabase without changing the existing `search_browsable_recipes` contract.

Implemented contract:

```sql
search_browsable_recipes_filtered(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0,
  p_search text DEFAULT NULL,
  p_author_search text DEFAULT NULL,
  p_cuisine_types text[] DEFAULT NULL,
  p_meal_types text[] DEFAULT NULL,
  p_main_ingredient text[] DEFAULT NULL,
  p_cooking_method text[] DEFAULT NULL,
  p_flavor text[] DEFAULT NULL,
  p_texture text[] DEFAULT NULL,
  p_dietary_tags text[] DEFAULT NULL,
  p_max_cooking_time integer DEFAULT NULL,
  p_platform public.social_media_platform DEFAULT NULL,
  p_tags text[] DEFAULT NULL,
  p_include_dev_only boolean DEFAULT false
)
```

The result should be deterministic and paginated:

- return only recipes matching all supplied hard filters
- keep optional `p_search` token behavior from `search_browsable_recipes`
- add separate `p_author_search` filtering against author `name` and `handle`
- support `LIMIT`/`OFFSET`
- sort predictably, currently `posted_date DESC NULLS LAST`
- include row-level `total_count`
- preserve the existing author JSON shape used by recipe cards

Filter semantics:

- `author_search`: case-insensitive substring search against `authors.name` and `authors.handle`
- `cuisine_types`: any-match equality after normalizing input consistently with stored values
- `meal_types`: overlap against `browsable_recipes.meal_types`
- `main_ingredient`: overlap against `browsable_recipes.main_ingredient`
- `cooking_method`: overlap against `browsable_recipes.cooking_method`
- `flavor`: overlap against `browsable_recipes.flavor`
- `texture`: overlap against `browsable_recipes.texture`
- `dietary_tags`: strict contains; recipes must satisfy all selected dietary filters
- `max_cooking_time`: `cooking_time <= p_max_cooking_time`
- when both `p_search` and `p_author_search` are supplied, combine them with `AND`

Normalization rules:

- lower + trim input text values
- treat empty arrays as `NULL`
- normalize stored taxonomy arrays with `unnest(... lower(btrim(value)))`
- normalize stored `cuisine_type` with `lower(btrim(...))`

## Environment Variables

No new environment variables are required for this documentation pass. Existing development visibility still depends on callers passing `p_include_dev_only` from app-side environment logic.

## Migration Notes

Implemented in `supabase/migrations/20260427000000_add_search_browsable_recipes_filtered_rpc.sql`.

The RPC is granted to `authenticated` and `service_role`. Anonymous access is intentionally not granted.

## Verification

Verify references with:

```sh
rg "search_browsable_recipes_filtered|search_browsable_recipes|get_onboarding_starter_recipes|001-client-search-filter" supabase-dev nak-beli-apa-v2
```

Cross-check the current behavior against:

- `supabase-dev/supabase/migrations/20260427000000_add_search_browsable_recipes_filtered_rpc.sql`
- `supabase-dev/supabase/migrations/20260407001000_tokenize_search_browsable_recipes_rpc.sql`
- `supabase-dev/supabase/migrations/20260423180000_add_onboarding_starter_recipes_rpc.sql`
- `nak-beli-apa-v2/app/search.tsx`
- `nak-beli-apa-v2/services/browsable-recipes.service.ts`
