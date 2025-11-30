-- Update create_user_profile_from_email to work purely off user_profile.email.
-- Behavior:
-- - If a user_profile row with the given email already exists, do nothing.
-- - If no such row exists, insert a new user_profile row with a fresh internal id.

create or replace function public.create_user_profile_from_email(p_email text)
returns void
language plpgsql
security definer
as $$
declare
  v_exists boolean;
begin
  -- Check if a profile already exists for this email
  select exists (
    select 1
    from public.user_profile
    where email = p_email
  )
  into v_exists;

  -- If not, insert a new profile row
  if not v_exists then
    insert into public.user_profile (
      id,
      email,
      is_pro,
      ai_imports_used
    )
    values (
      gen_random_uuid(),
      p_email,
      false,
      0
    );
  end if;
end;
$$;


