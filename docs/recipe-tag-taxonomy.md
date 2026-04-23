# Recipe Tags Taxonomy

## Overview

Tags are stored as **separate `text[]` columns per category** in Postgres, each with a GIN index for optimal query performance.

The current table is `browsable_recipes`. Some tag columns already exist; the migration below adds the missing ones.

---

## Current Schema (`browsable_recipes`)

### Existing tag-related columns

| Column             | Type      | Notes                                         |
| ------------------ | --------- | --------------------------------------------- |
| `cuisine_type`     | `text`    | ✅ Single value, fine as-is                   |
| `meal_type`        | `text`    | ⚠️ Single value — needs migration to `text[]` |
| `dietary_tags`     | `text[]`  | ✅ Already array with GIN index               |
| `difficulty_level` | `enum`    | ✅ `easy`, `medium`, `hard`                   |
| `tags`             | `text[]`  | ✅ Freeform/AI-generated tags                 |
| `cooking_time`     | `integer` | ⚠️ Raw minutes — no bucketed tag yet          |

### Missing columns

| Column            | Type     | Status                                   |
| ----------------- | -------- | ---------------------------------------- |
| `meal_types`      | `text[]` | ❌ Missing (replacement for `meal_type`) |
| `course`          | `text[]` | ❌ Missing                               |
| `main_ingredient` | `text[]` | ❌ Missing                               |
| `cooking_method`  | `text[]` | ❌ Missing                               |
| `flavor`          | `text[]` | ❌ Missing                               |
| `occasion`        | `text[]` | ❌ Missing                               |
| `texture`         | `text[]` | ❌ Missing                               |

---

## Migration

```sql
-- Add missing tag columns
ALTER TABLE browsable_recipes
  ADD COLUMN meal_types      text[] DEFAULT '{}',
  ADD COLUMN course          text[] DEFAULT '{}',
  ADD COLUMN main_ingredient text[] DEFAULT '{}',
  ADD COLUMN cooking_method  text[] DEFAULT '{}',
  ADD COLUMN flavor          text[] DEFAULT '{}',
  ADD COLUMN occasion        text[] DEFAULT '{}',
  ADD COLUMN texture         text[] DEFAULT '{}';

-- GIN indexes for new columns
CREATE INDEX idx_browsable_recipes_meal_types      ON browsable_recipes USING GIN (meal_types);
CREATE INDEX idx_browsable_recipes_course          ON browsable_recipes USING GIN (course);
CREATE INDEX idx_browsable_recipes_main_ingredient ON browsable_recipes USING GIN (main_ingredient);
CREATE INDEX idx_browsable_recipes_cooking_method  ON browsable_recipes USING GIN (cooking_method);
CREATE INDEX idx_browsable_recipes_flavor          ON browsable_recipes USING GIN (flavor);
CREATE INDEX idx_browsable_recipes_occasion        ON browsable_recipes USING GIN (occasion);
CREATE INDEX idx_browsable_recipes_texture         ON browsable_recipes USING GIN (texture);
```

> `meal_type` (single `text`) is kept for backward compatibility. Use `meal_types` (`text[]`) going forward.

---

## Example Row

```json
{
  "meal_name": "Nasi Lemak",
  "cuisine_type": "malay",
  "meal_types": ["breakfast", "lunch"],
  "course": ["main"],
  "main_ingredient": ["rice", "egg", "fish"],
  "dietary_tags": ["halal"],
  "cooking_method": ["steamed", "fried"],
  "flavor": ["spicy", "savory"],
  "occasion": ["everyday", "hari_raya"],
  "cooking_time": 45,
  "difficulty_level": "medium",
  "texture": ["dry", "crispy"]
}
```

## Example Query

```sql
-- Find halal breakfast recipes that are spicy
SELECT * FROM browsable_recipes
WHERE meal_types @> ARRAY['breakfast']
  AND dietary_tags @> ARRAY['halal']
  AND flavor @> ARRAY['spicy']
  AND visibility_status = 'published';
```

---

## Tag Categories & Allowed Values

### 1. Meal Type (`meal_types`)

| Value       | Description              |
| ----------- | ------------------------ |
| `breakfast` | Morning meal             |
| `lunch`     | Midday meal              |
| `dinner`    | Evening meal             |
| `supper`    | Late night meal          |
| `snack`     | Light bite between meals |
| `dessert`   | Sweet end-of-meal dish   |
| `beverage`  | Drinks                   |

---

### 2. Course (`course`)

| Value       | Description              |
| ----------- | ------------------------ |
| `appetizer` | Starter before main      |
| `soup`      | Broth or soup dishes     |
| `main`      | Primary dish             |
| `side`      | Accompaniment to main    |
| `condiment` | Sauces, sambals, pickles |
| `salad`     | Fresh or blanched salad  |

---

### 3. Main Ingredient (`main_ingredient`)

| Value        | Description                |
| ------------ | -------------------------- |
| `chicken`    | Poultry                    |
| `beef`       | Beef cuts                  |
| `lamb`       | Lamb/mutton                |
| `pork`       | Pork cuts                  |
| `seafood`    | General seafood            |
| `fish`       | Fish specifically          |
| `shrimp`     | Prawns/shrimp              |
| `egg`        | Egg-based dishes           |
| `tofu`       | Bean curd                  |
| `tempeh`     | Fermented soybean cake     |
| `vegetables` | Plant-based                |
| `rice`       | Rice as primary ingredient |
| `noodles`    | Noodle-based dishes        |
| `bread`      | Bread/dough-based          |

