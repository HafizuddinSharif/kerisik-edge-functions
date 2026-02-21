# Server-Side Search for Collection Recipes

This document describes how to implement server-side search when viewing a collection, so that users can find recipes anywhere in the collection (not only among already-loaded pages). Pass this to an agent or developer to implement.

---

## Goal

- **Current behavior:** Collection recipe search is client-side only. It filters over recipes already fetched (paginated via FlatList). Recipes that have not been loaded yet cannot be found.
- **Target behavior:** When the user types in the collection search bar, the app should call the backend with the search query. The backend returns only recipes in that collection that match the text (e.g. by `meal_name`, `meal_description`, `tags`). Pagination and "load more" should also use the same search query so results stay consistent.

---

## Context

- **Collection screen:** `app/browse/collection/[slugOrId].tsx` — shows recipes for one collection and a fixed search bar.
- **Store:** `hooks/useCollectionRecipesStore.ts` — holds `recipes`, `filteredRecipes`, `searchQuery`; calls `browseCollectionsService.listRecipesByCollectionId` / `listRecipesByCollectionSlug` for fetch and loadMore; applies client-side `filterRecipesBySearch` from `utils/recipeSearch.ts`.
- **Service:** `services/browse-collections.service.ts` — `listRecipesByCollectionId(collectionId, page, pageSize)` and `listRecipesByCollectionSlug(slug, page, pageSize)` query `collection_recipes` joined to `browsable_recipes`, ordered by `sort_order`, with no search parameter.
- **Recipe fields to search:** Match the client-side logic in `utils/recipeSearch.ts`: `meal_name`, `meal_description`, and `tags` (tokenized match; min 2 chars on client — backend can use same or similar, e.g. ILIKE or array/tag overlap).

---

## 1. Backend (Supabase)

### 1.1 Add an RPC for collection recipes with optional search

Create a PostgreSQL function that the app can call to list recipes in a collection with optional text filter.

**Suggested name:** `get_collection_recipes`

**Parameters:**

| Parameter           | Type    | Description                                      |
|--------------------|---------|--------------------------------------------------|
| `p_collection_id`  | UUID    | The collection id.                              |
| `p_limit`          | INTEGER | Page size (e.g. 20).                             |
| `p_offset`         | INTEGER | Offset for pagination (e.g. (page - 1) * limit).  |
| `p_search`         | TEXT    | Optional. When non-null/non-empty, filter recipes by this text. |
| `p_include_dev_only` | BOOLEAN | Optional. If true, include dev_only visibility (see existing RPCs like `get_collections`). |

**Behavior:**

- Join `collection_recipes` (filter by `collection_id = p_collection_id`) with `browsable_recipes` (via `recipe_id` or the existing FK).
- Apply visibility: same as existing patterns (e.g. `visibility_status = 'published'` or include `'dev_only'` when `p_include_dev_only` is true). Align with how `browsable_recipes` and `get_published_recipes` work.
- When `p_search` is null or empty: order by `collection_recipes.sort_order` ascending, then apply `LIMIT p_limit OFFSET p_offset`. Return the recipe rows and total count (for `hasMore`).
- When `p_search` is provided: add a WHERE on the recipe side so that `meal_name`, `meal_description`, or `tags` match the search (e.g. `ILIKE '%' || p_search || '%'` for name/description; for `tags` either array overlap or string concatenation + ILIKE depending on schema). Order can remain by `sort_order` or by relevance; then apply LIMIT/OFFSET. Return recipe rows and total count.

**Return shape:** Same as the current list response: array of recipe objects that match `BrowsableRecipeSummary` (id, meal_name, meal_description, image_url, cooking_time, author_id, author, platform, tags, cuisine_type, difficulty_level, featured, view_count). Include a way to get total count (e.g. one row with total_count, or a separate count query) so the client can compute `hasMore`.

Reference existing RPCs in the project:

- `get_collections` — takes `p_search`, `p_limit`, `p_offset` (see `services/browse-collections.service.ts`).
- `get_published_recipes` — takes `p_limit`, `p_offset` (see `services/browsable-recipes.service.ts`).

Add a migration (e.g. in Supabase migrations or in `docs/` as a SQL snippet) that creates this function and grants execute to the appropriate role.

---

## 2. Service layer

**File:** `services/browse-collections.service.ts`

### 2.1 Add optional `search` parameter

- Add an optional fourth parameter to both methods:
  - `listRecipesByCollectionId(collectionId, page, pageSize, search?: string)`
  - `listRecipesByCollectionSlug(slug, page, pageSize, search?: string)`

### 2.2 When search is provided

- If `search` is truthy (e.g. `search?.trim()`):
  - Call the new RPC: `supabase.rpc("get_collection_recipes", { p_collection_id: collectionId, p_limit: pageSize, p_offset: (page - 1) * pageSize, p_search: search.trim(), p_include_dev_only: shouldIncludeDevOnly() })`.
  - Map the RPC response to the existing `ListRecipesByCollectionResult` shape: `{ recipes, total, hasMore }`. Use the same `normalizeAuthor` helper for author normalization if the RPC returns raw rows.
  - Return that result.

### 2.3 When search is empty

- If `search` is absent or empty:
  - Keep the current implementation unchanged (query `collection_recipes` with join to `browsable_recipes`, order by `sort_order`, `.range()` for pagination). Do not call the RPC so behavior stays identical when the user is not searching.

