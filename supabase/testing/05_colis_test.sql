-- Tests réels du Lot 5 (Colis). 
set client_min_messages to notice;
reset role;
drop schema if exists th cascade;
create schema th;
grant usage on schema th to anon, authenticated;

create function th.u(n int) returns text language sql immutable as $$ select '00000000-0000-0000-0000-0000000000c' || n::text $$;
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



-- Comptes : 1 Compagnie, 2 Chauffeur, 3 Expéditeur A, 4 Expéditeur B (sans fonds), 9 admin
insert into auth.users (id, email, raw_user_meta_data)
select th.u(n)::uuid, 'c' || n || '@test.ci', jsonb_build_object('full_name', nm, 'phone', '+22507100000' || n)
from (values (1,'Compagnie Colis'),(2,'Chauffeur Colis'),(3,'Expediteur A'),(4,'Expediteur B'),(9,'Admin5')) v(n, nm);
update public.profiles set staff_role = 'admin' where id = th.u(9)::uuid;

set role authenticated;
select th.as_user(th.u(9));
select public.wallet_adjust(th.u(3)::uuid, 200000, 'dotation test');

-- ===== Mise en place : compagnie, autocar approuvé, 3 départs =====
select th.as_user(th.u(1));
select public.submit_identity('CNI', 'CI-COL-1');
select public.request_role('compagnie', array['Licence de transport','Registre de commerce','Assurance']);
select th.as_user(th.u(9));
select public.decide_identity(th.u(1)::uuid, 'verifie', null);
select public.decide_role(th.u(1)::uuid, 'compagnie', 'actif', null);
select th.as_user(th.u(1));
select public.bus_register_company('ColisBus', '+2250700000000');
select th.keep('v1', public.bus_add_vehicle('CI 9001 AA', 'Yutong', 52));
select th.as_user(th.u(9));
select public.bus_approve_vehicle(th.id('v1'), true);
select th.as_user(th.u(1));
select public.bus_add_driver('c2@test.ci');
select th.keep('d1', public.bus_publish_departure(th.id('v1'), 'Abidjan', 'Bouaké', now() + interval '3 days', now() + interval '3 days 6 hours', 17500, th.u(2)::uuid));
select th.keep('d2', public.bus_publish_departure(th.id('v1'), 'Abidjan', 'Yamoussoukro', now() + interval '4 days', now() + interval '4 days 4 hours', 12000, th.u(2)::uuid));
select th.keep('d3', public.bus_publish_departure(th.id('v1'), 'Abidjan', 'Korhogo', now() + interval '5 days', now() + interval '5 days 9 hours', 25000, null));

-- ===== Devis et création =====
select th.as_user(th.u(3));
select th.check_true((select count(*) from public.colis_departures('Abidjan', null)) = 3 and (select min(kg_left) from public.colis_departures(null, null)) = 500, 'recherche : 3 départs, 500 kg de capacité colis');
select th.check_true((select total from public.colis_quote(th.id('d1'), 5, 'petit', 'standard', 'standard')) > 0, 'devis calculé');
select th.check_true((select transport from public.colis_quote(th.id('d1'), 5, 'moyen', 'express', 'standard')) > (select transport from public.colis_quote(th.id('d1'), 5, 'moyen', 'standard', 'standard')), 'devis : express plus cher que standard');
select th.expect_error($q$select * from public.colis_quote(th.id('d1'), 31, 'grand', 'standard', 'standard')$q$, '30 kg', 'plus de 30 kg refusé (Fret)');
select th.expect_error($q$select * from public.colis_quote(th.id('d1'), 6, 'petit', 'standard', 'standard')$q$, '5 kg', 'petit colis limité à 5 kg');
select th.expect_error($q$select public.colis_create(th.id('d1'), 'Awa', '0701020304', 5, 'petit', 'standard', 'standard', 20000, false)$q$, 'produit interdit', 'attestation produits interdits obligatoire');
select th.expect_error($q$select public.colis_create(th.id('d1'), 'Awa', '12345', 5, 'petit', 'standard', 'standard', 20000, true)$q$, 'Téléphone', 'téléphone destinataire invalide');
select th.expect_error($q$select public.colis_create(th.id('d1'), 'Awa', '0701020304', 5, 'petit', 'standard', 'standard', 60000, true)$q$, 'Valeur déclarée', 'valeur au-dessus du plafond de la formule');
select th.as_user(th.u(4));
select th.expect_error($q$select public.colis_create(th.id('d1'), 'Awa', '0701020304', 5, 'petit', 'standard', 'standard', 20000, true)$q$, 'Solde Wallet insuffisant', 'sans fonds : envoi refusé');
select th.as_user(th.u(3));
select th.keep('p1', public.colis_create(th.id('d1'), 'Awa Traoré', '07 01 02 03 04', 5, 'petit', 'standard', 'standard', 20000, true));
select th.check_true(th.bal(3) = 200000 - (select total_fcfa from public.colis_parcels where id = th.id('p1')) and (select total_fcfa = transport_fcfa + insurance_fcfa from public.colis_parcels where id = th.id('p1')), 'Wallet débité du total (transport + assurance)');
select th.check_true((select ref like 'TVC-%' from public.colis_parcels where id = th.id('p1')) and length(public.colis_my_otp(th.id('p1'))) = 6, 'référence TVC et code de retrait à 6 chiffres');
select set_config('th.ref1', (select ref from public.colis_parcels where id = th.id('p1')), false);
select th.keep('p2', public.colis_create(th.id('d1'), 'Koffi', '+2250505050505', 2, 'petit', 'fragile', 'etendue', 100000, true));

