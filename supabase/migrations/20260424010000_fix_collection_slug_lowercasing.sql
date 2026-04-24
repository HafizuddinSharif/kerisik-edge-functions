-- Fix collection slug generation so uppercase letters are normalized to lowercase
-- instead of being stripped as non-matching characters.

CREATE OR REPLACE FUNCTION generate_collection_slug()
RETURNS TRIGGER AS $$
DECLARE
    base_slug TEXT;
    candidate_slug TEXT;
    counter INTEGER := 1;
BEGIN
    IF NEW.slug IS NOT NULL THEN
        RETURN NEW;
    END IF;

    base_slug := regexp_replace(lower(coalesce(NEW.name, '')), '[^a-z0-9]+', '-', 'g');
    base_slug := trim(both '-' from base_slug);

    IF base_slug = '' THEN
        base_slug := 'collection';
    END IF;

    candidate_slug := base_slug;

    WHILE EXISTS (
        SELECT 1
        FROM collections
        WHERE slug = candidate_slug
          AND id IS DISTINCT FROM NEW.id
    ) LOOP
        candidate_slug := base_slug || '-' || counter;
        counter := counter + 1;
    END LOOP;

    NEW.slug := candidate_slug;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

