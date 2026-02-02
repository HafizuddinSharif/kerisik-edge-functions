# Recipe Collections Feature - Database Design

## Overview

This migration adds support for organizing recipes into collections. Collections can be organized by:
- **Author/Creator** - All recipes from a specific content creator
- **Cuisine Type** - Italian, Thai, Mexican, etc.
- **Dietary Preferences** - Vegan, Gluten-free, Keto, etc.
- **Meal Type** - Breakfast, Lunch, Dinner, Dessert, Snacks
- **Custom Collections** - User-created collections for any purpose

## New Tables

### 1. `collections`

Stores collection metadata and configuration.

```sql
CREATE TYPE collection_type AS ENUM (
  'author',
  'cuisine',
  'dietary',
  'meal_type',
  'custom'
);

CREATE TYPE collection_visibility AS ENUM (
  'public',
  'private',
  'unlisted'
);

CREATE TABLE collections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Collection metadata
  name text NOT NULL,
  description text,
  type collection_type NOT NULL,
  visibility collection_visibility NOT NULL DEFAULT 'public',
  
  -- Visual presentation
  cover_image_url text,
  icon text, -- emoji or icon identifier
  color_theme text, -- hex color for UI theming
  
  -- Ownership and attribution
  created_by_user_id uuid REFERENCES user_profile(id) ON DELETE SET NULL,
  author_id uuid REFERENCES authors(id) ON DELETE CASCADE,
  
  -- Stats and metadata
  recipe_count integer NOT NULL DEFAULT 0,
  view_count integer NOT NULL DEFAULT 0,
  
  -- SEO and discovery
  slug text UNIQUE, -- URL-friendly identifier
  tags text[], -- searchable tags
  
  -- Timestamps
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  
  -- Constraints
  CONSTRAINT valid_collection_ownership CHECK (
    (type = 'author' AND author_id IS NOT NULL) OR
    (type != 'author')
  ),
  CONSTRAINT valid_slug CHECK (slug ~ '^[a-z0-9-]+$')
);

-- Indexes for performance
CREATE INDEX idx_collections_type ON collections(type);
CREATE INDEX idx_collections_visibility ON collections(visibility);
CREATE INDEX idx_collections_created_by ON collections(created_by_user_id);
CREATE INDEX idx_collections_author_id ON collections(author_id);
CREATE INDEX idx_collections_slug ON collections(slug);
CREATE INDEX idx_collections_tags ON collections USING GIN(tags);
CREATE INDEX idx_collections_updated_at ON collections(updated_at DESC);
```

### 2. `collection_recipes`

Junction table linking recipes to collections (many-to-many relationship).

```sql
CREATE TABLE collection_recipes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  
  collection_id uuid NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
  recipe_id uuid NOT NULL REFERENCES browsable_recipes(id) ON DELETE CASCADE,
  
  -- Ordering and curation
  sort_order integer NOT NULL DEFAULT 0,
  added_by_user_id uuid REFERENCES user_profile(id) ON DELETE SET NULL,
  curator_note text, -- optional note about why this recipe is in the collection
  
  -- Featured/pinned status
  is_featured boolean NOT NULL DEFAULT false,
  
  -- Timestamps
  added_at timestamptz NOT NULL DEFAULT now(),
  
  -- Prevent duplicate recipes in same collection
  UNIQUE(collection_id, recipe_id)
);

-- Indexes for performance
CREATE INDEX idx_collection_recipes_collection ON collection_recipes(collection_id, sort_order);
CREATE INDEX idx_collection_recipes_recipe ON collection_recipes(recipe_id);
CREATE INDEX idx_collection_recipes_featured ON collection_recipes(collection_id, is_featured) WHERE is_featured = true;
```

## Database Functions

### 1. Update Recipe Count Trigger

Automatically maintains the `recipe_count` in collections.

```sql
CREATE OR REPLACE FUNCTION update_collection_recipe_count()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE collections 
    SET recipe_count = recipe_count + 1,
        updated_at = now()
    WHERE id = NEW.collection_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE collections 
    SET recipe_count = recipe_count - 1,
        updated_at = now()
    WHERE id = OLD.collection_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trigger_update_collection_recipe_count
  AFTER INSERT OR DELETE ON collection_recipes
  FOR EACH ROW
  EXECUTE FUNCTION update_collection_recipe_count();
```

### 2. Generate Collection Slug

Auto-generates URL-friendly slugs from collection names.

