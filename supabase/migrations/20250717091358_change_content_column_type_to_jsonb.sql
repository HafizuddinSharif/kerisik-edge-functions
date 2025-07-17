alter table "public"."imported_content" alter column "content" set data type jsonb using "content"::jsonb;


