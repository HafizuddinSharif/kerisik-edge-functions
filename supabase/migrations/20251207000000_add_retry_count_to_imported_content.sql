-- Add retry_count column to imported_content with default 0
alter table "public"."imported_content"
  add column if not exists "retry_count" integer not null default 0;


