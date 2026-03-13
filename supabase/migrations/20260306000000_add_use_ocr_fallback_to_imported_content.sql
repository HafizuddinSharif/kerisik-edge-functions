-- Migration: Add use_ocr_fallback to imported_content
-- Tracks which imports actually used OCR (by_video or fallback OCR text).

ALTER TABLE imported_content
ADD COLUMN IF NOT EXISTS use_ocr_fallback BOOLEAN NOT NULL DEFAULT false;
