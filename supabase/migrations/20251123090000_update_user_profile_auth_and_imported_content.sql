-- Add auth_id to user_profile and rewire IDs and imported_content.user_id

-- 1) Add auth_id column to user_profile (nullable, we'll backfill and then constrain)
alter table "public"."user_profile"
  add column if not exists "auth_id" uuid;

-- 2) Backfill auth_id from existing id (which currently matches auth.users.id)
update "public"."user_profile"
set "auth_id" = "id"
where "auth_id" is null;

-- 3) Enforce uniqueness and FK on auth_id
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'user_profile_auth_id_key'
      and conrelid = 'public.user_profile'::regclass
  ) then
    alter table "public"."user_profile"
      add constraint "user_profile_auth_id_key" unique ("auth_id");
  end if;
end$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'user_profile_auth_id_fkey'
      and conrelid = 'public.user_profile'::regclass
  ) then
    alter table "public"."user_profile"
      add constraint "user_profile_auth_id_fkey"
      foreign key ("auth_id") references "auth"."users"("id")
      on update cascade on delete cascade;
  end if;
end$$;

-- 4) Drop old FK that tied id directly to auth.users(id)
do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'user_profile_id_fkey'
      and conrelid = 'public.user_profile'::regclass
  ) then
    alter table "public"."user_profile"
      drop constraint "user_profile_id_fkey";
  end if;
end$$;

-- 5) Regenerate internal IDs for user_profile
update "public"."user_profile"
set "id" = gen_random_uuid();

-- 6) Make sure RLS policy compares auth.uid() to auth_id, not id
do $$
begin
  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_profile'
      and policyname = 'Enable users to view their own data only'
  ) then
    alter policy "Enable users to view their own data only"
      on "public"."user_profile"
      using (((select auth.uid() as uid) = auth_id));
  end if;
end$$;

-- 7) Rewire imported_content.user_id to point to user_profile.id

-- Drop existing FK to auth.users(id) if present
do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'imported_content_user_id_fkey'
      and conrelid = 'public.imported_content'::regclass
  ) then
    alter table "public"."imported_content"
      drop constraint "imported_content_user_id_fkey";
  end if;
end$$;

-- Update imported_content.user_id values:
-- they currently store auth.users.id; map them to the new user_profile.id via auth_id
update "public"."imported_content" ic
set "user_id" = up."id"
from "public"."user_profile" up
where ic."user_id" = up."auth_id";

-- Add new FK to user_profile(id)
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'imported_content_user_id_fkey'
      and conrelid = 'public.imported_content'::regclass
  ) then
    alter table "public"."imported_content"
      add constraint "imported_content_user_id_fkey"
      foreign key ("user_id") references "public"."user_profile"("id")
      on delete cascade;
  end if;
end$$;

-- 8) Update RLS policies on imported_content to respect user_profile/auth_id mapping

do $$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'imported_content'
      and policyname = 'Users can insert their own imported content'
  ) then
    drop policy "Users can insert their own imported content"
      on "public"."imported_content";
  end if;
end$$;

create policy "Users can insert their own imported content"
on "public"."imported_content"
as permissive
for insert
to authenticated
with check (
  exists (
    select 1
    from public.user_profile up
    where up.id = user_id
      and up.auth_id = auth.uid()
  )
);

do $$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'imported_content'
      and policyname = 'Users can update their own imported content'
  ) then
    drop policy "Users can update their own imported content"
      on "public"."imported_content";
  end if;
end$$;

create policy "Users can update their own imported content"
on "public"."imported_content"
as permissive
for update
to authenticated
using (
  exists (
    select 1
    from public.user_profile up
    where up.id = user_id
      and up.auth_id = auth.uid()
  )
);

do $$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'imported_content'
      and policyname = 'Users can view their own imported content'
  ) then
    drop policy "Users can view their own imported content"
      on "public"."imported_content";
  end if;
end$$;

create policy "Users can view their own imported content"
on "public"."imported_content"
as permissive
for select
to authenticated
using (
  exists (
    select 1
    from public.user_profile up
    where up.id = user_id
      and up.auth_id = auth.uid()
  )
);

-- 9) Ensure create_user_on_signup uses internal id and auth_id
create or replace function public.create_user_on_signup() returns trigger
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
    gen_random_uuid(),
    new.id,
    new.email,
    false,
    0
  );

  return new;
end;
$$;


