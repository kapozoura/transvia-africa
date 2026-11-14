-- Tests réels du Lot 4 (VTC). 
set client_min_messages to notice;
reset role;
drop schema if exists th cascade;
create schema th;
grant usage on schema th to anon, authenticated;

create function th.u(n int) returns text language sql immutable as $$ select '00000000-0000-0000-0000-0000000000d' || n::text $$;
create function th.as_user(p_uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid, ''), false);
  perform set_config('request.jwt.claim.role', case when p_uid is null then 'anon' else 'authenticated' end, false);
end $$;
create function th.expect_error(p_sql text, p_pattern text, p_label text) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when others then
    if sqlerrm ilike '%' || p_pattern || '%' then raise notice 'OK   % (erreur attendue : %)', p_label, sqlerrm; return; end if;
    raise exception 'ECHEC % : erreur inattendue "%"', p_label, sqlerrm;
  end;
  raise exception 'ECHEC % : aucune erreur levée', p_label;
end $$;
create function th.check_true(p_cond boolean, p_label text) returns void language plpgsql as $$
begin
  if p_cond is not true then raise exception 'ECHEC %', p_label; end if;
  raise notice 'OK   %', p_label;
end $$;
create table th.ids (k text primary key, v uuid);
grant all on th.ids to anon, authenticated;
create function th.keep(p_k text, p_v uuid) returns void language sql security definer as $$ insert into th.ids values (p_k, p_v) $$;
create function th.id(p_k text) returns uuid language sql security definer as $$ select v from th.ids where k = p_k $$;
create function th.bal(n int) returns bigint language sql security definer as $$ select balance_fcfa from public.wallets where profile_id = th.u(n)::uuid $$;
grant execute on all functions in schema th to anon, authenticated;



-- Comptes : 1 Chauffeur standard, 2 Chauffeur confort, 3 Pax A, 4 Pax B (sans fonds), 5 Pax C, 9 admin
insert into auth.users (id, email, raw_user_meta_data)
select th.u(n)::uuid, 'v' || n || '@test.ci', jsonb_build_object('full_name', nm, 'phone', '+22509000000' || n)
from (values (1,'Chauffeur Kone'),(2,'Chauffeur Diallo'),(3,'Pax A'),(4,'Pax B'),(5,'Pax C'),(9,'Admin4')) v(n, nm);
update public.profiles set staff_role = 'admin' where id = th.u(9)::uuid;

set role authenticated;
select th.as_user(th.u(9));
select public.wallet_adjust(th.u(3)::uuid, 100000, 'dotation test');
select public.wallet_adjust(th.u(5)::uuid, 100000, 'dotation test');

-- ===== Rôles chauffeur =====
select th.as_user(th.u(1));
select th.expect_error($q$select public.vtc_add_vehicle('CI 1 AA', 'Toyota', 'standard', 4)$q$, 'Rôle Chauffeur VTC', 'sans rôle : ajout de véhicule refusé');
select public.submit_identity('CNI', 'CI-V-001');
select public.request_role('chauffeur_vtc', array['Permis de conduire','Documents du véhicule']);
select th.as_user(th.u(2));
select public.submit_identity('CNI', 'CI-V-002');
select public.request_role('chauffeur_vtc', array['Permis de conduire','Documents du véhicule']);
select th.as_user(th.u(9));
select public.decide_identity(th.u(1)::uuid, 'verifie', null);
select public.decide_role(th.u(1)::uuid, 'chauffeur_vtc', 'actif', null);
select public.decide_identity(th.u(2)::uuid, 'verifie', null);
select public.decide_role(th.u(2)::uuid, 'chauffeur_vtc', 'actif', null);

-- ===== Véhicules, approbation, mise en ligne =====
select th.as_user(th.u(1));
select th.keep('v1', public.vtc_add_vehicle('CI 1111 AA', 'Toyota Corolla', 'standard', 4));
select th.expect_error($q$select public.vtc_add_vehicle('ci 1111 aa', 'Autre', 'eco', 4)$q$, 'déjà enregistrée', 'plaque en double refusée');
select th.expect_error(format($q$select public.vtc_set_online(true, %L, 'Plateau')$q$, th.id('v1')), 'approuvé', 'en ligne avec véhicule non approuvé refusé');
select th.as_user(th.u(3));
select th.expect_error(format($q$select public.vtc_approve_vehicle(%L, true)$q$, th.id('v1')), 'équipe Transvia', 'approbation par un passager refusée');
select th.as_user(th.u(9));
select public.vtc_approve_vehicle(th.id('v1'), true);
select th.as_user(th.u(2));
select th.keep('v2', public.vtc_add_vehicle('CI 2222 BB', 'Mercedes C', 'confort', 4));
select th.as_user(th.u(9));
select public.vtc_approve_vehicle(th.id('v2'), true);
select th.as_user(th.u(1));
select th.expect_error($q$select public.vtc_set_online(true, (select id from public.vtc_vehicles where plate = 'CI 2222 BB'), 'Plateau')$q$, 'approuvé', 'en ligne avec le véhicule d''un autre refusé');
select public.vtc_set_online(true, th.id('v1'), 'Plateau');
select th.as_user(th.u(2));
select public.vtc_set_online(true, th.id('v2'), 'Cocody');

