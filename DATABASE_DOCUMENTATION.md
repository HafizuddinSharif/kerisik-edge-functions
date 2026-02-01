# Supabase Database Documentation

**Last Updated:** December 2024  
**Database:** Supabase PostgreSQL  
**Schema:** `public`

## Table of Contents

1. [Overview](#overview)
2. [Tables](#tables)
   - [user_profile](#user_profile)
   - [imported_content](#imported_content)
3. [Custom Types](#custom-types)
4. [Functions](#functions)
5. [Row Level Security (RLS)](#row-level-security-rls)
6. [Migrations History](#migrations-history)

---

## Overview

The database consists of two main tables:
- **user_profile**: Stores user account information and preferences
- **imported_content**: Stores content imported from external URLs (recipes, videos, etc.)

The database uses Row Level Security (RLS) to enforce access control, and includes several helper functions for user management and content tracking.

---

## Tables

### user_profile

Stores user account information linked to Supabase Auth users.

**Columns:**

| Column Name | Data Type | Nullable | Default | Description |
|------------|-----------|----------|---------|-------------|
| `id` | `uuid` | NO | `gen_random_uuid()` | Primary key - Internal profile ID (separate from auth ID) |
| `auth_id` | `uuid` | YES | `NULL` | Foreign key to `auth.users.id` - Unique identifier linking to Supabase Auth |
| `email` | `text` | YES | `NULL` | User's email address |
| `created_at` | `timestamptz` | NO | `now()` | Timestamp when profile was created |
| `modified_at` | `timestamp` | NO | `now()` | Timestamp when profile was last modified |
| `is_pro` | `boolean` | NO | `false` | Whether user has pro subscription |
| `ai_imports_used` | `integer` | NO | `0` | Counter for AI imports used by the user |

**Constraints:**
- **Primary Key:** `id`
- **Unique Constraint:** `auth_id` (ensures one profile per auth user)
- **Foreign Key:** `auth_id` → `auth.users.id` (ON UPDATE CASCADE, ON DELETE CASCADE)

**Row Count:** 16 rows

**RLS:** Enabled

**Key Design Notes:**
- The `id` field is an internal UUID that's separate from the auth user ID
- The `auth_id` field links to Supabase Auth users
- This design allows for anonymization (setting `user_id` to NULL in `imported_content`) when deleting accounts while preserving content

---

### imported_content

Stores content imported from external URLs, such as recipes, videos, and other media.

**Columns:**

| Column Name | Data Type | Nullable | Default | Description |
|------------|-----------|----------|---------|-------------|
| `id` | `uuid` | NO | `gen_random_uuid()` | Primary key |
| `user_id` | `uuid` | YES | `NULL` | User who imported this content (no FK constraint - allows anonymization) |
| `source_url` | `text` | NO | `NULL` | Original URL from which content was imported |
| `content` | `jsonb` | YES | `NULL` | Main content data in JSON format |
| `metadata` | `jsonb` | YES | `NULL` | Additional metadata in JSON format |
| `status` | `imported_content_status` | YES | `NULL` | Processing status (enum: PROCESSING, COMPLETED, FAILED) |
| `is_recipe_content` | `boolean` | YES | `NULL` | Whether this content is a recipe |
| `video_duration` | `integer` | YES | `NULL` | Duration of video content in seconds (if applicable) |
| `retry_count` | `integer` | NO | `0` | Number of retry attempts for processing |
| `created_at` | `timestamptz` | NO | `now()` | Timestamp when record was created |
| `updated_at` | `timestamptz` | NO | `now()` | Timestamp when record was last updated |

**Constraints:**
- **Primary Key:** `id`
- **No Foreign Key on `user_id`:** Intentionally removed to allow anonymization (setting to NULL) when deleting user accounts

**Row Count:** 82 rows

**RLS:** Enabled

**Key Design Notes:**
- `user_id` can be NULL to support account deletion while preserving content
- Content and metadata are stored as JSONB for flexibility
- Status tracking supports retry logic via `retry_count`

---

## Custom Types

### imported_content_status

Enum type for tracking the processing status of imported content.

**Values:**
- `PROCESSING` - Content is currently being processed
- `COMPLETED` - Content processing completed successfully
- `FAILED` - Content processing failed

**Usage:** Used in the `imported_content.status` column.

---

## Functions

### create_user_on_signup()

**Type:** Trigger Function  
**Returns:** `trigger`  
**Security:** `SECURITY DEFINER`

Automatically creates a user profile when a new user signs up in Supabase Auth.

**Behavior:**
- If a profile with the same email already exists, updates its `auth_id` to match the new auth user
- Otherwise, creates a new profile with:
  - New UUID for `id`
  - Auth user's ID for `auth_id`
  - User's email
  - `is_pro = false`
  - `ai_imports_used = 0`

**Trigger:** Should be attached to `auth.users` table (INSERT event).

---

### increment_ai_imports_used(user_id uuid)

**Type:** Function  
**Returns:** `integer` (the new count)  
**Security:** `SECURITY DEFINER`  
**Parameters:**
- `user_id` (uuid): The internal profile ID (not auth_id)

Increments the AI imports counter for a user and returns the new count.

**Behavior:**
- Increments `ai_imports_used` by 1
- Updates `modified_at` timestamp
- Returns the new `ai_imports_used` value
- Raises exception if user profile not found

**Usage Example:**
```sql
SELECT increment_ai_imports_used('user-profile-uuid-here');
```

---

### create_user_profile_from_email(p_email text)

**Type:** Function  
**Returns:** `void`  
**Security:** `SECURITY DEFINER`  
**Parameters:**
- `p_email` (text): Email address to create profile for

Creates a user profile from an email address if one doesn't already exist.

**Behavior:**
- Checks if a profile with the given email already exists
- If not, creates a new profile with:
  - New UUID for `id`
  - Email address
  - `is_pro = false`
  - `ai_imports_used = 0`
  - `auth_id = NULL` (can be set later)

**Usage Example:**
```sql
SELECT create_user_profile_from_email('user@example.com');
```

**Note:** This function does not link to an auth user. Use `create_user_on_signup()` for that purpose.

---

## Row Level Security (RLS)

### user_profile

**RLS Status:** Enabled

**Policies:**

1. **Enable users to view their own data only** (SELECT)
   - **Command:** SELECT
   - **Target:** `authenticated`
   - **Condition:** `auth.uid() = auth_id`
   - **Description:** Users can only view their own profile data

**Note:** No INSERT, UPDATE, or DELETE policies are defined. These operations are handled by functions with `SECURITY DEFINER`.

---

### imported_content

**RLS Status:** Enabled

**Policies:**

1. **Users can view all imported content** (SELECT)
   - **Command:** SELECT
   - **Target:** `authenticated`
   - **Condition:** `true`
   - **Description:** All authenticated users can view all imported content

2. **Users can view their own imported content** (SELECT)
   - **Command:** SELECT
   - **Target:** `authenticated`
   - **Condition:** `EXISTS (SELECT 1 FROM user_profile up WHERE up.id = user_id AND up.auth_id = auth.uid())`
   - **Description:** Users can view content they own (may be redundant with policy #1)

3. **Users can insert their own imported content** (INSERT)
   - **Command:** INSERT
   - **Target:** `authenticated`
   - **WITH CHECK:** `EXISTS (SELECT 1 FROM user_profile up WHERE up.id = user_id AND up.auth_id = auth.uid())`
   - **Description:** Users can only insert content with their own `user_id`

4. **Users can update their own imported content** (UPDATE)
   - **Command:** UPDATE
   - **Target:** `authenticated`
   - **USING:** `EXISTS (SELECT 1 FROM user_profile up WHERE up.id = user_id AND up.auth_id = auth.uid())`
   - **WITH CHECK:** `user_id IS NOT NULL AND EXISTS (SELECT 1 FROM user_profile up WHERE up.id = user_id AND up.auth_id = auth.uid())`
   - **Description:** Users can only update their own content, and cannot change ownership (cannot set `user_id` to NULL or another user's ID)

**Note:** There are multiple SELECT policies. PostgreSQL will allow access if any policy grants it, so the "view all" policy effectively makes the "view own" policy redundant.

---

## Migrations History

The database has evolved through the following migrations:

1. **20250713051516_remote_schema** - Initial remote schema setup
2. **20250713052643_imported_content_table** - Created `imported_content` table
3. **20250717091358_change_content_column_type_to_jsonb** - Changed content column to JSONB
4. **20250718030704_add_new_function_increment_ai_imports_used** - Added `increment_ai_imports_used()` function
5. **20250718033009_allow_any_authenticated_users_to_view_imported_content** - Added policy allowing all authenticated users to view imported content
6. **20251030081001_add_new_columns_imported_content** - Added `is_recipe_content`, `status`, and `video_duration` columns
7. **20251030082508_remove_not_null_for_status** - Made `status` column nullable
8. **20251123090000_update_user_profile_auth_and_imported_content** - Major refactor:
   - Added `auth_id` to `user_profile`
   - Separated internal `id` from auth user ID
   - Updated RLS policies to use `auth_id`
   - Rewired `imported_content.user_id` to point to `user_profile.id`
9. **20251123120000_create_user_profile_from_email_function** - Added `create_user_profile_from_email()` function
10. **20251123121000_update_create_user_profile_from_email_function** - Updated the function
11. **20251123122000_update_create_user_on_signup_check_email** - Updated `create_user_on_signup()` to check for existing email
12. **20251207000000_add_retry_count_to_imported_content** - Added `retry_count` column with default 0
13. **20251219183841_drop_imported_content_user_id_fk** - Removed foreign key constraint on `imported_content.user_id` to allow anonymization

---

## Database Statistics

- **Total Tables:** 2
- **Total Functions:** 3
- **Total Custom Types:** 1 (enum)
- **RLS Enabled Tables:** 2
- **Total Migrations:** 13

---

## Important Notes

1. **User ID Separation:** The `user_profile` table uses separate internal IDs (`id`) and auth IDs (`auth_id`). This design allows for better data management and anonymization.

2. **Anonymization Support:** The `imported_content.user_id` field has no foreign key constraint, allowing it to be set to NULL when deleting user accounts while preserving the content.

3. **RLS Policy Overlap:** The `imported_content` table has overlapping SELECT policies. The "view all" policy effectively grants access to all authenticated users.

4. **Function Security:** All custom functions use `SECURITY DEFINER`, meaning they run with the privileges of the function owner (typically `postgres`), not the caller.

5. **No Triggers:** Currently, there are no database triggers defined. The `create_user_on_signup()` function should be attached as a trigger on `auth.users` if automatic profile creation is desired.

---

## Extensions

The database uses the following PostgreSQL extensions:
- `pgsodium` - Cryptographic functions
- `pg_graphql` - GraphQL support
- `pg_stat_statements` - Query statistics
- `pgcrypto` - Additional cryptographic functions
- `pgjwt` - JWT token support
- `supabase_vault` - Vault functionality
- `uuid-ossp` - UUID generation

---

*This documentation was generated from the current database schema and migration history.*