```sql
CREATE OR REPLACE FUNCTION generate_collection_slug()
RETURNS trigger AS $$
DECLARE
  base_slug text;
  final_slug text;
  counter integer := 0;
BEGIN
  -- Only generate if slug is not provided
  IF NEW.slug IS NULL THEN
    -- Create base slug from name
    base_slug := lower(regexp_replace(NEW.name, '[^a-z0-9]+', '-', 'g'));
    base_slug := trim(both '-' from base_slug);
    
    -- Ensure uniqueness
    final_slug := base_slug;
    WHILE EXISTS (SELECT 1 FROM collections WHERE slug = final_slug AND id != NEW.id) LOOP
      counter := counter + 1;
      final_slug := base_slug || '-' || counter;
    END LOOP;
    
    NEW.slug := final_slug;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_generate_collection_slug
  BEFORE INSERT OR UPDATE OF name ON collections
  FOR EACH ROW
  EXECUTE FUNCTION generate_collection_slug();
```

### 3. Get or Create Collection

Helper function to get or create a collection (useful for automatic collections).

```sql
CREATE OR REPLACE FUNCTION get_or_create_collection(
  p_type collection_type,
  p_name text,
  p_author_id uuid DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_tags text[] DEFAULT NULL
)
RETURNS uuid AS $$
DECLARE
  v_collection_id uuid;
BEGIN
  -- For author collections, check by author_id
  IF p_type = 'author' AND p_author_id IS NOT NULL THEN
    SELECT id INTO v_collection_id
    FROM collections
    WHERE type = 'author' AND author_id = p_author_id
    LIMIT 1;
    
    IF v_collection_id IS NOT NULL THEN
      RETURN v_collection_id;
    END IF;
  END IF;
  
  -- For other types, check by type and name
  IF p_type != 'author' THEN
    SELECT id INTO v_collection_id
    FROM collections
    WHERE type = p_type AND name = p_name
    LIMIT 1;
    
    IF v_collection_id IS NOT NULL THEN
      RETURN v_collection_id;
    END IF;
  END IF;
  
  -- Create new collection
  INSERT INTO collections (type, name, description, author_id, tags)
  VALUES (p_type, p_name, p_description, p_author_id, p_tags)
  RETURNING id INTO v_collection_id;
  
  RETURN v_collection_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 4. Add Recipe to Collection

Helper function to add a recipe to a collection with proper ordering.

```sql
CREATE OR REPLACE FUNCTION add_recipe_to_collection(
  p_collection_id uuid,
  p_recipe_id uuid,
  p_user_id uuid DEFAULT NULL,
  p_curator_note text DEFAULT NULL,
  p_is_featured boolean DEFAULT false
)
RETURNS uuid AS $$
DECLARE
  v_sort_order integer;
  v_cr_id uuid;
BEGIN
  -- Get next sort order
  SELECT COALESCE(MAX(sort_order), 0) + 1 INTO v_sort_order
  FROM collection_recipes
  WHERE collection_id = p_collection_id;
  
  -- Insert or update
  INSERT INTO collection_recipes (
    collection_id,
    recipe_id,
    sort_order,
    added_by_user_id,
    curator_note,
    is_featured
  )
  VALUES (
    p_collection_id,
    p_recipe_id,
    v_sort_order,
    p_user_id,
    p_curator_note,
    p_is_featured
  )
  ON CONFLICT (collection_id, recipe_id) DO UPDATE SET
    curator_note = COALESCE(EXCLUDED.curator_note, collection_recipes.curator_note),
    is_featured = EXCLUDED.is_featured,
    added_by_user_id = COALESCE(EXCLUDED.added_by_user_id, collection_recipes.added_by_user_id)
  RETURNING id INTO v_cr_id;
  
  RETURN v_cr_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### 5. Increment Collection View Count

```sql
CREATE OR REPLACE FUNCTION increment_collection_views(p_collection_id uuid)
RETURNS void AS $$
BEGIN
  UPDATE collections
  SET view_count = view_count + 1
  WHERE id = p_collection_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

## Row Level Security (RLS)

### collections

```sql
-- Enable RLS
ALTER TABLE collections ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can view public collections
CREATE POLICY select_public_collections ON collections
  FOR SELECT
  TO authenticated
  USING (visibility = 'public');

-- Policy: Users can view their own collections
CREATE POLICY select_own_collections ON collections
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profile
      WHERE user_profile.id = collections.created_by_user_id
      AND user_profile.auth_id = auth.uid()
    )
  );

-- Policy: Users can create collections
CREATE POLICY insert_collections ON collections
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profile
      WHERE user_profile.id = created_by_user_id
      AND user_profile.auth_id = auth.uid()
    )
  );

