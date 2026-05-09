# LLM Token Usage

## Purpose

`llm_token_usage` is an internal audit table for tracking LLM input and output token usage generated while processing imported content.

The table records one row per LLM call, not one row per import. This preserves visibility into retries and separate pipeline stages such as transcription, recipe validation, extraction, full-video extraction, audio explanation classification, and categorization.

## Table Contract

Table: `public.llm_token_usage`

Columns:

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` | Primary key, default `gen_random_uuid()` |
| `imported_content_id` | `uuid` | Required FK to `public.imported_content(id)` |
| `provider` | `text` | LLM provider, for example `gemini` or `deepseek` |
| `model` | `text` | Provider model name used for the call |
| `operation` | `text` | Logical call site, for example `extract_transcript` or `transcribe_with_audio_path` |
| `input_tokens` | `integer` | Prompt/input token count; non-negative |
| `output_tokens` | `integer` | Completion/output token count; non-negative |
| `total_tokens` | `integer` | Provider total token count when available; nullable and non-negative |
| `raw_usage` | `jsonb` | Full provider usage metadata for debugging/provider differences |
| `created_at` | `timestamptz` | Insert timestamp, default `now()` |
| `updated_at` | `timestamptz` | Updated by the standard `set_updated_at` trigger |

Constraints and indexes:

- `imported_content_id` references `public.imported_content(id)` with `ON DELETE CASCADE`.
- Token count columns must be non-negative.
- Index `idx_llm_token_usage_imported_content_id` supports import-level lookups.
- Index `idx_llm_token_usage_created_at` supports time-based reporting.
- Index `idx_llm_token_usage_provider_model_operation` supports provider/model/operation cost analysis.

## RLS and Access

`llm_token_usage` is service-only.

- Enable RLS.
- Grant access to `service_role`.
- Do not grant client access to `anon` or `authenticated`.
- Do not add authenticated read/write policies.

This differs from `imported_content`, which currently has broad authenticated read access. Token usage rows may expose internal model choices, pipeline shape, retry behavior, and cost-related data, so they should remain backend-only unless a product requirement explicitly changes that.

## FastAPI Contract

FastAPI should insert rows through service-role Supabase credentials after each LLM response returns usage metadata.

Expected normalization:

- Gemini: read token counts from response `usage_metadata`, store the full serialized usage metadata in `raw_usage`.
- DeepSeek/OpenAI-compatible chat responses: map `prompt_tokens` to `input_tokens`, `completion_tokens` to `output_tokens`, and `total_tokens` to `total_tokens`.
- Missing usage metadata should not fail imports. Store zeros/nulls where appropriate and keep `raw_usage` as `{}` if no provider metadata exists.

Usage logging failures must be non-blocking. Recipe import, transcription, extraction, and categorization should continue if the insert into `llm_token_usage` fails.

Related FastAPI documentation: `fastapi/docs/002-llm-token-usage.md`.

## Verification

Database verification:

- Insert rejects an unknown `imported_content_id`.
- Deleting an `imported_content` row cascades related usage rows.
- Negative token counts are rejected.
- `authenticated` cannot select or insert rows.
- `service_role` can insert and select rows.

FastAPI verification:

- Gemini usage metadata is normalized into `input_tokens`, `output_tokens`, `total_tokens`, and `raw_usage`.
- DeepSeek usage metadata is normalized from `prompt_tokens`, `completion_tokens`, and `total_tokens`.
- LLM calls still succeed when usage logging insert fails.