---

### 4. Dietary (`dietary_tags`)

| Value         | Description                      |
| ------------- | -------------------------------- |
| `halal`       | Permissible under Islamic law    |
| `vegetarian`  | No meat/seafood                  |
| `vegan`       | No animal products               |
| `gluten_free` | No gluten-containing ingredients |
| `dairy_free`  | No dairy products                |
| `nut_free`    | No nuts                          |
| `low_carb`    | Reduced carbohydrate             |
| `keto`        | Ketogenic diet compatible        |

---

### 5. Cooking Method (`cooking_method`)

| Value         | Description               |
| ------------- | ------------------------- |
| `grilled`     | Direct heat grilling      |
| `fried`       | Pan or shallow frying     |
| `deep_fried`  | Submerged in hot oil      |
| `steamed`     | Cooked via steam          |
| `baked`       | Oven baked                |
| `stir_fried`  | High-heat wok cooking     |
| `braised`     | Slow-cooked in liquid     |
| `raw`         | No cooking required       |
| `slow_cooked` | Extended low-heat cooking |
| `boiled`      | Cooked in boiling liquid  |
| `roasted`     | Dry oven heat             |
| `smoked`      | Smoke-infused cooking     |

---

### 6. Flavor Profile (`flavor`)

| Value    | Description          |
| -------- | -------------------- |
| `spicy`  | Chilli heat          |
| `sweet`  | Sugary notes         |
| `savory` | Umami/salty base     |
| `sour`   | Acidic/tangy         |
| `mild`   | Low intensity flavor |
| `rich`   | Heavy, indulgent     |
| `umami`  | Deep savory flavor   |
| `bitter` | Bitter notes         |

---

### 7. Occasion (`occasion`)

| Value              | Description                |
| ------------------ | -------------------------- |
| `everyday`         | Regular daily meal         |
| `festive`          | General celebration        |
| `street_food`      | Hawker or roadside dish    |
| `comfort_food`     | Nostalgic or soothing dish |
| `party`            | Social gatherings          |
| `ramadan`          | Ramadan/iftar specific     |
| `hari_raya`        | Eid celebration dishes     |
| `chinese_new_year` | CNY specific dishes        |

---

### 8. Cook Time (`cook_time`)

| Value          | Description               |
| -------------- | ------------------------- |
| `under_30_min` | Ready in under 30 minutes |
| `30_to_60_min` | 30 minutes to 1 hour      |
| `1_to_3_hrs`   | 1 to 3 hours              |
| `over_3_hrs`   | More than 3 hours         |

---

### 9. Difficulty (`difficulty_level` — enum)

| Value    | Description                    |
| -------- | ------------------------------ |
| `easy`   | Beginner friendly              |
| `medium` | Some cooking experience needed |
| `hard`   | Advanced techniques required   |

---

### 10. Texture / Form (`texture`)

| Value     | Description          |
| --------- | -------------------- |
| `crispy`  | Crunchy exterior     |
| `soupy`   | Broth-heavy dish     |
| `dry`     | No sauce or gravy    |
| `gravy`   | Thick sauce-based    |
| `creamy`  | Smooth, rich texture |
| `crunchy` | Firm bite throughout |

---

## Cuisine Type (`cuisine_type`)

Stored as a single `text` field (not an array) since a dish typically belongs to one primary cuisine.

| Value           | Region                         |
| --------------- | ------------------------------ |
| `malay`         | Southeast Asia                 |
| `chinese`       | East Asia                      |
| `indian`        | South Asia                     |
| `western`       | Europe/North America (general) |
| `arabic`        | Middle East                    |
| `japanese`      | East Asia                      |
| `korean`        | East Asia                      |
| `indonesian`    | Southeast Asia                 |
| `thai`          | Southeast Asia                 |
| `italian`       | Europe                         |
| `vietnamese`    | Southeast Asia                 |
| `filipino`      | Southeast Asia                 |
| `singaporean`   | Southeast Asia                 |
| `burmese`       | Southeast Asia                 |
| `taiwanese`     | East Asia                      |
| `hong_kong`     | East Asia                      |
| `pakistani`     | South Asia                     |
| `bangladeshi`   | South Asia                     |
| `sri_lankan`    | South Asia                     |
| `french`        | Europe                         |
| `spanish`       | Europe                         |
| `greek`         | Europe                         |
| `mexican`       | Latin America                  |
| `american`      | North America                  |
| `brazilian`     | Latin America                  |
| `peruvian`      | Latin America                  |
| `moroccan`      | Africa                         |
| `ethiopian`     | Africa                         |
| `west_african`  | Africa                         |
| `turkish`       | Central Asia / Europe          |
| `persian`       | Central Asia                   |
| `mediterranean` | Mediterranean region           |
| `peranakan`     | Malaysian/Straits Chinese      |
| `mamak`         | Malaysian Indian Muslim        |
| `fusion`        | Mixed cuisines                 |
| `other`         | Uncategorized                  |

---

## Performance Notes

| Rows       | Performance impact                                     |
| ---------- | ------------------------------------------------------ |
| 10,000     | No noticeable difference between approaches            |
| 100,000    | GIN indexes start to matter                            |
| 1,000,000+ | Separate columns with GIN indexes significantly faster |

> At current scale, all approaches feel instant. Add GIN indexes early as a good habit — the cost is negligible and the payoff comes as data grows.
