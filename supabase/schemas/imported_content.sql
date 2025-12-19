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
