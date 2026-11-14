-- Supabase crée nativement les rôles "anon" et "authenticated" avec des
-- GRANTs larges sur le schéma public, la restriction réelle venant des
-- policies RLS. On reproduit ça ici pour que les tests RLS soient
-- significatifs : sans ça, on testerait en tant que superutilisateur
-- "postgres", qui contourne TOUJOURS le RLS — un test qui "passerait"
-- sans jamais avoir vérifié quoi que ce soit.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end $$;

grant anon to postgres;
grant authenticated to postgres;

grant usage on schema public, auth to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to anon, authenticated;
grant execute on all functions in schema public to anon, authenticated;
grant execute on all functions in schema auth to anon, authenticated;

alter default privileges in schema public grant select, insert, update, delete on tables to anon, authenticated;
