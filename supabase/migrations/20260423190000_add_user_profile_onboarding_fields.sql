alter table public.user_profile
  add column if not exists display_name text,
  add column if not exists onboarding_intent text,
  add column if not exists cuisine_preferences text[] not null default '{}',
  add column if not exists has_completed_onboarding boolean not null default false,
  add column if not exists onboarding_completed_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'user_profile_onboarding_intent_check'
      and conrelid = 'public.user_profile'::regclass
  ) then
    alter table public.user_profile
      add constraint user_profile_onboarding_intent_check
      check (
        onboarding_intent is null
        or onboarding_intent in ('save', 'plan', 'explore', 'family')
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'user_profile'
      and policyname = 'Users can update their own profile'
  ) then
    create policy "Users can update their own profile"
      on public.user_profile
      for update
      to authenticated
      using (auth_id = auth.uid())
      with check (auth_id = auth.uid());
  end if;
end $$;