-- Policy: Users can update their own collections
CREATE POLICY update_own_collections ON collections
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profile
      WHERE user_profile.id = collections.created_by_user_id
      AND user_profile.auth_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profile
      WHERE user_profile.id = collections.created_by_user_id
      AND user_profile.auth_id = auth.uid()
    )
  );

-- Policy: Users can delete their own collections
CREATE POLICY delete_own_collections ON collections
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profile
      WHERE user_profile.id = collections.created_by_user_id
      AND user_profile.auth_id = auth.uid()
    )
  );
```

### collection_recipes

```sql
-- Enable RLS
ALTER TABLE collection_recipes ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can view recipes in public collections
CREATE POLICY select_public_collection_recipes ON collection_recipes
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM collections
      WHERE collections.id = collection_recipes.collection_id
      AND collections.visibility = 'public'
    )
  );

-- Policy: Users can view recipes in their own collections
CREATE POLICY select_own_collection_recipes ON collection_recipes
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM collections c
      JOIN user_profile up ON c.created_by_user_id = up.id
      WHERE c.id = collection_recipes.collection_id
      AND up.auth_id = auth.uid()
    )
  );

-- Policy: Users can add recipes to their own collections
CREATE POLICY insert_own_collection_recipes ON collection_recipes
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM collections c
      JOIN user_profile up ON c.created_by_user_id = up.id
      WHERE c.id = collection_id
      AND up.auth_id = auth.uid()
    )
  );

-- Policy: Users can update recipes in their own collections
CREATE POLICY update_own_collection_recipes ON collection_recipes
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM collections c
      JOIN user_profile up ON c.created_by_user_id = up.id
      WHERE c.id = collection_recipes.collection_id
      AND up.auth_id = auth.uid()
    )
  );

-- Policy: Users can delete recipes from their own collections
CREATE POLICY delete_own_collection_recipes ON collection_recipes
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM collections c
      JOIN user_profile up ON c.created_by_user_id = up.id
      WHERE c.id = collection_recipes.collection_id
      AND up.auth_id = auth.uid()
    )
  );
```

## Migration SQL

Complete migration file:

```sql
-- Migration: 20260202000000_create_recipe_collections

-- 1. Create custom types
CREATE TYPE collection_type AS ENUM (
  'author',
  'cuisine',
  'dietary',
  'meal_type',
  'custom'
);

CREATE TYPE collection_visibility AS ENUM (
  'public',
  'private',
  'unlisted'
);

-- 2. Create collections table
CREATE TABLE collections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  type collection_type NOT NULL,
  visibility collection_visibility NOT NULL DEFAULT 'public',
  cover_image_url text,
  icon text,
  color_theme text,
  created_by_user_id uuid REFERENCES user_profile(id) ON DELETE SET NULL,
  author_id uuid REFERENCES authors(id) ON DELETE CASCADE,
  recipe_count integer NOT NULL DEFAULT 0,
  view_count integer NOT NULL DEFAULT 0,
  slug text UNIQUE,
  tags text[],
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT valid_collection_ownership CHECK (
    (type = 'author' AND author_id IS NOT NULL) OR
    (type != 'author')
  ),
  CONSTRAINT valid_slug CHECK (slug ~ '^[a-z0-9-]+$')
);

CREATE INDEX idx_collections_type ON collections(type);
CREATE INDEX idx_collections_visibility ON collections(visibility);
CREATE INDEX idx_collections_created_by ON collections(created_by_user_id);
CREATE INDEX idx_collections_author_id ON collections(author_id);
CREATE INDEX idx_collections_slug ON collections(slug);
CREATE INDEX idx_collections_tags ON collections USING GIN(tags);
CREATE INDEX idx_collections_updated_at ON collections(updated_at DESC);

-- 3. Create collection_recipes junction table
CREATE TABLE collection_recipes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  collection_id uuid NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
  recipe_id uuid NOT NULL REFERENCES browsable_recipes(id) ON DELETE CASCADE,
  sort_order integer NOT NULL DEFAULT 0,
  added_by_user_id uuid REFERENCES user_profile(id) ON DELETE SET NULL,
  curator_note text,
  is_featured boolean NOT NULL DEFAULT false,
  added_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(collection_id, recipe_id)
);

CREATE INDEX idx_collection_recipes_collection ON collection_recipes(collection_id, sort_order);
CREATE INDEX idx_collection_recipes_recipe ON collection_recipes(recipe_id);
CREATE INDEX idx_collection_recipes_featured ON collection_recipes(collection_id, is_featured) WHERE is_featured = true;