-- ===== Confidentialité du code et suivi public =====
select th.as_user(th.u(1));
select th.expect_error(format($q$select otp from public.colis_parcels where id = %L$q$, th.id('p1')), 'permission denied', 'la compagnie ne peut pas lire le code de retrait');
select th.check_true(public.colis_my_otp(th.id('p1')) is null, 'seul l''expéditeur obtient le code');
select th.check_true((select count(*) from public.colis_parcels) = 2, 'la compagnie voit les colis de ses départs');
select th.as_user(th.u(4));
select th.check_true((select count(*) from public.colis_parcels) = 0, 'un autre utilisateur ne voit pas les colis');
reset role;
set role anon;
select th.as_user(null);
select th.check_true((select count(*) from public.colis_track(current_setting('th.ref1'))) = 1, 'suivi public sans compte : 1 évènement');
select th.check_true((select count(*) from public.colis_track('TVC-ZZZZZZ')) = 0, 'code inconnu : rien');
select th.expect_error($q$select * from public.colis_parcels$q$, 'permission denied', 'anonyme : table des colis illisible');
reset role;
set role authenticated;

-- ===== Annulation avant dépôt =====
select th.as_user(th.u(3));
select th.keep('p3', public.colis_create(th.id('d1'), 'Test', '0707070707', 3, 'petit', 'standard', 'standard', 10000, true));
select public.colis_cancel(th.id('p3'));
select th.check_true((select status = 'annule' and refunded_fcfa = total_fcfa from public.colis_parcels where id = th.id('p3')), 'annulation avant dépôt : remboursement intégral');
select th.expect_error($q$select public.colis_cancel(th.id('p3'))$q$, 'déjà pris en charge', 'annulation non rejouable');

-- ===== Dépôt en gare (contrôle du poids) =====
select th.expect_error(format($q$select public.colis_receive(%L, (select ref from public.colis_parcels where id = %L), 5)$q$, th.id('d1'), th.id('p1')), 'Réservé', 'un expéditeur ne réceptionne pas');
select th.as_user(th.u(2));
select th.expect_error(format($q$select public.colis_receive(%L, (select ref from public.colis_parcels where id = %L), 9)$q$, th.id('d1'), th.id('p1')), 'Écart de poids', 'écart de poids > 30 % : colis refusé');
select public.colis_receive(th.id('d1'), (select ref from public.colis_parcels where id = th.id('p1')), 5.5);
select th.check_true((select status = 'depose' and verified_weight_kg = 5.5 from public.colis_parcels where id = th.id('p1')), 'dépôt contrôlé : statut déposé, poids vérifié');
select th.expect_error(format($q$select public.colis_receive(%L, (select ref from public.colis_parcels where id = %L), 5)$q$, th.id('d1'), th.id('p1')), 'déjà réceptionné', 'double réception refusée');
select public.colis_receive(th.id('d1'), (select ref from public.colis_parcels where id = th.id('p2')), 2);
select th.as_user(th.u(3));
select th.expect_error($q$select public.colis_cancel(th.id('p1'))$q$, 'déjà pris en charge', 'annulation impossible après dépôt');
-- un colis non déposé avant le départ sera remboursé
select th.keep('p4', public.colis_create(th.id('d1'), 'Absent', '0708080808', 4, 'petit', 'standard', 'standard', 10000, true));
select th.keep('pb', public.colis_create(th.id('d3'), 'Annulé par la compagnie', '0709090909', 4, 'petit', 'standard', 'standard', 10000, true));
select th.as_user(th.u(1));
select public.colis_receive(th.id('d3'), (select ref from public.colis_parcels where id = th.id('pb')), 4);

