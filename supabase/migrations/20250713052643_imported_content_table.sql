create table "public"."imported_content" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid,
    "source_url" text not null,
    "content" text,
    "metadata" jsonb,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
);


alter table "public"."imported_content" enable row level security;

CREATE UNIQUE INDEX imported_content_pkey ON public.imported_content USING btree (id);

alter table "public"."imported_content" add constraint "imported_content_pkey" PRIMARY KEY using index "imported_content_pkey";

alter table "public"."imported_content" add constraint "imported_content_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."imported_content" validate constraint "imported_content_user_id_fkey";

grant delete on table "public"."imported_content" to "anon";

grant insert on table "public"."imported_content" to "anon";

grant references on table "public"."imported_content" to "anon";

grant select on table "public"."imported_content" to "anon";

grant trigger on table "public"."imported_content" to "anon";

grant truncate on table "public"."imported_content" to "anon";

grant update on table "public"."imported_content" to "anon";

grant delete on table "public"."imported_content" to "authenticated";

grant insert on table "public"."imported_content" to "authenticated";

grant references on table "public"."imported_content" to "authenticated";

grant select on table "public"."imported_content" to "authenticated";

grant trigger on table "public"."imported_content" to "authenticated";

grant truncate on table "public"."imported_content" to "authenticated";

grant update on table "public"."imported_content" to "authenticated";

grant delete on table "public"."imported_content" to "service_role";

grant insert on table "public"."imported_content" to "service_role";

grant references on table "public"."imported_content" to "service_role";

grant select on table "public"."imported_content" to "service_role";

grant trigger on table "public"."imported_content" to "service_role";

grant truncate on table "public"."imported_content" to "service_role";

grant update on table "public"."imported_content" to "service_role";

create policy "Users can insert their own imported content"
on "public"."imported_content"
as permissive
for insert
to authenticated
with check ((auth.uid() = user_id));


create policy "Users can update their own imported content"
on "public"."imported_content"
as permissive
for update
to authenticated
using ((auth.uid() = user_id));


create policy "Users can view their own imported content"
on "public"."imported_content"
as permissive
for select
to authenticated
using ((auth.uid() = user_id));



