-- Update create_user_on_signup to avoid duplicate user_profile rows.
-- Behavior:
--   - On new auth.users row, check if a user_profile with the same email already exists.
--   - If a profile for that email exists, update its auth_id with the new auth user id (if needed).
--   - If none exists, insert a new user_profile row.

create or replace function public.create_user_on_signup() returns trigger
language plpgsql
security definer
as $$
begin
  -- If a profile with this email already exists, ensure its auth_id is set
  if exists (
    select 1
    from public.user_profile up
    where up.email = new.email
  ) then
    update public.user_profile
    set auth_id = new.id
    where email = new.email
      and (auth_id is null or auth_id <> new.id);
  else
    -- Otherwise, insert a new profile row
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
  end if;

  return new;
end;
$$;