-- 4. Create functions and triggers
CREATE OR REPLACE FUNCTION update_collection_recipe_count()
RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE collections 
    SET recipe_count = recipe_count + 1,
        updated_at = now()
    WHERE id = NEW.collection_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE collections 
    SET recipe_count = recipe_count - 1,
        updated_at = now()
    WHERE id = OLD.collection_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trigger_update_collection_recipe_count
  AFTER INSERT OR DELETE ON collection_recipes
  FOR EACH ROW
  EXECUTE FUNCTION update_collection_recipe_count();

CREATE OR REPLACE FUNCTION generate_collection_slug()
RETURNS trigger AS $$
DECLARE
  base_slug text;
  final_slug text;
  counter integer := 0;
BEGIN
  IF NEW.slug IS NULL THEN
    base_slug := lower(regexp_replace(NEW.name, '[^a-z0-9]+', '-', 'g'));
    base_slug := trim(both '-' from base_slug);
    final_slug := base_slug;
    
    WHILE EXISTS (SELECT 1 FROM collections WHERE slug = final_slug AND id != NEW.id) LOOP
      counter := counter + 1;
      final_slug := base_slug || '-' || counter;
    END LOOP;
    
    NEW.slug := final_slug;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_generate_collection_slug
  BEFORE INSERT OR UPDATE OF name ON collections
  FOR EACH ROW
  EXECUTE FUNCTION generate_collection_slug();

CREATE OR REPLACE FUNCTION get_or_create_collection(
  p_type collection_type,
  p_name text,
  p_author_id uuid DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_tags text[] DEFAULT NULL
)
RETURNS uuid AS $$
DECLARE
  v_collection_id uuid;
BEGIN
  IF p_type = 'author' AND p_author_id IS NOT NULL THEN
    SELECT id INTO v_collection_id
    FROM collections
    WHERE type = 'author' AND author_id = p_author_id
    LIMIT 1;
    
    IF v_collection_id IS NOT NULL THEN
      RETURN v_collection_id;
    END IF;
  END IF;
  
  IF p_type != 'author' THEN
    SELECT id INTO v_collection_id
    FROM collections
    WHERE type = p_type AND name = p_name
    LIMIT 1;
    
    IF v_collection_id IS NOT NULL THEN
      RETURN v_collection_id;
    END IF;
  END IF;
  
  INSERT INTO collections (type, name, description, author_id, tags)
  VALUES (p_type, p_name, p_description, p_author_id, p_tags)
  RETURNING id INTO v_collection_id;
  
  RETURN v_collection_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION add_recipe_to_collection(
  p_collection_id uuid,
  p_recipe_id uuid,
  p_user_id uuid DEFAULT NULL,
  p_curator_note text DEFAULT NULL,
  p_is_featured boolean DEFAULT false
)
RETURNS uuid AS $$
DECLARE
  v_sort_order integer;
  v_cr_id uuid;
BEGIN
  SELECT COALESCE(MAX(sort_order), 0) + 1 INTO v_sort_order
  FROM collection_recipes
  WHERE collection_id = p_collection_id;
  
  INSERT INTO collection_recipes (
    collection_id,
    recipe_id,
    sort_order,
    added_by_user_id,
    curator_note,
    is_featured
  )
  VALUES (
    p_collection_id,
    p_recipe_id,
    v_sort_order,
    p_user_id,
    p_curator_note,
    p_is_featured
  )
  ON CONFLICT (collection_id, recipe_id) DO UPDATE SET
    curator_note = COALESCE(EXCLUDED.curator_note, collection_recipes.curator_note),
    is_featured = EXCLUDED.is_featured,
    added_by_user_id = COALESCE(EXCLUDED.added_by_user_id, collection_recipes.added_by_user_id)
  RETURNING id INTO v_cr_id;
  
  RETURN v_cr_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION increment_collection_views(p_collection_id uuid)
RETURNS void AS $$
BEGIN
  UPDATE collections
  SET view_count = view_count + 1
  WHERE id = p_collection_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Enable RLS on all tables
ALTER TABLE collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE collection_recipes ENABLE ROW LEVEL SECURITY;

-- 6. Create RLS policies for collections
CREATE POLICY select_public_collections ON collections
  FOR SELECT TO authenticated
  USING (visibility = 'public');

CREATE POLICY select_own_collections ON collections
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profile
      WHERE user_profile.id = collections.created_by_user_id
      AND user_profile.auth_id = auth.uid()
    )
  );

CREATE POLICY insert_collections ON collections
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profile
      WHERE user_profile.id = created_by_user_id
      AND user_profile.auth_id = auth.uid()
    )
  );

CREATE POLICY update_own_collections ON collections
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profile
      WHERE user_profile.id = collections.created_by_user_id
      AND user_profile.auth_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profile
      WHERE user_profile.id = collections.created_by_user_id
      AND user_profile.auth_id = auth.uid()
    )
  );