-- ===== Devis =====
select th.as_user(th.u(3));
select th.check_true((select price_fcfa from public.vtc_quote('Plateau','Cocody') where category = 'eco')
                   < (select price_fcfa from public.vtc_quote('Plateau','Cocody') where category = 'standard')
                 and (select price_fcfa from public.vtc_quote('Plateau','Cocody') where category = 'standard')
                   < (select price_fcfa from public.vtc_quote('Plateau','Cocody') where category = 'premium'), 'devis : éco < standard < premium');
select th.check_true((select min(price_fcfa) from public.vtc_quote('Plateau','Adjamé')) >= 1000, 'devis : tarif minimum 1 000 FCFA');

-- ===== Commande, séquestre, une seule course active =====
select th.expect_error($q$select public.vtc_request('Plateau', 'Plateau', 'standard')$q$, 'identiques', 'départ = arrivée refusé');
select th.as_user(th.u(4));
select th.expect_error($q$select public.vtc_request('Plateau', 'Cocody', 'standard')$q$, 'Solde Wallet insuffisant', 'sans fonds : commande refusée');
select th.as_user(th.u(3));
select th.keep('r1', public.vtc_request('Plateau', 'Cocody', 'standard'));
select th.check_true(th.bal(3) = 100000 - (select price_fcfa from public.vtc_rides where id = th.id('r1')), 'Wallet débité du prix de la course');
select th.expect_error($q$select public.vtc_request('Plateau', 'Marcory', 'standard')$q$, 'déjà une course', 'une seule course active par passager');

-- ===== Code PIN confidentiel =====
select th.check_true(length(public.vtc_my_pin(th.id('r1'))) = 4, 'le passager voit son code de prise en charge');
select th.as_user(th.u(1));
select th.expect_error(format($q$select pin from public.vtc_rides where id = %L$q$, th.id('r1')), 'permission denied', 'le chauffeur ne peut pas lire le code en direct');
select th.check_true(public.vtc_my_pin(th.id('r1')) is null, 'le chauffeur ne reçoit pas le code via la fonction');

-- ===== Matching par catégorie =====
select th.check_true(exists (select 1 from public.vtc_open_requests() where id = th.id('r1')), 'chauffeur standard voit la demande standard');
select th.as_user(th.u(2));
select th.check_true(not exists (select 1 from public.vtc_open_requests() where id = th.id('r1')), 'chauffeur confort ne voit pas une demande standard');
select th.expect_error(format($q$select public.vtc_accept(%L)$q$, th.id('r1')), 'Catégorie incompatible', 'acceptation hors catégorie refusée');

-- ===== Cycle complet =====
select th.as_user(th.u(1));
select public.vtc_accept(th.id('r1'));
select th.as_user(th.u(2));
select th.expect_error(format($q$select public.vtc_accept(%L)$q$, th.id('r1')), 'déjà prise', 'course déjà prise : second chauffeur refusé');
select th.as_user(th.u(1));
select th.expect_error(format($q$select public.vtc_start(%L, '0000')$q$, th.id('r1')), 'pas encore arrivé', 'démarrage avant arrivée refusé');
select public.vtc_arrive(th.id('r1'));
select th.expect_error(format($q$select public.vtc_start(%L, %L)$q$, th.id('r1'), case when (select 1) = 1 then 'xxxx' end), 'incorrect', 'mauvais code refusé');
select th.as_user(th.u(3));
select set_config('th.pin', public.vtc_my_pin(th.id('r1')), false);
select th.as_user(th.u(1));
select public.vtc_start(th.id('r1'), current_setting('th.pin'));
select th.as_user(th.u(3));
select th.expect_error(format($q$select public.vtc_cancel_ride(%L)$q$, th.id('r1')), 'ne peut plus', 'annulation passager refusée en cours de route');
select th.as_user(th.u(1));
select th.check_true(public.vtc_complete(th.id('r1')) = (select price_fcfa - round(price_fcfa * 0.08) from public.vtc_rides where id = th.id('r1')), 'fin de course : net chauffeur = prix - 8 %');
select th.check_true(th.bal(1) = (select driver_net_fcfa from public.vtc_rides where id = th.id('r1')), 'Wallet chauffeur crédité du net');
select th.as_user(th.u(3));
select public.vtc_rate(th.id('r1'), 5, 'Très bien');
select th.expect_error(format($q$select public.vtc_rate(%L, 4, null)$q$, th.id('r1')), 'déjà notée', 'double notation refusée');
select th.as_user(th.u(1));
select th.check_true((select avg_rating from public.vtc_driver_rating(th.u(1)::uuid)) = 5.00, 'note moyenne du chauffeur');