-- ===== Départ : transit, arrivée, remise =====
reset role;
update public.bus_departures set departs_at = now() + interval '1 hour' where id = th.id('d1');
set role authenticated;
select th.as_user(th.u(2));
select public.bus_start_departure(th.id('d1'));
select th.check_true((select status from public.colis_parcels where id = th.id('p1')) = 'en_transit', 'départ démarré : colis déposé en transit');
select th.check_true((select status = 'annule' and refunded_fcfa = total_fcfa from public.colis_parcels where id = th.id('p4')), 'colis non déposé : annulé et remboursé au départ');
select th.expect_error(format($q$select public.colis_deliver(%L, (select ref from public.colis_parcels where id = %L), '000000')$q$, th.id('d1'), th.id('p1')), 'pas encore arrivé', 'remise avant arrivée refusée');
select public.bus_complete_departure(th.id('d1'));
select th.check_true((select status from public.colis_parcels where id = th.id('p1')) = 'arrive', 'autocar arrivé : colis arrivé');
select th.expect_error(format($q$select public.colis_deliver(%L, (select ref from public.colis_parcels where id = %L), '999999')$q$, th.id('d1'), th.id('p1')), 'incorrect', 'mauvais code de retrait refusé');
select th.as_user(th.u(3));
select set_config('th.otp', public.colis_my_otp(th.id('p1')), false);
select th.as_user(th.u(2));
select th.check_true(public.colis_deliver(th.id('d1'), (select ref from public.colis_parcels where id = th.id('p1')), current_setting('th.otp'))
   = (select transport_fcfa - round(transport_fcfa * 0.12) from public.colis_parcels where id = th.id('p1')), 'remise contre le code : net compagnie = transport − 12 %');
select th.check_true((select status = 'livre' from public.colis_parcels where id = th.id('p1')), 'statut livré');
select th.expect_error(format($q$select public.colis_deliver(%L, (select ref from public.colis_parcels where id = %L), %L)$q$, th.id('d1'), th.id('p1'), current_setting('th.otp')), 'déjà remis', 'remise non rejouable');
select th.check_true((select count(*) from public.colis_manifest(th.id('d1'))) = 2, 'manifeste : colis annulés exclus');

-- ===== Départ annulé par la compagnie =====
select th.as_user(th.u(1));
select public.bus_cancel_departure(th.id('d3'));
select th.check_true((select status = 'annule' and refunded_fcfa = total_fcfa from public.colis_parcels where id = th.id('pb')), 'départ annulé : colis remboursé intégralement');

-- ===== Réclamations et indemnisation =====
select th.as_user(th.u(3));
select th.expect_error($q$select public.colis_open_claim(th.id('p1'), 'perdu', 'Colis perdu')$q$, 'déjà livré', 'perte impossible sur un colis livré');
select th.expect_error($q$select public.colis_open_claim(th.id('p3'), 'endommage', 'Cassé en route')$q$, 'non pris en charge', 'réclamation impossible sur colis annulé');
select th.keep('k1', public.colis_open_claim(th.id('p1'), 'endommage', 'Le contenu est cassé'));
select th.expect_error($q$select public.colis_open_claim(th.id('p1'), 'endommage', 'Encore')$q$, 'existe déjà', 'une seule réclamation par type');
select th.expect_error(format($q$select public.colis_decide_claim(%L, true, 100, 'ok')$q$, th.id('k1')), 'équipe Transvia', 'l''expéditeur ne décide pas de son indemnité');
select th.as_user(th.u(9));
select th.check_true(public.colis_claim_max(th.id('k1')) = 20000, 'plafond : valeur déclarée 20 000 FCFA (formule Standard)');
select th.expect_error(format($q$select public.colis_decide_claim(%L, true, 25000, 'trop')$q$, th.id('k1')), 'plafond', 'indemnité au-dessus du plafond refusée');
select th.expect_error(format($q$select public.colis_decide_claim(%L, true, 5000, '')$q$, th.id('k1')), 'Motif', 'motif obligatoire');
select public.colis_decide_claim(th.id('k1'), true, 15000, 'Photos reçues, dommage confirmé');
select th.check_true((select status = 'indemnisee' and indemnity_fcfa = 15000 from public.colis_claims where id = th.id('k1')), 'réclamation indemnisée');
select th.as_user(th.u(3));
select th.check_true(th.bal(3) = 200000 - (select total_fcfa from public.colis_parcels where id = th.id('p1')) - (select total_fcfa from public.colis_parcels where id = th.id('p2')) + 15000, 'Wallet expéditeur : indemnité créditée');
select th.expect_error(format($q$select public.colis_decide_claim(%L, false, null, 'x')$q$, th.id('k1')), 'équipe Transvia', 'décision réservée au staff');
select th.as_user(th.u(9));
select th.expect_error(format($q$select public.colis_decide_claim(%L, false, null, 'x')$q$, th.id('k1')), 'déjà traitée', 'réclamation non rejouable');

-- ===== Sécurité et cohérence =====
select th.as_user(th.u(3));
select th.expect_error($q$update public.colis_parcels set total_fcfa = 1$q$, 'permission denied', 'écriture directe sur les colis interdite');
select th.expect_error($q$insert into public.colis_events (parcel_id, status) values (gen_random_uuid(), 'livre')$q$, 'permission denied', 'écriture directe sur le suivi interdite');
reset role;
select th.check_true(
  not exists (select 1 from public.wallets w where w.balance_fcfa <> (select coalesce(sum(e.amount_fcfa), 0) from public.wallet_entries e where e.profile_id = w.profile_id)),
  'cohérence globale : chaque solde = somme de son journal');
do $$ begin raise notice '=== TOUS LES TESTS DU LOT 5 PASSENT ==='; end $$;
