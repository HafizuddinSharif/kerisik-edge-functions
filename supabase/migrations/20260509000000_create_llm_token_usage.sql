-- Migration: 20260509000000_create_llm_token_usage
-- Description: Create service-only audit table for per-call LLM token usage.

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS public.llm_token_usage (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    imported_content_id uuid NOT NULL,
    provider text NOT NULL,
    model text NOT NULL,
    operation text NOT NULL,
    input_tokens integer NOT NULL DEFAULT 0,
    output_tokens integer NOT NULL DEFAULT 0,
    total_tokens integer,
    raw_usage jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_llm_token_usage_imported_content
        FOREIGN KEY (imported_content_id)
        REFERENCES public.imported_content(id)
        ON DELETE CASCADE,
    CONSTRAINT llm_token_usage_input_tokens_non_negative
        CHECK (input_tokens >= 0),
    CONSTRAINT llm_token_usage_output_tokens_non_negative
        CHECK (output_tokens >= 0),
    CONSTRAINT llm_token_usage_total_tokens_non_negative
        CHECK (total_tokens IS NULL OR total_tokens >= 0)
);

CREATE INDEX IF NOT EXISTS idx_llm_token_usage_imported_content_id
    ON public.llm_token_usage (imported_content_id);

CREATE INDEX IF NOT EXISTS idx_llm_token_usage_created_at
    ON public.llm_token_usage (created_at);

CREATE INDEX IF NOT EXISTS idx_llm_token_usage_provider_model_operation
    ON public.llm_token_usage (provider, model, operation);

DROP TRIGGER IF EXISTS set_llm_token_usage_updated_at ON public.llm_token_usage;
CREATE TRIGGER set_llm_token_usage_updated_at
    BEFORE UPDATE ON public.llm_token_usage
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.llm_token_usage ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.llm_token_usage FROM anon;
REVOKE ALL ON TABLE public.llm_token_usage FROM authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.llm_token_usage TO service_role;