### 2.4 Slug overload

- `listRecipesByCollectionSlug` should resolve slug to id (existing `getCollectionIdBySlug`), then call `listRecipesByCollectionId(collectionId, page, pageSize, search)` so the search parameter is passed through.

---

## 3. Store

**File:** `hooks/useCollectionRecipesStore.ts`

### 3.1 Pass search into the service

- When calling the service from `fetchRecipes` and `loadMore`, pass the current `searchQuery` (e.g. trimmed) as the fourth argument.
  - **Important:** For `fetchRecipes`, the store currently resets `searchQuery` to `""`. Change behavior so that when the user is searching, we do not reset the query on initial fetch for the same collection; or introduce a separate "fetch with search" flow. Prefer: `fetchRecipes(collectionIdOrSlug)` still resets state and loads page 1, but it should pass the current `searchQuery` from the previous render/store so that if the UI triggers a refetch when search changes (see below), the refetched data uses the new query. So: when search is applied from the UI, the store should refetch from page 1 with that search; the service calls should always include the current `searchQuery`.
- Simpler approach: add an optional parameter to the store’s fetch, e.g. `fetchRecipes(collectionIdOrSlug, searchQuery?)`. When the UI updates search, it calls `fetchRecipes(slugOrId, newSearchQuery)` to refetch page 1 with the new query. And `loadMore()` should pass the current `searchQuery` from the store to the service so the next page is also filtered.

### 3.2 Use server result as the single source when using server search

- When the backend supports search (i.e. when you pass a non-empty `search` to the service), the service returns already-filtered recipes. The store should then:
  - Set `recipes` and `filteredRecipes` to the same list (the server result). Do not apply client-side `filterRecipesBySearch` for that response.
- When the backend is not used with search (empty query), keep current behavior: set `recipes` from the response and derive `filteredRecipes` with `filterRecipesBySearch(recipes, searchQuery)` (so client-side filter still applies when search is empty and you have a local query, or you can keep search and filter only when server search is disabled; the end state should be: if server search is used, no client filter on top).

### 3.3 Refetch on search change

- When the user types in the search bar and you want to trigger a server search (e.g. on submit or after debounce), the UI should call something that refetches from page 1 with the new query. Options:
  - `filterRecipes` updates `searchQuery` and then triggers a refetch (e.g. call `fetchRecipes(collectionIdOrSlug, searchQuery)` from the store or from the screen with the current slug and new query), **or**
  - The screen debounces the search input and calls a new method like `searchRecipes(collectionIdOrSlug, searchQuery)` that resets page to 1 and fetches with that query.
- Ensure `loadMore` always passes the current `searchQuery` to the service so subsequent pages are filtered the same way.

### 3.4 Clear search when collection changes

- When `fetchRecipes` is called with a new `collectionIdOrSlug` (different from the previous one), reset `searchQuery` to `""` and clear recipes so the user does not see a stale filter from another collection. This is already partially the case; keep it.

---

## 4. UI (collection screen)

**File:** `app/browse/collection/[slugOrId].tsx`

- The search bar and list already use `filterRecipes`, `searchQuery`, and `filteredRecipes` from the store. Once the store uses server-side results when search is provided, the list will show server-filtered recipes.
- Optional: When server-side search is implemented, you can remove or simplify the "No matches in loaded recipes. Scroll down to load more, then try again." hint (e.g. show it only when search is empty and `hasMore` is true, or remove it and always show "No search results" when the server returns no matches).
- Optional: Trigger server search on submit or after a short debounce (e.g. 300–400 ms) so we don’t refetch on every keystroke. The store should expose a way to "refetch page 1 with current search" that the UI can call when the user commits the search (e.g. submit) or when the debounced value changes.

---

## 5. Summary checklist

- [ ] **Supabase:** Create RPC `get_collection_recipes(p_collection_id, p_limit, p_offset, p_search, p_include_dev_only)` that joins `collection_recipes` and `browsable_recipes`, optionally filters by `p_search` on meal_name/meal_description/tags, orders and paginates, returns recipe rows + total count.
- [ ] **Service:** In `browse-collections.service.ts`, add optional `search?: string` to `listRecipesByCollectionId` and `listRecipesByCollectionSlug`; when provided, call the RPC and map result to `ListRecipesByCollectionResult`; when empty, keep existing query.
- [ ] **Store:** In `useCollectionRecipesStore`, pass current `searchQuery` into the service on fetch and loadMore; when service is called with search, set `recipes` and `filteredRecipes` from server response (no client filter); when search changes (e.g. submit or debounce), refetch page 1 with new query; clear search when collection changes.
- [ ] **UI:** Keep existing search bar and list; optionally debounce or submit-trigger server search; optionally adjust empty-state hint as above.

---

## 6. File reference

| Area        | File path |
|------------|-----------|
| Service    | `services/browse-collections.service.ts` |
| Store      | `hooks/useCollectionRecipesStore.ts` |
| Collection screen | `app/browse/collection/[slugOrId].tsx` |
| Client-side filter (reference) | `utils/recipeSearch.ts` |
| Recipe summary type | `types/browsable-recipes.ts` — `BrowsableRecipeSummary` |
| Existing RPC usage | `get_collections` in same service; `get_published_recipes` in `services/browsable-recipes.service.ts` |
