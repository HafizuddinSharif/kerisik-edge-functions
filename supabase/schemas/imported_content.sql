-- Imported Content Table Schema
-- This file defines the imported_content table structure declaratively

CREATE TYPE public.imported_content_status AS ENUM ('PROCESSING', 'COMPLETED', 'FAILED');

-- Create table for storing imported content from URLs
CREATE TABLE IF NOT EXISTS public.imported_content (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid, -- No FK constraint to allow anonymization (setting to NULL) when deleting accounts
    source_url text NOT NULL,
    content jsonb,
    metadata jsonb,
    video_duration integer,
    is_recipe_content boolean,
    status imported_content_status,
    error_code text,
    error_display jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Enable RLS
ALTER TABLE public.imported_content ENABLE ROW LEVEL SECURITY;

-- Create policy for users to view their own imported content
CREATE POLICY "Users can view their own imported content"
ON public.imported_content
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.user_profile up
    WHERE up.id = user_id
      AND up.auth_id = auth.uid()
  )
);

-- Create policy for all authenticated users to view imported content
CREATE POLICY "Users can view all imported content"
ON public.imported_content
FOR SELECT
TO authenticated
USING (true);

-- Create policy for users to insert their own imported content
CREATE POLICY "Users can insert their own imported content"
ON public.imported_content
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.user_profile up
    WHERE up.id = user_id
      AND up.auth_id = auth.uid()
  )
);

-- Create policy for users to update their own imported content
CREATE POLICY "Users can update their own imported content"
ON public.imported_content
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.user_profile up
    WHERE up.id = user_id
      AND up.auth_id = auth.uid()
  )
)
WITH CHECK (
  -- Prevent changing ownership: user_id must remain the same and cannot be set to NULL
  user_id IS NOT NULL
  AND EXISTS (
    SELECT 1
    FROM public.user_profile up
    WHERE up.id = user_id
      AND up.auth_id = auth.uid()
  )
);

-- Grant permissions
GRANT ALL ON TABLE public.imported_content TO authenticated;
GRANT ALL ON TABLE public.imported_content TO service_role;

-- Generic trigger to keep updated_at in sync for public tables
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Canonical import error display copy keyed by backend error code and language
CREATE TABLE IF NOT EXISTS public.error_messages (
    error_code text NOT NULL,
    language text NOT NULL,
    title text NOT NULL,
    message text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT error_messages_pkey PRIMARY KEY (error_code, language),
    CONSTRAINT error_messages_language_check
        CHECK (language IN ('EN', 'BM')),
    CONSTRAINT error_messages_title_non_empty
        CHECK (btrim(title) <> ''),
    CONSTRAINT error_messages_message_non_empty
        CHECK (btrim(message) <> '')
);

CREATE TRIGGER set_error_messages_updated_at
    BEFORE UPDATE ON public.error_messages
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.error_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can view active error messages"
ON public.error_messages
FOR SELECT
TO authenticated
USING (is_active = true);

REVOKE ALL ON TABLE public.error_messages FROM anon;
REVOKE ALL ON TABLE public.error_messages FROM authenticated;
GRANT SELECT ON TABLE public.error_messages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.error_messages TO service_role;

-- Denormalized ingredient groups extracted from imported_content.content->ingredients
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

CREATE TRIGGER set_imported_content_ingredients_updated_at
    BEFORE UPDATE ON public.imported_content_ingredients
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.imported_content_ingredients ENABLE ROW LEVEL SECURITY;

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

-- Denormalized ingredient lines extracted from imported_content.content->ingredients[*].sub_ingredients
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

CREATE TRIGGER set_imported_content_sub_ingredients_updated_at
    BEFORE UPDATE ON public.imported_content_sub_ingredients
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.imported_content_sub_ingredients ENABLE ROW LEVEL SECURITY;

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

create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.user_profile (
    id,
    auth_id,
    email,
    is_pro,
    ai_imports_used
  )
  values (
    gen_random_uuid(), -- new UUID for your internal profile ID
    new.id,            -- actual auth user ID
    new.email,
    false,
    0
  );

  return new;
end;
$$;
