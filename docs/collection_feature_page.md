# Recipe Collections Feature Page Design

## Overview
This document outlines the design for a feature page showcasing recipe collections, including UI layout options, API requirements, and necessary schema updates.

---

## UI Layout Options

### Option 1: Hero + Category Grid
- **Hero Section**: Feature 1-2 "Editor's Pick" collections with large cover images
- **Category Sections**: Organize collections by type (Authors, Cuisines, Dietary, Meal Types)
- **Each collection card shows**: Cover image, name, recipe count, view count, brief description
- **Benefits**: Clear navigation, easy to browse by interest

### Option 2: Pinterest-style Masonry Grid
- **Mixed-size cards** in a masonry layout
- **Featured collections** get larger cards
- **Infinite scroll** or pagination
- **Benefits**: Visually dynamic, fits many collections on screen

### Option 3: Carousel + Sections
- **Top carousel**: Rotating featured collections
- **Below**: Categorized horizontal scrolling rows (like Netflix)
- **Benefits**: Showcases variety, good for mobile

### Option 4: Tabbed Interface
- **Tabs for each collection type** (All, Authors, Cuisines, Dietary, etc.)
- **Grid of collections** within each tab
- **Benefits**: Clean organization, reduces scroll

---

## Recommended API Endpoints

### 1. Get Featured Collections (NEW)
**Endpoint**: `GET /api/collections/featured`

**Query Parameters**:
- `limit` (optional, default: 5): Number of featured collections to return

**Response**:
```json
{
  "collections": [
    {
      "id": "uuid",
      "name": "string",
      "description": "string",
      "type": "cuisine|author|dietary|meal_type|custom",
      "visibility": "public|private|unlisted",
      "cover_image_url": "string",
      "icon": "string",
      "color_theme": "string",
      "recipe_count": "number",
      "view_count": "number",
      "slug": "string",
      "tags": ["string"],
      "is_featured": true,
      "featured_order": "number"
    }
  ]
}
```

### 2. Get Collections by Type
**Endpoint**: `GET /api/collections?type={type}&limit={n}&offset={n}`

**Query Parameters**:
- `type` (optional): Filter by collection_type (author, cuisine, dietary, meal_type, custom)
- `limit` (optional, default: 20): Number of collections to return
- `offset` (optional, default: 0): Pagination offset
- `sort` (optional, default: 'popular'): Sort order (popular, recent, alphabetical)

**Response**:
```json
{
  "collections": [...],
  "total": "number",
  "limit": "number",
  "offset": "number"
}
```

### 3. Get Popular Collections
**Endpoint**: `GET /api/collections/popular?limit={n}`

**Query Parameters**:
- `limit` (optional, default: 10): Number of popular collections to return

**Response**: Same as featured collections

### 4. Get Recent Collections
**Endpoint**: `GET /api/collections/recent?limit={n}`

**Query Parameters**:
- `limit` (optional, default: 10): Number of recent collections to return

**Response**: Same as featured collections

### 5. Get Collection Stats
**Endpoint**: `GET /api/collections/stats`

**Response**:
```json
{
  "total_collections": "number",
  "total_recipes": "number",
  "by_type": {
    "author": "number",
    "cuisine": "number",
    "dietary": "number",
    "meal_type": "number",
    "custom": "number"
  }
}
```

---

## Schema Updates Required

### 1. Add Featured Flag to Collections

```sql
-- Add featured columns to collections table
ALTER TABLE collections 
ADD COLUMN is_featured BOOLEAN DEFAULT false,
ADD COLUMN featured_order INTEGER,
ADD COLUMN featured_at TIMESTAMPTZ;

-- Add index for performance
CREATE INDEX idx_collections_featured 
ON collections(is_featured, featured_order) 
WHERE is_featured = true;

-- Add comment
COMMENT ON COLUMN collections.is_featured IS 'Whether this collection is featured on the main page';
COMMENT ON COLUMN collections.featured_order IS 'Sort order for featured collections (lower = higher priority)';
COMMENT ON COLUMN collections.featured_at IS 'When this collection was marked as featured';
```

### 2. Add New Function for Featured Collections

```sql
CREATE OR REPLACE FUNCTION get_featured_collections(p_limit INTEGER DEFAULT 5)
RETURNS SETOF collections
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT *
  FROM collections
  WHERE visibility = 'public' AND is_featured = true
  ORDER BY featured_order ASC NULLS LAST, view_count DESC
  LIMIT p_limit;
$$;

COMMENT ON FUNCTION get_featured_collections IS 'Returns featured collections ordered by featured_order, then by popularity';
```

### 3. Add Function to Set Featured Collection

