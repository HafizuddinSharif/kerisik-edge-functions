# `dev_only` visibility (browsable recipes + collections)

Agent-facing summary for development-only visibility. Both `visibility_status` (browsable_recipes) and `collection_visibility` (collections) support `dev_only`.

## Migrations

- **`supabase/migrations/20260216000000_add_visibility_dev_only.sql`** — Adds enum value `'dev_only'` to `public.visibility_status` and `public.collection_visibility`. (Enum values are in a separate migration so they can be committed before any function that uses them.)
- **`supabase/migrations/20260216000001_add_visibility_dev_only_functions.sql`** — Updates `get_published_recipes` and `get_featured_collections` to accept `p_include_dev_only` and optionally return `dev_only` rows.

## Enums

- **`public.visibility_status`** (browsable_recipes): `draft` | `published` | `archived` | `removed` | `dev_only`
- **`public.collection_visibility`** (collections): `public` | `private` | `unlisted` | `dev_only`

**`dev_only`**: Shown only in development. In production the app must never include these in public listings.

## Enforcement (Option B: app-level)

- **RLS**: No special policy for `dev_only`.
  - **browsable_recipes**: Normal users see only `visibility_status = 'published'`; curators see all.
  - **collections**: Normal users see only `visibility = 'public'`; owners see their own via `select_own_collections`.
- **App responsibility**: In **development**, include `dev_only` when listing (e.g. pass `p_include_dev_only = true` to the functions below). In **production**, only query for `published` / `public` (omit the flag or pass `p_include_dev_only = false`).

## Listing recipes: `get_published_recipes`

```sql
get_published_recipes(
  p_limit INTEGER DEFAULT 20,
  p_offset INTEGER DEFAULT 0,
  p_platform social_media_platform DEFAULT NULL,
  p_tags TEXT[] DEFAULT NULL,
  p_include_dev_only BOOLEAN DEFAULT false  -- set true only in development
)
```

- **Production**: Call with 4 args or with `p_include_dev_only = false` (default). Returns only `visibility_status = 'published'`.
- **Development**: Call with `p_include_dev_only = true` to also return rows with `visibility_status = 'dev_only'`.

## Listing collections: `get_featured_collections`

```sql
get_featured_collections(
  p_limit INTEGER DEFAULT 5,
  p_include_dev_only BOOLEAN DEFAULT false  -- set true only in development
)
```

- **Production**: Omit second arg or pass `p_include_dev_only = false`. Returns only `visibility = 'public'`.
- **Development**: Pass `p_include_dev_only = true` to also return collections with `visibility = 'dev_only'`.

## Setting visibility

- **browsable_recipes**: `visibility_status` accepts `'dev_only'`.
- **collections**: `visibility` (type `collection_visibility`) accepts `'dev_only'`.
- Use `'dev_only'` for recipes or collections you want to see only in dev (e.g. test data, WIP).

## Dev check reference

The app already detects development in Edge Functions (e.g. `import-recipe`):  
`(Deno.env.get("NODE_ENV") || Deno.env.get("ENVIRONMENT") || "").toLowerCase() === "development"`. Use the same (or equivalent) before passing `p_include_dev_only = true`.
