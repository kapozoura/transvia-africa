-- Tests réels du Lot 1 (compte unique, rôles, Wallet) : chaque bloc bascule sur
-- le rôle Postgres "authenticated"/"anon" (jamais "postgres", qui contourne la RLS).
set client_min_messages to notice;
reset role;
drop schema if exists th cascade;
create schema th;

create or replace function th.as_user(p_uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid, ''), false);
  perform set_config('request.jwt.claim.role', case when p_uid is null then 'anon' else 'authenticated' end, false);
end $$;

-- attend une erreur contenant p_pattern
create or replace function th.expect_error(p_sql text, p_pattern text, p_label text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm ilike '%' || p_pattern || '%' then
      raise notice 'OK   % (erreur attendue : %)', p_label, sqlerrm; return;
    end if;
    raise exception 'ECHEC % : erreur inattendue "%"', p_label, sqlerrm;
  end;
  raise exception 'ECHEC % : aucune erreur levée', p_label;
end $$;

create or replace function th.check_true(p_cond boolean, p_label text) returns void language plpgsql as $$
begin
  if p_cond is not true then raise exception 'ECHEC %', p_label; end if;
  raise notice 'OK   %', p_label;
end $$;

grant execute on all functions in schema th to anon, authenticated;
grant usage on schema th to anon, authenticated;

-- --- Comptes (le trigger crée profil + wallet) ---
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'alice@test.ci', '{"full_name":"Alice Traoré","phone":"+2250700000001","city":"Abidjan"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bob@test.ci',   '{"full_name":"Bob Koné"}'),
  ('00000000-0000-0000-0000-00000000000c', 'admin@test.ci', '{"full_name":"Admin"}'),
  ('00000000-0000-0000-0000-00000000000d', 'finance@test.ci','{"full_name":"Finance"}'),
  -- tentative d'élévation via les métadonnées d'inscription
  ('00000000-0000-0000-0000-00000000000e', 'mallory@test.ci','{"full_name":"Mallory","staff_role":"admin","id_verified":true,"role":"admin"}');
update public.profiles set staff_role = 'admin'   where id = '00000000-0000-0000-0000-00000000000c';
update public.profiles set staff_role = 'finance' where id = '00000000-0000-0000-0000-00000000000d';

select th.check_true((select count(*) from public.profiles) = 5 and (select count(*) from public.wallets) = 5, 'trigger : un profil et un Wallet par compte');
select th.check_true((select staff_role is null and not id_verified from public.profiles where id = '00000000-0000-0000-0000-00000000000e'), 'métadonnées d''inscription ne donnent ni rôle d''équipe ni identité vérifiée');

-- ===== Alice =====
set role authenticated;
select th.as_user('00000000-0000-0000-0000-00000000000a');

