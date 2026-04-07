-- Migration: 20260405000000_denormalize_imported_content_ingredients
-- Description: Denormalize imported_content.content->ingredients into relational child tables.

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS public.imported_content_ingredients (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    imported_content_id uuid NOT NULL,
    group_name text NOT NULL,
    sort_order integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT fk_imported_content_ingredients_imported_content
        FOREIGN KEY (imported_content_id)
        REFERENCES public.imported_content(id)
        ON DELETE CASCADE,
    CONSTRAINT unique_imported_content_ingredient_group_sort
        UNIQUE (imported_content_id, sort_order)
);

CREATE INDEX IF NOT EXISTS idx_imported_content_ingredients_parent_sort
    ON public.imported_content_ingredients (imported_content_id, sort_order);

DROP TRIGGER IF EXISTS set_imported_content_ingredients_updated_at ON public.imported_content_ingredients;
CREATE TRIGGER set_imported_content_ingredients_updated_at
    BEFORE UPDATE ON public.imported_content_ingredients
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.imported_content_ingredients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view imported content ingredients" ON public.imported_content_ingredients;
CREATE POLICY "Users can view imported content ingredients"
ON public.imported_content_ingredients
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.imported_content ic
    WHERE ic.id = imported_content_id
  )
);

DROP POLICY IF EXISTS "Users can insert imported content ingredients" ON public.imported_content_ingredients;
CREATE POLICY "Users can insert imported content ingredients"
ON public.imported_content_ingredients
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.imported_content ic
    JOIN public.user_profile up ON up.id = ic.user_id
    WHERE ic.id = imported_content_id
      AND up.auth_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Users can update imported content ingredients" ON public.imported_content_ingredients;
CREATE POLICY "Users can update imported content ingredients"
ON public.imported_content_ingredients
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.imported_content ic
    JOIN public.user_profile up ON up.id = ic.user_id
    WHERE ic.id = imported_content_id
      AND up.auth_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.imported_content ic
    JOIN public.user_profile up ON up.id = ic.user_id
    WHERE ic.id = imported_content_id
      AND up.auth_id = auth.uid()
  )
);

GRANT ALL ON TABLE public.imported_content_ingredients TO authenticated;
GRANT ALL ON TABLE public.imported_content_ingredients TO service_role;

CREATE TABLE IF NOT EXISTS public.imported_content_sub_ingredients (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    imported_content_ingredient_id uuid NOT NULL,
    name text NOT NULL,
    quantity text,
    unit text,
    sort_order integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT fk_imported_content_sub_ingredients_group
        FOREIGN KEY (imported_content_ingredient_id)
        REFERENCES public.imported_content_ingredients(id)
        ON DELETE CASCADE,
    CONSTRAINT unique_imported_content_sub_ingredient_sort
        UNIQUE (imported_content_ingredient_id, sort_order)
);

CREATE INDEX IF NOT EXISTS idx_imported_content_sub_ingredients_parent_sort
    ON public.imported_content_sub_ingredients (imported_content_ingredient_id, sort_order);

CREATE INDEX IF NOT EXISTS idx_imported_content_sub_ingredients_lower_name
    ON public.imported_content_sub_ingredients (lower(name));

DROP TRIGGER IF EXISTS set_imported_content_sub_ingredients_updated_at ON public.imported_content_sub_ingredients;
CREATE TRIGGER set_imported_content_sub_ingredients_updated_at
    BEFORE UPDATE ON public.imported_content_sub_ingredients
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.imported_content_sub_ingredients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view imported content sub ingredients" ON public.imported_content_sub_ingredients;
CREATE POLICY "Users can view imported content sub ingredients"
ON public.imported_content_sub_ingredients
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.imported_content_ingredients ici
    JOIN public.imported_content ic ON ic.id = ici.imported_content_id
    WHERE ici.id = imported_content_ingredient_id
  )
);

DROP POLICY IF EXISTS "Users can insert imported content sub ingredients" ON public.imported_content_sub_ingredients;
CREATE POLICY "Users can insert imported content sub ingredients"
ON public.imported_content_sub_ingredients
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.imported_content_ingredients ici
    JOIN public.imported_content ic ON ic.id = ici.imported_content_id
    JOIN public.user_profile up ON up.id = ic.user_id
    WHERE ici.id = imported_content_ingredient_id
      AND up.auth_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Users can update imported content sub ingredients" ON public.imported_content_sub_ingredients;
CREATE POLICY "Users can update imported content sub ingredients"
ON public.imported_content_sub_ingredients
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.imported_content_ingredients ici
    JOIN public.imported_content ic ON ic.id = ici.imported_content_id
    JOIN public.user_profile up ON up.id = ic.user_id
    WHERE ici.id = imported_content_ingredient_id
      AND up.auth_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.imported_content_ingredients ici
    JOIN public.imported_content ic ON ic.id = ici.imported_content_id
    JOIN public.user_profile up ON up.id = ic.user_id
    WHERE ici.id = imported_content_ingredient_id
      AND up.auth_id = auth.uid()
  )
);

GRANT ALL ON TABLE public.imported_content_sub_ingredients TO authenticated;
GRANT ALL ON TABLE public.imported_content_sub_ingredients TO service_role;

WITH inserted_groups AS (
    INSERT INTO public.imported_content_ingredients (
        imported_content_id,
        group_name,
        sort_order
    )
    SELECT
        ic.id,
        COALESCE(NULLIF(btrim(section.value->>'name'), ''), 'Ingredients'),
        section.ordinality::integer - 1
    FROM public.imported_content ic
    CROSS JOIN LATERAL jsonb_array_elements(ic.content->'ingredients') WITH ORDINALITY AS section(value, ordinality)
    WHERE jsonb_typeof(ic.content->'ingredients') = 'array'
    RETURNING id, imported_content_id, sort_order
)
INSERT INTO public.imported_content_sub_ingredients (
    imported_content_ingredient_id,
    name,
    quantity,
    unit,
    sort_order
)
SELECT
    ig.id,
    item.value->>'name',
    NULLIF(btrim(item.value->>'quantity'), ''),
    NULLIF(btrim(item.value->>'unit'), ''),
    item.ordinality::integer - 1
FROM inserted_groups ig
JOIN public.imported_content ic
  ON ic.id = ig.imported_content_id
CROSS JOIN LATERAL jsonb_array_elements(ic.content->'ingredients') WITH ORDINALITY AS section(value, ordinality)
CROSS JOIN LATERAL jsonb_array_elements(
    CASE
        WHEN jsonb_typeof(section.value->'sub_ingredients') = 'array' THEN section.value->'sub_ingredients'
        ELSE '[]'::jsonb
    END
) WITH ORDINALITY AS item(value, ordinality)
WHERE ig.sort_order = section.ordinality::integer - 1
  AND NULLIF(btrim(item.value->>'name'), '') IS NOT NULL;
