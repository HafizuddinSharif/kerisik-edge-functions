-- Imported Content Table Schema
-- This file defines the imported_content table structure declaratively

-- Create table for storing imported content from URLs
CREATE TABLE IF NOT EXISTS public.imported_content (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    source_url text NOT NULL,
    content jsonb,
    metadata jsonb,
    video_duration integer,
    is_recipe_content boolean,
    status enum('PROCESSING', 'COMPLETED', 'FAILED'),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

-- Enable RLS
ALTER TABLE public.imported_content ENABLE ROW LEVEL SECURITY;

-- Create policy for users to view all imported content
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
WITH CHECK (auth.uid() = user_id);

-- Create policy for users to update their own imported content
CREATE POLICY "Users can update their own imported content"
ON public.imported_content
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id);

-- Grant permissions
GRANT ALL ON TABLE public.imported_content TO authenticated;
GRANT ALL ON TABLE public.imported_content TO service_role; 