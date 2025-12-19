-- Drop FK constraint on imported_content.user_id to allow anonymization
-- This allows us to set user_id = NULL when deleting accounts while keeping the content

-- 1) Drop the FK constraint
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

-- 2) Ensure user_id is nullable (it should already be, but make sure)
alter table "public"."imported_content"
  alter column "user_id" drop not null;

-- 3) Update RLS update policy to prevent users from changing ownership
-- Add WITH CHECK clause to prevent setting user_id to NULL or another user's profile id
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
)
with check (
  -- Prevent changing ownership: user_id must remain the same or be NULL
  -- But we also prevent setting it to NULL via this policy (only service role can do that)
  user_id is not null
  and exists (
    select 1
    from public.user_profile up
    where up.id = user_id
      and up.auth_id = auth.uid()
  )
);

