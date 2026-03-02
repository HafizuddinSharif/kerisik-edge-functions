## Public schema tables overview

This document lists all tables in the `public` schema with their columns and row level security (RLS) configuration.

### `user_profile`

**RLS**: enabled  
**Policies**:
- `Enable read access for all users` (`SELECT`, roles: `{public}`, using: `true`)

**Columns**:
- `id` — `uuid`, default: `gen_random_uuid()`
- `created_at` — `timestamptz`, default: `now()`
- `modified_at` — `timestamp`, default: `now()`
- `is_pro` — `bool`, default: `false`
- `ai_imports_used` — `int4`, default: `0`
- `email` — `text`, nullable
- `auth_id` — `uuid`, nullable, unique

---

### `imported_content`

**RLS**: enabled  
**Policies**:
- `Users can insert their own imported content` (`INSERT`, roles: `{authenticated}`, check: `EXISTS (SELECT 1 FROM user_profile up WHERE up.id = imported_content.user_id AND up.auth_id = auth.uid())`)
- `Users can update their own imported content` (`UPDATE`, roles: `{authenticated}`, using: `EXISTS (SELECT 1 FROM user_profile up WHERE up.id = imported_content.user_id AND up.auth_id = auth.uid())`, check: `user_id IS NOT NULL AND EXISTS (SELECT 1 FROM user_profile up WHERE up.id = imported_content.user_id AND up.auth_id = auth.uid())`)
- `Users can view all imported content` (`SELECT`, roles: `{authenticated}`, using: `true`)
- `Users can view their own imported content` (`SELECT`, roles: `{authenticated}`, using: `EXISTS (SELECT 1 FROM user_profile up WHERE up.id = imported_content.user_id AND up.auth_id = auth.uid())`)

**Columns**:
- `id` — `uuid`, default: `gen_random_uuid()`
- `user_id` — `uuid`, nullable
- `source_url` — `text`
- `content` — `jsonb`, nullable
- `metadata` — `jsonb`, nullable
- `created_at` — `timestamptz`, default: `now()`
- `updated_at` — `timestamptz`, default: `now()`
- `is_recipe_content` — `bool`, nullable
- `status` — `imported_content_status`, nullable (`PROCESSING` | `COMPLETED` | `FAILED`)
- `video_duration` — `int4`, nullable
- `retry_count` — `int4`, default: `0`

---

### `browsable_recipes`

**RLS**: enabled  
**Policies**:
- `curators_insert_recipes` (`INSERT`, roles: `{authenticated}`, check: `curator_id IN (SELECT user_profile.id FROM user_profile WHERE user_profile.auth_id = auth.uid() AND user_profile.is_pro = true)`)
- `curators_update_own_recipes` (`UPDATE`, roles: `{authenticated}`, using: `curator_id IN (SELECT user_profile.id FROM user_profile WHERE user_profile.auth_id = auth.uid())`)
- `curators_view_all` (`SELECT`, roles: `{authenticated}`, using: `curator_id IN (SELECT user_profile.id FROM user_profile WHERE user_profile.auth_id = auth.uid() AND user_profile.is_pro = true)`)
- `view_published_recipes` (`SELECT`, roles: `{authenticated}`, using: `visibility_status = 'published'::visibility_status`)

**Columns**:
- `id` — `uuid`, default: `gen_random_uuid()`
- `imported_content_id` — `uuid`, unique
- `meal_name` — `text`
- `meal_description` — `text`, nullable
- `image_url` — `text`, nullable
- `cooking_time` — `int4`, nullable
- `serving_suggestions` — `int4`, nullable
- `platform` — `social_media_platform` (`tiktok` | `youtube` | `instagram` | `website` | `other`)
- `original_post_url` — `text`
- `posted_date` — `timestamptz`, nullable
- `engagement_metrics` — `jsonb`, nullable
- `tags` — `text[]`, nullable, default: `'{}'::text[]`
- `cuisine_type` — `text`, nullable
- `meal_type` — `text`, nullable
- `dietary_tags` — `text[]`, nullable, default: `'{}'::text[]`
- `difficulty_level` — `recipe_difficulty`, nullable (`easy` | `medium` | `hard`)
- `platform_metadata` — `jsonb`, nullable
- `visibility_status` — `visibility_status`, default: `'draft'::visibility_status` (`draft` | `published` | `archived` | `removed` | `dev_only`)
- `featured` — `bool`, default: `false`
- `featured_until` — `timestamptz`, nullable
- `curator_id` — `uuid`, nullable
- `curation_notes` — `text`, nullable
- `view_count` — `int4`, default: `0`
- `save_count` — `int4`, default: `0`
- `share_count` — `int4`, default: `0`
- `created_at` — `timestamptz`, default: `now()`
- `updated_at` — `timestamptz`, default: `now()`
- `published_at` — `timestamptz`, nullable
- `author_id` — `uuid`, nullable

---

### `authors`

**RLS**: enabled  
**Policies**:
- `authenticated_read_authors` (`SELECT`, roles: `{authenticated}`, using: `true`)

