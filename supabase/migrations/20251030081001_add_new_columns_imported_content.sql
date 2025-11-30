create type "public"."imported_content_status" as enum ('PROCESSING', 'COMPLETED', 'FAILED');

alter table "public"."imported_content" add column "is_recipe_content" boolean;

alter table "public"."imported_content" add column "status" imported_content_status;

alter table "public"."imported_content" add column "video_duration" integer;


