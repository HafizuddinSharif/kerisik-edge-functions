<!-- b3e9e547-c595-44ca-baed-7e3924f1cdb9 c3f66c51-7ebb-41d3-8815-07217d06cb4b -->
# Refactor user_profile IDs and update import-recipe auth usage

### 1. Adjust `user_profile` schema to introduce `auth_id`

- **Add new column** in `prod.sql` and a new migration: `auth_id uuid` on `public.user_profile`, nullable but with a `UNIQUE` constraint and a foreign key to `auth.users(id)`.
- **Backfill data**: `UPDATE public.user_profile SET auth_id = id;` so existing auth IDs are preserved.
- **Drop old FK** `user_profile_id_fkey` that currently references `auth.users(id)` from `id`, since `id` will become the internal key.
- **Regenerate primary keys**: `UPDATE public.user_profile SET id = gen_random_uuid();` to create new internal IDs while keeping the primary key on `id`.
- **Update RLS policy** on `user_profile` in `prod.sql` so `auth.uid()` compares to `auth_id` instead of `id` (e.g. `USING (((SELECT auth.uid() AS uid) = auth_id))`).

### 2. Update signup trigger function to use `auth_id`

- **Update `create_user_on_signup` in `prod.sql` and its matching migration** (`20250713051516_remote_schema.sql`) to:
- Insert `gen_random_uuid()` into `id`.
- Insert `new.id` (from `auth.users`) into `auth_id`.
- Keep `email`, `is_pro` and `ai_imports_used` logic the same.
- **Align with existing `handle_new_user`** in `schemas/imported_content.sql` so both functions follow the same internal-ID vs auth-ID model.

### 3. Retarget `imported_content.user_id` to `user_profile.id`

- **Change FK definition** so `public.imported_content.user_id` references `public.user_profile(id)` instead of `auth.users(id)` (update both the relevant migration and `schemas/imported_content.sql`).
- **Migrate existing data** after `user_profile.auth_id` and new `id` values exist:
- `UPDATE public.imported_content ic SET user_id = up.id FROM public.user_profile up WHERE ic.user_id = up.auth_id;`
- **Update RLS policies** on `public.imported_content` so ownership checks use `auth.uid()` via `user_profile`, e.g. `WITH CHECK (EXISTS (SELECT 1 FROM public.user_profile up WHERE up.id = user_id AND up.auth_id = auth.uid()))` and similarly for `USING`.

### 4. Update the `import-recipe` Edge function to use `user_profile` row IDs

- **Change `getAuthenticatedUserIdOrThrow` in `supabase/functions/api/import-recipe/index.ts`** to:
- Call `getAuthenticatedUserOrThrow` to get the auth user.
- Query `public.user_profile` by `auth_id = user.id` and return the `id` from that row.
- Throw a clear error if no profile row is found.
- **Keep downstream usage** of `userId` as-is so that:
- `insertImportedContentProcessing` and related helpers write `user_id` as the `user_profile.id`.
- `incrementAiImportsUsedIfNeeded` still calls `rpc('increment_ai_imports_used', { user_id })`, which now passes the internal `user_profile.id`.

### 5. Verification and safety checks

- **Run migrations locally** to confirm constraints: verify `user_profile.auth_id` is unique and FK to `auth.users`, and `imported_content.user_id` FKs to `user_profile.id`.
- **Test signup flow** (or trigger function) to ensure new users get both an internal `id` and `auth_id` set correctly, and that `increment_ai_imports_used` works with the new IDs.
- **Exercise the `import-recipe` function** with a real authenticated request to confirm it resolves the `user_profile` row, writes `imported_content.user_id` correctly, and increments `ai_imports_used` without errors.

### To-dos

- [ ] Add `auth_id` column, constraints, backfill data, drop old FK, and regenerate `user_profile.id` as internal UUIDs.
- [ ] Update `create_user_on_signup` (and matching migration) to insert `gen_random_uuid()` into `id` and `new.id` into `auth_id`.
- [ ] Retarget `imported_content.user_id` to `user_profile.id`, migrate existing data, and fix RLS policies accordingly.
- [ ] Change `getAuthenticatedUserIdOrThrow` in `import-recipe/index.ts` to resolve and return `user_profile.id` via `auth_id`.
- [ ] Run migrations and test signup plus import-recipe flows to ensure IDs and permissions behave correctly.