-- Minimal local stand-in for Supabase's built-in auth schema, so we can develop
-- and test RLS policies against a real Postgres instance before this ever
-- touches an actual Supabase project (which provides these natively).
create schema if not exists auth;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text unique,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Supabase exposes the current request's user id via this function inside
-- RLS policies. We emulate it with a session-local setting so tests can
-- switch "who" is running a query.
-- Reproduit fidèlement la vraie fonction auth.uid() de Supabase, y compris
-- son garde-fou nullif(..., '') pour ne pas planter sur un visiteur anonyme
-- (sub absent/vide) — sans ce garde-fou, un simple SELECT public en tant
-- qu'anon lève une erreur de cast uuid au lieu de renvoyer NULL.
create or replace function auth.uid() returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create or replace function auth.role() returns text
language sql stable
as $$
  select coalesce(current_setting('request.jwt.claim.role', true), 'anon')
$$;
