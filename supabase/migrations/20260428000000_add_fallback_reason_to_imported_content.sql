-- Add ocr_fallback_reason to imported_content to record why OCR fallback extraction was used.
alter table "public"."imported_content"
  add column if not exists "ocr_fallback_reason" text;