```sql
CREATE OR REPLACE FUNCTION set_collection_featured(
  p_collection_id UUID,
  p_is_featured BOOLEAN,
  p_featured_order INTEGER DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE collections
  SET 
    is_featured = p_is_featured,
    featured_order = p_featured_order,
    featured_at = CASE 
      WHEN p_is_featured = true AND is_featured = false THEN now()
      WHEN p_is_featured = false THEN NULL
      ELSE featured_at
    END,
    updated_at = now()
  WHERE id = p_collection_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Collection with id % not found', p_collection_id;
  END IF;
END;
$$;

COMMENT ON FUNCTION set_collection_featured IS 'Mark a collection as featured or unfeatured with optional order';
```

### 4. Optional: Add Collection Metrics Table (For Tracking Trends)

```sql
-- Create table for tracking collection metrics over time
CREATE TABLE collection_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  views INTEGER DEFAULT 0,
  recipe_additions INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(collection_id, date)
);

-- Add index for querying by collection and date range
CREATE INDEX idx_collection_metrics_collection_date 
ON collection_metrics(collection_id, date DESC);

COMMENT ON TABLE collection_metrics IS 'Daily metrics for tracking collection performance over time';
```

---

## Sample Queries

### Get All Data for Feature Page (Single Query)

```sql
-- Get all data needed for feature page in one query
WITH featured AS (
  SELECT * FROM collections
  WHERE is_featured = true AND visibility = 'public'
  ORDER BY featured_order ASC NULLS LAST
  LIMIT 3
),
popular_authors AS (
  SELECT * FROM collections
  WHERE type = 'author' AND visibility = 'public'
  ORDER BY view_count DESC
  LIMIT 6
),
popular_cuisines AS (
  SELECT * FROM collections
  WHERE type = 'cuisine' AND visibility = 'public'
  ORDER BY view_count DESC
  LIMIT 8
),
popular_dietary AS (
  SELECT * FROM collections
  WHERE type = 'dietary' AND visibility = 'public'
  ORDER BY view_count DESC
  LIMIT 6
),
trending AS (
  SELECT * FROM collections
  WHERE visibility = 'public'
  ORDER BY updated_at DESC
  LIMIT 10
)
SELECT 
  json_build_object(
    'featured', (SELECT json_agg(featured.*) FROM featured),
    'popular_authors', (SELECT json_agg(popular_authors.*) FROM popular_authors),
    'popular_cuisines', (SELECT json_agg(popular_cuisines.*) FROM popular_cuisines),
    'popular_dietary', (SELECT json_agg(popular_dietary.*) FROM popular_dietary),
    'trending', (SELECT json_agg(trending.*) FROM trending)
  ) as page_data;
```

### Get Collections with Recipe Preview

```sql
-- Get collections with a preview of their top recipes
SELECT 
  c.*,
  COALESCE(
    json_agg(
      json_build_object(
        'recipe_id', br.id,
        'title', br.title,
        'thumbnail_url', br.thumbnail_url,
        'author_name', a.name
      ) ORDER BY cr.is_featured DESC, cr.sort_order ASC
    ) FILTER (WHERE br.id IS NOT NULL),
    '[]'
  ) as preview_recipes
FROM collections c
LEFT JOIN collection_recipes cr ON c.id = cr.collection_id
LEFT JOIN browsable_recipes br ON cr.recipe_id = br.id
LEFT JOIN authors a ON br.author_id = a.id
WHERE c.visibility = 'public'
  AND c.type = 'cuisine'
GROUP BY c.id
ORDER BY c.view_count DESC
LIMIT 8;
```

---

## UI Components Needed

### 1. CollectionCard
**Props**:
- `collection`: Collection object
- `variant`: 'small' | 'medium' | 'large' | 'hero'
- `showStats`: boolean (whether to show view count, recipe count)

**Displays**:
- Cover image (with fallback gradient based on color_theme)
- Icon (emoji or icon identifier)
- Name
- Description (truncated for smaller variants)
- Recipe count
- View count (optional)
- Tags (optional)

### 2. FeaturedCollectionHero
**Props**:
- `collection`: Featured collection object
- `onCTAClick`: Callback function

**Displays**:
- Large cover image background
- Full description
- Prominent CTA button ("Explore Collection")
- Recipe count and view count badges

### 3. CategorySection
**Props**:
- `title`: Section title (e.g., "Popular Authors")
- `collections`: Array of collections
- `layout`: 'horizontal-scroll' | 'grid'
- `viewAllLink`: URL to view all collections in this category

**Displays**:
- Section header with title
- Horizontal scrolling row or grid of CollectionCards
- "View All" link

### 4. SearchBar
**Props**:
- `onSearch`: Callback function
- `placeholder`: Search placeholder text