-- ===== Annulations =====
select th.as_user(th.u(3));
select th.keep('r2', public.vtc_request('Marcory', 'Plateau', 'standard'));
select th.check_true(public.vtc_cancel_ride(th.id('r2')) = (select price_fcfa from public.vtc_rides where id = th.id('r2')), 'annulation avant chauffeur : remboursement 100 %');
select th.keep('r3', public.vtc_request('Marcory', 'Plateau', 'standard'));
select th.as_user(th.u(1));
select public.vtc_accept(th.id('r3'));
select th.as_user(th.u(3));
select th.check_true(public.vtc_cancel_ride(th.id('r3')) = (select price_fcfa - 500 from public.vtc_rides where id = th.id('r3')), 'annulation après acceptation : frais de 500 FCFA');
select th.keep('r4', public.vtc_request('Marcory', 'Plateau', 'standard'));
select th.as_user(th.u(1));
select public.vtc_accept(th.id('r4'));
select public.vtc_arrive(th.id('r4'));
select th.as_user(th.u(3));
select th.check_true(public.vtc_cancel_ride(th.id('r4')) = (select price_fcfa - 1000 from public.vtc_rides where id = th.id('r4')), 'annulation chauffeur arrivé : frais de 1 000 FCFA');
-- le chauffeur annule : remboursement intégral, aucun revenu
select th.keep('r5', public.vtc_request('Marcory', 'Plateau', 'standard'));
select th.as_user(th.u(1));
select public.vtc_accept(th.id('r5'));
select public.vtc_driver_cancel(th.id('r5'));
select th.as_user(th.u(3));
select th.check_true((select status from public.vtc_rides where id = th.id('r5')) = 'annulee_chauffeur' and (select refunded_fcfa = price_fcfa from public.vtc_rides where id = th.id('r5')), 'annulation chauffeur : passager remboursé en totalité');

-- ===== Expiration =====
select th.keep('r6', public.vtc_request('Marcory', 'Plateau', 'standard'));
reset role;
update public.vtc_rides set created_at = now() - interval '11 minutes' where id = th.id('r6');
set role authenticated;
select th.as_user(th.u(3));
select th.check_true(public.vtc_sweep() = 1, 'demande sans chauffeur expirée après 10 min');
select th.check_true((select status from public.vtc_rides where id = th.id('r6')) = 'expiree', 'statut expirée');

-- ===== Cohérence du Wallet passager =====
-- dotation 100000 - course 1 payée - frais 500 - frais 1000 (les autres remboursées en totalité)
select th.check_true(th.bal(3) = 100000 - (select price_fcfa from public.vtc_rides where id = th.id('r1'))
   - 500 - 1000 - 0, 'Wallet passager : solde final exact');

-- ===== Sécurité =====
select th.expect_error($q$update public.vtc_rides set price_fcfa = 1000$q$, 'permission denied', 'écriture directe sur les courses refusée');
select th.as_user(th.u(5));
select th.check_true(not exists (select 1 from public.vtc_rides), 'un passager ne voit pas les courses des autres');
select th.as_user(th.u(1));
select public.vtc_set_online(false, null, null);
select th.check_true(not exists (select 1 from public.vtc_open_requests()), 'hors ligne : plus aucune demande');
select th.as_user(th.u(9));
select th.check_true(exists (select 1 from public.vtc_rides), 'le staff voit les courses');

do $$ begin raise notice '=== TOUS LES TESTS DU LOT 4 PASSENT ==='; end $$;
