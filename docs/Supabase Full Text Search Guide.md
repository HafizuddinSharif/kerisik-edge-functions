# Supabase Full‑Text Search + Pagination Guide

This guide explains how to optimize paginated search in Supabase (Postgres) using **Full‑Text Search (FTS)** with a GIN index.

---

## 🚨 Problem

Using:

```sql
ILIKE '%search%'
```

Causes:

* Sequential scans (no index usage)
* Slow queries on large datasets
* Pagination feeling like it loads everything

Even with `LIMIT` and `OFFSET`, Postgres must scan all matching rows first.

---

# ✅ Solution Overview

We will:

1. Add a generated `tsvector` column
2. Add a GIN index
3. Update the RPC search condition
4. Reset pagination correctly on the frontend

---

# 1️⃣ Add a Generated Search Vector Column

Run this in Supabase SQL Editor:

```sql
ALTER TABLE public.browsable_recipes
ADD COLUMN search_vector tsvector
GENERATED ALWAYS AS (
  to_tsvector(
    'simple',
    coalesce(meal_name, '') || ' ' ||
    coalesce(meal_description, '') || ' ' ||
    array_to_string(tags, ' ')
  )
) STORED;
```

### Why use `'simple'` dictionary?

* Works better for multilingual content
* Avoids aggressive word stemming
* Safer for recipe names and tags

---

# 2️⃣ Create a GIN Index (Critical Step)

```sql
CREATE INDEX idx_browsable_recipes_search
ON public.browsable_recipes
USING GIN (search_vector);
```

This allows Postgres to search efficiently instead of scanning the entire table.

---

# 3️⃣ Update Your RPC Function

### ❌ Remove This

```sql
AND (
  NULLIF(trim(p_search), '') IS NULL
  OR br.meal_name ILIKE '%' || trim(p_search) || '%'
  OR coalesce(br.meal_description, '') ILIKE '%' || trim(p_search) || '%'
  OR array_to_string(br.tags, ' ') ILIKE '%' || trim(p_search) || '%'
)
```

### ✅ Replace With This

```sql
AND (
  NULLIF(trim(p_search), '') IS NULL
  OR br.search_vector @@ plainto_tsquery('simple', trim(p_search))
)
```

Now search is:

* Indexed
* Fast
* Fully compatible with LIMIT/OFFSET
* Scalable

---

# 4️⃣ Optional: Add Relevance Ranking

If you want search results ordered by relevance:

### Add rank to SELECT

```sql
ts_rank(
  br.search_vector,
  plainto_tsquery('simple', trim(p_search))
) AS rank
```

### Update ORDER BY

```sql
ORDER BY rank DESC, br.posted_date DESC
```

This improves search quality significantly.

---

# 5️⃣ Frontend (Expo + FlatList)

When search changes, reset pagination:

```ts
useEffect(() => {
  setRecipes([])
  setOffset(0)
  fetchRecipes(search, 0)
}, [search])
```

When loading more:

```ts
fetchRecipes(search, currentOffset + limit)
```

### Important Rules

* Always reset data when search changes
* Do not append old data from previous search
* Keep search state separate from pagination state

---

# ⚡ Optional Upgrade: Cursor Pagination

If collections may exceed thousands of rows, consider replacing OFFSET pagination with cursor-based pagination using `posted_date`.

Example condition:

```sql
AND (p_cursor IS NULL OR br.posted_date < p_cursor)
ORDER BY br.posted_date DESC
LIMIT p_limit;
```

Cursor pagination scales better for very large datasets.

---

# 🎯 Final Result

After implementing this:

* Search remains paginated
* No full table scans
* Lazy loading works properly
* UX becomes significantly faster
* Query scales cleanly as your dataset grows

---

## Recommended Order of Implementation

1. Add `search_vector`
2. Add GIN index
3. Update RPC
4. Test performance
5. (Optional) Add ranking
6. (Optional) Switch to cursor pagination

---

You now have production‑grade search architecture in Supabase 🚀
