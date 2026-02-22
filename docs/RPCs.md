# Supabase RPCs Reference

This document lists all Remote Procedure Calls (RPCs) in the project that can be invoked via `supabase.rpc()`.

---

## Collections

### `get_collections`

General collection listing with optional filters.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_limit` | integer | 20 | Max results to return |
| `p_offset` | integer | 0 | Pagination offset |
| `p_type` | text | NULL | Filter by collection type (`author`, `cuisine`, `dietary`, `meal_type`, `custom`) |
| `p_search` | text | NULL | Search in name/description |
| `p_is_featured` | boolean | NULL | Filter by featured status |
| `p_include_dev_only` | boolean | false | Include dev_only visibility (use true only in development) |

**Returns:** Table of collections with `total_count` for pagination.

**Grants:** `anon`, `authenticated`

---

### `get_collection_recipes`

List recipes in a collection with optional text search.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_collection_id` | uuid | required | Collection ID |
| `p_limit` | integer | 20 | Max results |
| `p_offset` | integer | 0 | Pagination offset |
| `p_search` | text | NULL | Search in meal_name, meal_description, tags |
| `p_include_dev_only` | boolean | false | Include dev_only recipes (use true only in development) |

**Returns:** Table of recipes with author JSON, `posted_date`, and `total_count`. Results are sorted by posted_date (newest first; nulls last).

**Grants:** `anon`, `authenticated`

---

### `get_featured_collections`

Returns featured collections, optionally including dev_only.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_limit` | integer | 5 | Max results |
| `p_include_dev_only` | boolean | false | Include dev_only (use true only in development) |

**Returns:** Set of collections.

**Grants:** (varies; check migration)

---

### `set_collection_featured`

Mark a collection as featured or unfeatured with optional sort order.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_collection_id` | uuid | required | Collection ID |
| `p_is_featured` | boolean | required | Whether to feature |
| `p_featured_order` | integer | NULL | Sort order (lower = higher priority) |

**Returns:** void

---

### `get_or_create_collection`

Get existing collection by criteria, or create a new one.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_type` | collection_type | required | `author`, `cuisine`, `dietary`, `meal_type`, `custom` |
| `p_name` | text | required | Collection name |
| `p_author_id` | uuid | NULL | Required when type is `author` |
| `p_description` | text | NULL | Optional description |
| `p_tags` | text[] | NULL | Optional tags |

**Returns:** uuid (collection id)

---

### `add_recipe_to_collection`

Add a recipe to a collection.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_collection_id` | uuid | required | Collection ID |
| `p_recipe_id` | uuid | required | Recipe ID |
| `p_user_id` | uuid | NULL | User who added it |
| `p_curator_note` | text | NULL | Optional note |
| `p_is_featured` | boolean | false | Mark as featured in collection |

**Returns:** uuid (collection_recipe id)

---

### `increment_collection_views`

Increment the view count for a collection.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `p_collection_id` | uuid | Collection ID |

**Returns:** void

---

## Recipes (Browsable)

### `get_published_recipes`

Retrieve published recipes with pagination and optional filters.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_limit` | integer | 20 | Max results |
| `p_offset` | integer | 0 | Pagination offset |
| `p_platform` | social_media_platform | NULL | Filter by platform (`tiktok`, `youtube`, `instagram`, `website`, `other`) |
| `p_tags` | text[] | NULL | Filter by tags (overlap) |
| `p_include_dev_only` | boolean | false | Include dev_only recipes (use true only in development) |

**Returns:** Table of recipes (id, meal_name, meal_description, image_url, cooking_time, platform, tags, view_count, posted_date, published_at). Results are sorted by posted_date (newest first; nulls last).

**Grants:** `authenticated`, `service_role`

---

### `create_browsable_recipe`

Create a browsable recipe from imported content.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_imported_content_id` | uuid | required | Imported content ID |
| `p_author_name` | text | NULL | Author display name |
| `p_author_handle` | text | NULL | Author handle |
| `p_author_profile_url` | text | NULL | Author profile URL |
| `p_author_profile_pic_url` | text | NULL | Author profile picture URL |
| `p_platform` | social_media_platform | 'website' | Platform |
| `p_tags` | text[] | '{}' | Tags |
| `p_curator_id` | uuid | NULL | Curator user ID |

**Returns:** uuid (recipe id)

**Grants:** `authenticated`, `service_role`

---

### `publish_browsable_recipe`

Publish a draft recipe.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `p_recipe_id` | uuid | Recipe ID |

**Returns:** boolean (true if published)

**Grants:** `authenticated`, `service_role`

---

### `increment_recipe_views`

Increment the view count for a recipe.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `p_recipe_id` | uuid | Recipe ID |

**Returns:** integer (new view count)

**Grants:** `authenticated`, `service_role`

---

## Authors

### `get_or_create_author`

Get existing author by platform/profile or create a new one.

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `p_platform` | social_media_platform | required | Platform |
| `p_name` | text | NULL | Author name |
| `p_handle` | text | NULL | Author handle |
| `p_profile_url` | text | NULL | Profile URL |
| `p_profile_pic_url` | text | NULL | Profile picture URL |

**Returns:** uuid (author id)

**Grants:** `authenticated`, `service_role`

---

## User Profile & Auth

### `create_user_profile_from_email`

Create or ensure a user_profile row exists for an auth user (OAuth flow).

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `p_email` | text | User email (must exist in auth.users) |

**Returns:** void

**Usage:** `supabase.rpc('create_user_profile_from_email', { p_email: '<user-email>' })`

---

### `increment_ai_imports_used`

Increment the AI imports used count for a user.

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `user_id` | uuid | User profile ID |

**Returns:** integer (new ai_imports_used count)

---

## Excluded: Trigger Functions (not RPCs)

These functions are invoked by triggers and are not intended to be called directly as RPCs:

| Function | Purpose |
|----------|---------|
| `update_collection_recipe_count` | Keeps `recipe_count` in sync on collection_recipes insert/delete |
| `generate_collection_slug` | Auto-generates slug for collections |
| `update_authors_updated_at` | Updates `updated_at` on authors |
| `update_browsable_recipes_updated_at` | Updates `updated_at` on browsable_recipes |
| `create_user_on_signup` | Creates user_profile on auth signup |