**Features**:
- Search input
- Filter by collection type (dropdown or pills)
- Sort options (popular, recent, alphabetical)

### 5. FilterTabs
**Props**:
- `activeTab`: Current active tab
- `onTabChange`: Callback function
- `counts`: Object with counts for each tab

**Tabs**:
- All Collections
- Authors
- Cuisines
- Dietary
- Meal Types
- Custom

---

## Suggested Page Structure

```
┌─────────────────────────────────────────────────────────┐
│  🌟 Featured Collection Hero                            │
│  (Large cover image, description, recipe count, CTA)    │
│  - Auto-rotates every 5 seconds if multiple featured    │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  📊 Quick Stats                                          │
│  [Total Collections] [Total Recipes] [Categories]       │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  👨‍🍳 Popular Authors                      [View All →]   │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐            │
│  │Card│ │Card│ │Card│ │Card│ │Card│ │Card│            │
│  └────┘ └────┘ └────┘ └────┘ └────┘ └────┘            │
│  ← Horizontal scroll →                                  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  🍝 Browse by Cuisine                   [View All →]    │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐            │
│  │Card│ │Card│ │Card│ │Card│ │Card│ │Card│            │
│  └────┘ └────┘ └────┘ └────┘ └────┘ └────┘            │
│  ← Horizontal scroll →                                  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  🥗 Dietary Preferences                 [View All →]    │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐            │
│  │Card│ │Card│ │Card│ │Card│ │Card│ │Card│            │
│  └────┘ └────┘ └────┘ └────┘ └────┘ └────┘            │
│  ← Horizontal scroll →                                  │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  🔥 Trending Collections                                │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐                           │
│  │Card│ │Card│ │Card│ │Card│                           │
│  └────┘ └────┘ └────┘ └────┘                           │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐                           │
│  │Card│ │Card│ │Card│ │Card│                           │
│  └────┘ └────┘ └────┘ └────┘                           │
│                              [Load More]                │
└─────────────────────────────────────────────────────────┘
```

---

## Mobile Considerations

### Responsive Breakpoints
- **Mobile (< 640px)**: 
  - Single column layout
  - Full-width hero
  - Horizontal scroll for category sections (2-3 cards visible)
  
- **Tablet (640px - 1024px)**:
  - 2-column grid where applicable
  - Horizontal scroll shows 3-4 cards
  
- **Desktop (> 1024px)**:
  - Full layout as shown above
  - Grid sections show 4-6 cards

### Touch Interactions
- Swipe gestures for horizontal scrolling sections
- Tap to expand collection cards for more details
- Pull-to-refresh to reload featured collections

---

## Performance Considerations

### Caching Strategy
- Cache featured collections for 1 hour
- Cache popular collections for 30 minutes
- Cache stats for 1 hour
- Invalidate cache when collections are updated

### Lazy Loading
- Load hero section first
- Lazy load category sections as user scrolls
- Use skeleton loaders for better UX

### Image Optimization
- Use responsive images with srcset
- Lazy load images below the fold
- Provide fallback gradients based on color_theme when cover_image_url is null

---

## Analytics to Track

### Collection Engagement
- Views per collection
- Click-through rate from feature page to collection detail
- Time spent viewing collections
- Recipe clicks from collection previews

### User Behavior
- Most popular collection types
- Search query patterns
- Navigation patterns (which sections get most engagement)
- Conversion from browse to recipe view

### A/B Testing Ideas
- Hero carousel vs static featured collection
- Grid layout vs horizontal scroll for categories
- Number of collections to show per section
- Card size and information density

---

## Migration Checklist

- [ ] Run schema migration to add featured columns
- [ ] Create `get_featured_collections()` function
- [ ] Create `set_collection_featured()` function
- [ ] (Optional) Create `collection_metrics` table
- [ ] Update RLS policies if needed
- [ ] Build API endpoints
- [ ] Create UI components
- [ ] Implement caching layer
- [ ] Add analytics tracking
- [ ] Test responsive design
- [ ] Mark initial collections as featured
- [ ] Deploy and monitor

---

## Future Enhancements

1. **Personalized Recommendations**: Use user's saved recipes to suggest relevant collections
2. **Seasonal Collections**: Auto-feature collections based on seasons/holidays
3. **User-Generated Featured**: Allow users to submit collections for featuring
4. **Collection of the Week**: Automated rotation of featured collection
5. **Share Collections**: Social sharing functionality
6. **Collection Following**: Allow users to follow/subscribe to collections
7. **Collaborative Collections**: Allow multiple users to contribute to custom collections
8. **Collection Themes**: Pre-designed visual themes for different collection types