# Onboarding Starter Recipes RPC

## Purpose

Define the Supabase RPC used by onboarding screen 6 to fetch 6-8 starter recipe candidates from `browsable_recipes`.

This RPC should be separate from the existing browse/search RPCs because onboarding needs taxonomy-aware matching, category balancing, ranking, and fallback behavior.

Related docs:

- [new-onboarding-flow.md](./new-onboarding-flow.md)
- [cuisine-id-mapping.md](./cuisine-id-mapping.md)
- [reference/recipe-tag-taxonomy.md](./reference/recipe-tag-taxonomy.md)

## Proposed RPC

```sql
get_onboarding_starter_recipes(...)
```

## Inputs

All array inputs are optional. Empty arrays should behave the same as `null`.

```sql
p_cuisine_types text[] default null,
p_meal_types text[] default null,
p_course text[] default null,
p_main_ingredient text[] default null,
p_dietary_tags text[] default null,
p_cooking_method text[] default null,
p_flavor text[] default null,
p_occasion text[] default null,
p_texture text[] default null,
p_difficulty_levels recipe_difficulty[] default null,
p_tags text[] default null,
p_legacy_meal_types text[] default null,
p_max_cooking_time integer default null,
p_limit integer default 8,
p_include_dev_only boolean default false
```

## Output Shape

Return card-ready recipe rows plus scoring metadata for debugging and client-side variety logic.

```sql
table (
  id uuid,
  meal_name text,
  meal_description text,
  image_url text,
  cooking_time integer,
  cuisine_type text,
  meal_types text[],
  course text[],
  main_ingredient text[],
  dietary_tags text[],
  cooking_method text[],
  flavor text[],
  occasion text[],
  texture text[],
  difficulty_level recipe_difficulty,
  tags text[],
  author_id uuid,
  author jsonb,
  platform social_media_platform,
  original_post_url text,
  view_count integer,
  save_count integer,
  published_at timestamptz,
  match_score integer,
  matched_fields text[]
)
```

## Matching Rules

The RPC should include recipes where at least one supplied filter matches.

Recommended field behavior:

- `cuisine_type`: case-insensitive match against `p_cuisine_types`
- taxonomy arrays: overlap match using `&&`
- `dietary_tags`: overlap match for onboarding discovery; use contains only if future requirements need strict dietary filtering
- `difficulty_level`: match any value in `p_difficulty_levels`
- `tags`: overlap match using normalized aliases
- `meal_type`: legacy fallback via `p_legacy_meal_types`
- `cooking_time`: include rows where `cooking_time <= p_max_cooking_time`

Visibility:

- default: `visibility_status = 'published'`
- when `p_include_dev_only = true`: allow `visibility_status in ('published', 'dev_only')`

## Scoring Rules

Use `match_score` to rank stronger taxonomy matches above weak alias-only matches.

Suggested scoring:

| Match | Points |
| --- | ---: |
| `cuisine_type` match | 30 |
| `meal_types` match | 30 |
| `occasion` match | 30 |
| `course` match | 20 |
| `main_ingredient` match | 15 |
| `cooking_method` match | 15 |
| `flavor` match | 15 |
| `texture` match | 10 |
| `dietary_tags` match | 10 |
| `difficulty_level` match | 10 |
| `cooking_time <= p_max_cooking_time` | 10 |
| `tags` match | 8 |
| legacy `meal_type` match | 5 |

Tie-breakers:

1. higher `match_score`
2. higher `save_count`
3. higher `view_count`
4. newer `published_at`

If `seed_popularity_score` is added later, it should become the first tie-breaker after `match_score`.

## Variety Rules

The RPC can return a larger candidate pool internally, then trim to `p_limit`.

Recommended v1 behavior:

- fetch up to `greatest(p_limit * 4, 24)` matching candidates internally
- avoid returning more than 2 recipes with the same `cuisine_type` when enough alternatives exist
- avoid returning near-duplicates with the same `meal_name`
- prefer recipes with images for onboarding cards
- prefer rows with populated `cooking_time`

If SQL-only balancing becomes too complex, keep the RPC focused on scoring and let `OnboardingRecipesService` do final balancing client-side.

## Fallback Behavior

If not enough recipes match the selected taxonomy filters:

1. include tag-only matches
2. include popular published recipes with images
3. include newest published recipes with images

The RPC should still return up to `p_limit` rows when possible.

## Example Calls

### Sarapan

```sql
select *
from get_onboarding_starter_recipes(
  p_meal_types => array['breakfast'],
  p_tags => array['sarapan', 'breakfast'],
  p_legacy_meal_types => array['breakfast'],
  p_limit => 8
);
```

### Raya

```sql
select *
from get_onboarding_starter_recipes(
  p_occasion => array['hari_raya', 'festive'],
  p_tags => array['raya', 'hari_raya', 'hari-raya', 'eid', 'festive'],
  p_limit => 8
);
```

### Simple Meals

```sql
select *
from get_onboarding_starter_recipes(
  p_difficulty_levels => array['easy']::recipe_difficulty[],
  p_max_cooking_time => 30,
  p_tags => array['simple', 'quick', 'easy'],
  p_limit => 8
);
```

## Client Integration

`OnboardingRecipesService` should:

- translate selected onboarding IDs using [cuisine-id-mapping.md](./cuisine-id-mapping.md)
- merge filter arrays across selected IDs
- call `get_onboarding_starter_recipes`
- request 8 candidates for screen 6
- apply any final client-side balancing if needed
- return card-ready recipe data to onboarding UI

## Open Implementation Questions

- Should strict dietary matching be needed during onboarding, or is overlap enough for starter recommendations?
- Should popularity use `save_count`, `view_count`, or a future `seed_popularity_score`?
- Should author data stay embedded as `jsonb`, matching `search_browsable_recipes`, or should the client fetch author details separately?
- Should fallback recipes be marked in `matched_fields` so analytics can distinguish exact matches from fallback recommendations?