select th.check_true((select count(*) from public.profiles) = 1, 'Alice ne voit que son profil');
select th.check_true((select count(*) from public.role_catalog) = 7, 'catalogue des rôles lisible');
update public.profiles set full_name = 'Alice T.' where id = '00000000-0000-0000-0000-00000000000a';
select th.check_true((select full_name from public.profiles) = 'Alice T.', 'Alice peut modifier son nom');
select th.expect_error($q$update public.profiles set id_verified = true where id = '00000000-0000-0000-0000-00000000000a'$q$, 'permission denied', 'Alice ne peut pas se déclarer vérifiée');
select th.expect_error($q$update public.profiles set staff_role = 'admin' where id = '00000000-0000-0000-0000-00000000000a'$q$, 'permission denied', 'Alice ne peut pas se donner un rôle d''équipe');
select th.expect_error($q$update public.profiles set status = 'actif' where id = '00000000-0000-0000-0000-00000000000a'$q$, 'permission denied', 'Alice ne peut pas modifier son statut');
select th.expect_error($q$insert into public.profile_roles (profile_id, role, status) values ('00000000-0000-0000-0000-00000000000a', 'loueur', 'actif')$q$, 'permission denied', 'Alice ne peut pas s''attribuer un rôle directement');
select th.expect_error($q$update public.wallets set balance_fcfa = 9999999 where profile_id = '00000000-0000-0000-0000-00000000000a'$q$, 'permission denied', 'Alice ne peut pas écrire son solde');
select th.expect_error($q$insert into public.wallet_entries (profile_id, amount_fcfa, kind, label, balance_after) values ('00000000-0000-0000-0000-00000000000a', 5000, 'revenu', 'x', 5000)$q$, 'permission denied', 'Alice ne peut pas écrire dans le journal');
select th.expect_error($q$select public.wallet_post('00000000-0000-0000-0000-00000000000a', 5000, 'revenu', 'x', null)$q$, 'permission denied', 'wallet_post est interne');
select th.expect_error($q$select public.request_role('loueur', array['Carte grise','Assurance','Visite technique'])$q$, 'identité', 'rôle refusé tant que l''identité n''est pas soumise');
select public.submit_identity('CNI', 'CI-ID-123456');
select th.expect_error($q$select public.request_role('loueur', array['Carte grise'])$q$, 'Pièces manquantes', 'pièces manquantes refusées');
select public.request_role('loueur', array['Carte grise','Assurance','Visite technique']);
select th.check_true((select status from public.profile_roles where role = 'loueur') = 'en_attente', 'demande de rôle en attente');
select th.expect_error($q$select public.request_role('loueur', array['Carte grise','Assurance','Visite technique'])$q$, 'déjà', 'double demande refusée');
select th.expect_error($q$select public.decide_identity('00000000-0000-0000-0000-00000000000a', 'verifie', null)$q$, 'Réservé', 'Alice ne peut pas valider sa propre identité');
select th.expect_error($q$select public.decide_role('00000000-0000-0000-0000-00000000000a', 'loueur', 'actif', null)$q$, 'Réservé', 'Alice ne peut pas valider son propre rôle');
select th.expect_error($q$select public.wallet_adjust('00000000-0000-0000-0000-00000000000a', 100000, 'moi')$q$, 'Réservé', 'Alice ne peut pas s''ajuster son Wallet');

-- ===== Bob =====
select th.as_user('00000000-0000-0000-0000-00000000000b');
select th.check_true((select count(*) from public.profile_roles) = 0 and (select count(*) from public.identity_checks) = 0, 'Bob ne voit ni les rôles ni l''identité d''Alice');
select th.check_true((select count(*) from public.wallets) = 1, 'Bob ne voit que son Wallet');

-- ===== Admin =====
select th.as_user('00000000-0000-0000-0000-00000000000c');
select th.check_true((select count(*) from public.profile_roles) = 1 and (select count(*) from public.identity_checks) = 1, 'Admin voit les demandes');
select th.expect_error($q$select public.decide_role('00000000-0000-0000-0000-00000000000a', 'loueur', 'actif', null)$q$, 'Identité non vérifiée', 'rôle non activable avant vérification de l''identité');
select th.expect_error($q$select public.decide_identity('00000000-0000-0000-0000-00000000000a', 'refuse', '')$q$, 'Motif', 'refus d''identité sans motif refusé');
select public.decide_identity('00000000-0000-0000-0000-00000000000a', 'verifie', null);
select public.decide_role('00000000-0000-0000-0000-00000000000a', 'loueur', 'actif', null);
select th.check_true((select id_verified from public.profiles where id = '00000000-0000-0000-0000-00000000000a'), 'identité vérifiée une seule fois');

-- ===== Finance =====
select th.as_user('00000000-0000-0000-0000-00000000000d');
select th.expect_error($q$select public.decide_role('00000000-0000-0000-0000-00000000000a', 'loueur', 'suspendu', 'x')$q$, 'Réservé', 'Finance ne modère pas les rôles');
select th.expect_error($q$select public.wallet_adjust('00000000-0000-0000-0000-00000000000a', 10000, '')$q$, 'Motif', 'ajustement sans motif refusé');
select public.wallet_adjust('00000000-0000-0000-0000-00000000000a', 10000, 'dotation test');

