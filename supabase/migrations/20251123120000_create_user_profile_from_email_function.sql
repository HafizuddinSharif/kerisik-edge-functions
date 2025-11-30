-- Create a helper function to create a user_profile row from an email address.
-- This is useful for OAuth flows where you have the user's email and want to
-- ensure a corresponding profile row exists.
--
-- Usage (from client):
--   supabase.rpc('create_user_profile_from_email', { p_email: '<user-email>' })
--
-- Notes:
-- - The function will:
--   - Look up the user in auth.users by email
--   - Insert a row into public.user_profile with that user's id and email
--   - Do nothing if a profile already exists for that id

create or replace function public.create_user_profile_from_email(p_email text)
returns void
language plpgsql
security definer
as $$
declare
  v_user auth.users%rowtype;
begin
  -- Find the auth user by email
  select *
  into v_user
  from auth.users
  where email = p_email
  limit 1;

  -- If no user found, raise an exception
  if v_user.id is null then
    raise exception 'No auth.users record found for email: %', p_email;
  end if;

  -- Insert user_profile row for this user if it does not already exist
  insert into public.user_profile (id, email, is_pro, ai_imports_used)
  values (v_user.id, v_user.email, false, 0)
  on conflict (id) do nothing;
end;
$$;