CREATE POLICY delete_own_collections ON collections
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profile
      WHERE user_profile.id = collections.created_by_user_id
      AND user_profile.auth_id = auth.uid()
    )
  );

-- 7. Create RLS policies for collection_recipes
CREATE POLICY select_public_collection_recipes ON collection_recipes
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM collections
      WHERE collections.id = collection_recipes.collection_id
      AND collections.visibility = 'public'
    )
  );

CREATE POLICY select_own_collection_recipes ON collection_recipes
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM collections c
      JOIN user_profile up ON c.created_by_user_id = up.id
      WHERE c.id = collection_recipes.collection_id
      AND up.auth_id = auth.uid()
    )
  );

CREATE POLICY insert_own_collection_recipes ON collection_recipes
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM collections c
      JOIN user_profile up ON c.created_by_user_id = up.id
      WHERE c.id = collection_id
      AND up.auth_id = auth.uid()
    )
  );

CREATE POLICY update_own_collection_recipes ON collection_recipes
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM collections c
      JOIN user_profile up ON c.created_by_user_id = up.id
      WHERE c.id = collection_recipes.collection_id
      AND up.auth_id = auth.uid()
    )
  );

CREATE POLICY delete_own_collection_recipes ON collection_recipes
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM collections c
      JOIN user_profile up ON c.created_by_user_id = up.id
      WHERE c.id = collection_recipes.collection_id
      AND up.auth_id = auth.uid()
    )
  );
```

## Usage Examples

### 1. Create an Author Collection

```sql
-- Automatically creates collection for an author
SELECT get_or_create_collection(
  'author',
  'Gordon Ramsay',
  'author-uuid-here',
  'Professional chef and restaurateur',
  ARRAY['celebrity-chef', 'british', 'michelin-star']
);
```

### 2. Create a Cuisine Collection

```sql
-- Create Italian cuisine collection
SELECT get_or_create_collection(
  'cuisine',
  'Italian',
  NULL,
  'Traditional and modern Italian recipes',
  ARRAY['italian', 'pasta', 'pizza', 'mediterranean']
);
```

### 3. Add Recipe to Collection

```sql
-- Add a recipe to a collection
SELECT add_recipe_to_collection(
  'collection-uuid',
  'recipe-uuid',
  'user-profile-uuid',
  'Classic carbonara recipe - highly recommended!',
  true  -- is_featured
);
```

### 4. Query Recipes in a Collection

```sql
-- Get all recipes in a collection with details
SELECT 
  br.id,
  br.title,
  br.description,
  br.thumbnail_url,
  cr.sort_order,
  cr.curator_note,
  cr.is_featured,
  a.name as author_name
FROM collection_recipes cr
JOIN browsable_recipes br ON cr.recipe_id = br.id
LEFT JOIN authors a ON br.author_id = a.id
WHERE cr.collection_id = 'collection-uuid'
ORDER BY cr.sort_order;
```

### 5. Get All Collections by Type

```sql
-- Get all public cuisine collections
SELECT c.*
FROM collections c
WHERE c.type = 'cuisine' AND c.visibility = 'public'
ORDER BY c.recipe_count DESC;
```

### 6. Get User's Collections

```sql
-- Get collections created by current user
SELECT c.*
FROM collections c
JOIN user_profile up ON c.created_by_user_id = up.id
WHERE up.auth_id = auth.uid()
ORDER BY c.updated_at DESC;
```

## Key Features

1. **Flexible Collection Types**: Support for author, cuisine, dietary, meal type, and custom collections
2. **Many-to-Many Relationships**: Recipes can belong to multiple collections
3. **Ordering & Curation**: Sort order and featured status for recipes within collections
4. **SEO-Friendly**: Auto-generated slugs for clean URLs
5. **View Tracking**: Track collection popularity with view counts
6. **Privacy Controls**: Public, private, and unlisted collections
7. **Automatic Maintenance**: Triggers keep recipe counts accurate
8. **Full RLS**: Comprehensive security policies for all operations

## Future Enhancements

Consider these additional features:

1. **Collection Collaborators**: Allow multiple users to manage a collection
2. **Collection Templates**: Pre-made collection structures users can clone
3. **Smart Collections**: Auto-populated based on criteria (e.g., all vegan recipes)
4. **Collection Sharing**: Generate shareable links for collections
5. **Collection Analytics**: Track which recipes are most viewed within collections
6. **Nested Collections**: Collections that contain other collections
7. **Collection Ratings**: Allow users to rate collections