-- ===== Alice : rôle actif, 2e rôle sans nouvelle identité, Wallet =====
select th.as_user('00000000-0000-0000-0000-00000000000a');
select th.check_true((select status from public.profile_roles where role = 'loueur') = 'actif', 'rôle Loueur actif');
select public.request_role('chauffeur_vtc', array['Permis de conduire','Documents du véhicule']);
select th.check_true((select count(*) from public.identity_checks) = 1, '2e rôle demandé sans nouvelle pièce d''identité');
select th.expect_error($q$select public.submit_identity('CNI', 'CI-ID-999999')$q$, 'déjà vérifiée', 'identité vérifiée non modifiable');
select th.expect_error($q$select public.wallet_topup_simulated(500)$q$, 'Montant', 'recharge trop faible refusée');
select th.expect_error($q$select public.wallet_topup_simulated(200000)$q$, 'Montant', 'recharge trop élevée refusée');
select th.check_true(public.wallet_topup_simulated(5000) = 15000, 'recharge simulée : 10 000 (dotation) + 5 000 = 15 000');
select th.check_true((select count(*) from public.wallet_entries) = 2 and (select min(balance_after) from public.wallet_entries) = 10000, 'journal : 2 écritures avec solde après');
select th.check_true((select count(*) from public.admin_log) = 0, 'Alice ne voit pas le journal d''audit');

-- ===== Admin : refus motivé, re-demande, suspension =====
select th.as_user('00000000-0000-0000-0000-00000000000c');
select th.expect_error($q$select public.decide_role('00000000-0000-0000-0000-00000000000a', 'chauffeur_vtc', 'refuse', null)$q$, 'Motif', 'refus de rôle sans motif refusé');
select public.decide_role('00000000-0000-0000-0000-00000000000a', 'chauffeur_vtc', 'refuse', 'Permis illisible');
select th.as_user('00000000-0000-0000-0000-00000000000a');
select th.check_true((select reason from public.profile_roles where role = 'chauffeur_vtc') = 'Permis illisible', 'motif du refus visible par l''utilisateur');
select public.request_role('chauffeur_vtc', array['Permis de conduire','Documents du véhicule']);
select th.check_true((select status from public.profile_roles where role = 'chauffeur_vtc') = 'en_attente', 'nouvelle demande possible après un refus');
select th.as_user('00000000-0000-0000-0000-00000000000c');
select public.decide_role('00000000-0000-0000-0000-00000000000a', 'loueur', 'suspendu', 'Litige en cours');
select th.as_user('00000000-0000-0000-0000-00000000000a');
select th.expect_error($q$select public.request_role('loueur', array['Carte grise','Assurance','Visite technique'])$q$, 'déjà', 'un rôle suspendu ne se réactive pas seul');
select th.check_true((select count(*) from public.admin_log) = 0, 'journal d''audit toujours invisible pour Alice');
select th.as_user('00000000-0000-0000-0000-00000000000c');
select th.check_true((select count(*) from public.admin_log) >= 5, 'journal d''audit visible par l''équipe');

-- ===== Wallet : jamais négatif, journal inaltérable =====
select th.expect_error($q$select public.wallet_adjust('00000000-0000-0000-0000-00000000000a', -99999999, 'test')$q$, 'check', 'solde jamais négatif');

reset role;
select th.expect_error($q$update public.wallet_entries set amount_fcfa = 1$q$, 'inaltérable', 'journal : modification impossible');
select th.expect_error($q$delete from public.wallet_entries$q$, 'inaltérable', 'journal : suppression impossible');
select th.check_true((select sum(amount_fcfa) from public.wallet_entries where profile_id = '00000000-0000-0000-0000-00000000000a') = (select balance_fcfa from public.wallets where profile_id = '00000000-0000-0000-0000-00000000000a'), 'cohérence : somme du journal = solde');

-- ===== Compte bloqué =====
update public.profiles set status = 'bloque' where id = '00000000-0000-0000-0000-00000000000b';
set role authenticated;
select th.as_user('00000000-0000-0000-0000-00000000000b');
select th.expect_error($q$select public.wallet_topup_simulated(5000)$q$, 'bloqué', 'compte bloqué : recharge refusée');

-- ===== Visiteur anonyme =====
reset role;
set role anon;
select th.as_user(null);
select th.check_true((select count(*) from public.profiles) = 0, 'anonyme : aucun profil visible');
select th.check_true((select count(*) from public.wallets) = 0, 'anonyme : aucun Wallet visible');
select th.check_true((select count(*) from public.role_catalog) = 7, 'anonyme : catalogue des rôles lisible');
select th.expect_error($q$select public.wallet_topup_simulated(5000)$q$, 'permission denied', 'anonyme : RPC Wallet interdite');
reset role;
\echo === TOUS LES TESTS DU LOT 1 PASSENT ===