**Columns**:
- `id` — `uuid`, default: `gen_random_uuid()`
- `name` — `text`, nullable
- `handle` — `text`, nullable
- `profile_url` — `text`, nullable
- `profile_pic_url` — `text`, nullable
- `platform` — `social_media_platform` (`tiktok` | `youtube` | `instagram` | `website` | `other`)
- `created_at` — `timestamptz`, default: `now()`
- `updated_at` — `timestamptz`, default: `now()`

---

### `collections`

**RLS**: enabled  
**Policies**:
- `delete_own_collections` (`DELETE`, roles: `{authenticated}`, using: `EXISTS (SELECT 1 FROM user_profile WHERE user_profile.id = collections.created_by_user_id AND user_profile.auth_id = auth.uid())`)
- `insert_collections` (`INSERT`, roles: `{authenticated}`, check: `EXISTS (SELECT 1 FROM user_profile WHERE user_profile.id = collections.created_by_user_id AND user_profile.auth_id = auth.uid())`)
- `select_own_collections` (`SELECT`, roles: `{authenticated}`, using: `EXISTS (SELECT 1 FROM user_profile WHERE user_profile.id = collections.created_by_user_id AND user_profile.auth_id = auth.uid())`)
- `select_public_collections` (`SELECT`, roles: `{authenticated}`, using: `visibility = 'public'::collection_visibility`)
- `update_own_collections` (`UPDATE`, roles: `{authenticated}`, using: `EXISTS (SELECT 1 FROM user_profile WHERE user_profile.id = collections.created_by_user_id AND user_profile.auth_id = auth.uid())`, check: `EXISTS (SELECT 1 FROM user_profile WHERE user_profile.id = collections.created_by_user_id AND user_profile.auth_id = auth.uid())`)

**Columns**:
- `id` — `uuid`, default: `gen_random_uuid()`
- `name` — `text`
- `description` — `text`, nullable
- `type` — `collection_type` (`author` | `cuisine` | `dietary` | `meal_type` | `custom`)
- `visibility` — `collection_visibility`, default: `'public'::collection_visibility` (`public` | `private` | `unlisted` | `dev_only`)
- `cover_image_url` — `text`, nullable
- `icon` — `text`, nullable
- `color_theme` — `text`, nullable
- `created_by_user_id` — `uuid`, nullable
- `author_id` — `uuid`, nullable, unique
- `recipe_count` — `int4`, default: `0`
- `view_count` — `int4`, default: `0`
- `slug` — `text`, nullable, unique, check: `slug ~ '^[a-z0-9-]+$'::text`
- `tags` — `text[]`, nullable
- `created_at` — `timestamptz`, default: `now()`
- `updated_at` — `timestamptz`, default: `now()`
- `is_featured` — `bool`, default: `false`
- `featured_order` — `int4`, nullable
- `featured_at` — `timestamptz`, nullable

---

### `collection_recipes`

**RLS**: enabled  
**Policies**:
- `delete_own_collection_recipes` (`DELETE`, roles: `{authenticated}`, using: `EXISTS (SELECT 1 FROM collections c JOIN user_profile up ON c.created_by_user_id = up.id WHERE c.id = collection_recipes.collection_id AND up.auth_id = auth.uid())`)
- `insert_own_collection_recipes` (`INSERT`, roles: `{authenticated}`, check: `EXISTS (SELECT 1 FROM collections c JOIN user_profile up ON c.created_by_user_id = up.id WHERE c.id = collection_recipes.collection_id AND up.auth_id = auth.uid())`)
- `select_own_collection_recipes` (`SELECT`, roles: `{authenticated}`, using: `EXISTS (SELECT 1 FROM collections c JOIN user_profile up ON c.created_by_user_id = up.id WHERE c.id = collection_recipes.collection_id AND up.auth_id = auth.uid())`)
- `select_public_collection_recipes` (`SELECT`, roles: `{authenticated}`, using: `EXISTS (SELECT 1 FROM collections WHERE collections.id = collection_recipes.collection_id AND collections.visibility = 'public'::collection_visibility)`)
- `update_own_collection_recipes` (`UPDATE`, roles: `{authenticated}`, using: `EXISTS (SELECT 1 FROM collections c JOIN user_profile up ON c.created_by_user_id = up.id WHERE c.id = collection_recipes.collection_id AND up.auth_id = auth.uid())`)

**Columns**:
- `id` — `uuid`, default: `gen_random_uuid()`
- `collection_id` — `uuid`
- `recipe_id` — `uuid`
- `sort_order` — `int4`, default: `0`
- `added_by_user_id` — `uuid`, nullable
- `curator_note` — `text`, nullable
- `is_featured` — `bool`, default: `false`
- `added_at` — `timestamptz`, default: `now()`

---

### `collection_metrics`

**RLS**: disabled  
**Policies**: _none (RLS off)_

**Columns**:
- `id` — `uuid`, default: `gen_random_uuid()`
- `collection_id` — `uuid`
- `date` — `date`
- `views` — `int4`, nullable, default: `0`
- `recipe_additions` — `int4`, nullable, default: `0`
- `created_at` — `timestamptz`, default: `now()`

