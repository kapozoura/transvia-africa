-- Tests réels du Lot 2 (Covoiturage). Rejoué après les tests du Lot 1 dans la même base.
set client_min_messages to notice;
reset role;
drop schema if exists th cascade;
create schema th;
grant usage on schema th to anon, authenticated;

create function th.u(n int) returns text language sql immutable as $$ select '00000000-0000-0000-0000-0000000000f' || n::text $$;
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

-- Comptes : 1 Dana (conductrice), 2 Pat, 3 Quinn (passagers), 4 Rick (sans rôle), 9 admin
insert into auth.users (id, email, raw_user_meta_data)
select th.u(n)::uuid, 'u' || n || '@test.ci', jsonb_build_object('full_name', nm, 'phone', '+22507000000' || n)
from (values (1,'Dana'),(2,'Pat'),(3,'Quinn'),(4,'Rick'),(9,'Admin2')) v(n, nm);
update public.profiles set staff_role = 'admin' where id = th.u(9)::uuid;

-- Dotation Wallet par l'équipe
set role authenticated;
select th.as_user(th.u(9));
select public.wallet_adjust(th.u(2)::uuid, 20000, 'dotation test');
select public.wallet_adjust(th.u(3)::uuid, 20000, 'dotation test');
select public.wallet_adjust(th.u(4)::uuid, 1000, 'dotation test');

-- ===== Conductrice : parcours d'activation du rôle (Lot 1) =====
select th.as_user(th.u(4));
select th.expect_error($q$select public.carpool_publish('Abidjan','Bouaké', now() + interval '3 days', 3, 7000, true)$q$, 'Rôle Conducteur', 'sans rôle activé : publication refusée');
select th.as_user(th.u(1));
select public.submit_identity('CNI', 'CI-DANA-12345');
select public.request_role('conducteur_covoiturage', array['Permis de conduire','Documents du véhicule']);
select th.expect_error($q$select public.carpool_publish('Abidjan','Bouaké', now() + interval '3 days', 3, 7000, true)$q$, 'Rôle Conducteur', 'rôle en attente : publication toujours refusée');
select th.as_user(th.u(9));
select public.decide_identity(th.u(1)::uuid, 'verifie', null);
select public.decide_role(th.u(1)::uuid, 'conducteur_covoiturage', 'actif', null);

-- ===== Publication =====
select th.as_user(th.u(1));
select th.check_true((select suggested from public.carpool_price_hint('Abidjan','Bouaké')) = 6800 and (select cap from public.carpool_price_hint('Bouaké','Abidjan')) = 9520, 'prix suggéré 6 800 et plafond 9 520 (Abidjan–Bouaké, dans les deux sens)');
select th.expect_error($q$select public.carpool_publish('Abidjan','Bouaké', now() + interval '3 days', 3, 9600, true)$q$, 'Prix trop élevé', 'prix au-dessus du plafond refusé');
select th.expect_error($q$select public.carpool_publish('Abidjan','Bouaké', now() + interval '3 days', 3, 400, true)$q$, 'Prix minimum', 'prix sous le minimum refusé');
select th.expect_error($q$select public.carpool_publish('Abidjan','Bouaké', now() + interval '10 minutes', 3, 7000, true)$q$, '30 minutes', 'départ trop proche refusé');
select th.expect_error($q$select public.carpool_publish('Abidjan','Paris', now() + interval '3 days', 3, 7000, true)$q$, 'non disponible', 'trajet hors réseau refusé');
select th.expect_error($q$select public.carpool_publish('Abidjan','Bouaké', now() + interval '3 days', 9, 7000, true)$q$, 'places invalide', 'plus de 8 places refusé');
select th.expect_error($q$insert into public.carpool_trips (driver_id, origin, destination, departs_at, seats_total, price_fcfa) values (th.u(1)::uuid, 'a','b', now(), 1, 500)$q$, 'permission denied', 'écriture directe sur les trajets interdite');
select th.keep('t1', public.carpool_publish('Abidjan','Bouaké', now() + interval '3 days', 3, 7000, true));
select th.keep('t2', public.carpool_publish('Abidjan','Bouaké', now() + interval '3 days', 2, 7000, false));
select th.expect_error($q$update public.carpool_trips set price_fcfa = 500$q$, 'permission denied', 'modification directe du prix interdite');
select th.expect_error($q$select public.carpool_book(th.id('t1'), 1)$q$, 'propre trajet', 'on ne réserve pas son propre trajet');

-- ===== Réservation instantanée, places, solde =====
select th.as_user(th.u(2));
select th.check_true((select count(*) from public.carpool_search('Abidjan','Bouaké', null)) = 2, 'recherche : 2 trajets visibles');
select th.keep('b1', public.carpool_book(th.id('t1'), 2));
select th.check_true(th.bal(2) = 6000, 'Pat : Wallet débité de 14 000 (séquestre)');
select th.check_true((select status from public.carpool_bookings where id = th.id('b1')) = 'confirmee', 'réservation instantanée confirmée');
select th.as_user(th.u(3));
select th.expect_error($q$select public.carpool_book(th.id('t1'), 2)$q$, 'Pas assez de places', 'sur-réservation refusée');
select th.keep('b2', public.carpool_book(th.id('t1'), 1));
select th.check_true((select count(*) from public.carpool_search('Abidjan','Bouaké', null) where id = th.id('t1')) = 0, 'trajet complet : absent de la recherche');
select th.check_true((select count(*) from public.carpool_bookings) = 1, 'Quinn ne voit que sa réservation');
select th.as_user(th.u(1));
select th.check_true((select count(*) from public.carpool_bookings) = 2, 'conductrice : voit les 2 réservations de son trajet');
select th.check_true((select count(*) from public.carpool_trip_passengers(th.id('t1')) where phone is not null) = 2, 'conductrice : passagers confirmés avec téléphone');
select th.as_user(th.u(2));
select th.check_true((select count(*) from public.carpool_trip_passengers(th.id('t1'))) = 0, 'un passager ne voit pas la liste des passagers');
select th.as_user(th.u(4));
select th.expect_error($q$select public.carpool_book(th.id('t2'), 1)$q$, 'Solde Wallet insuffisant', 'solde insuffisant refusé');

-- ===== Réservation sur demande =====
select th.as_user(th.u(9));
select public.wallet_adjust(th.u(2)::uuid, 10000, 'dotation test');
select th.as_user(th.u(2));
select th.keep('b3', public.carpool_book(th.id('t2'), 1));
select th.check_true((select status from public.carpool_bookings where id = th.id('b3')) = 'en_attente' and th.bal(2) = 9000, 'sur demande : en attente, paiement en séquestre');
select th.expect_error($q$select public.carpool_decide_booking(th.id('b3'), true)$q$, 'conducteur du trajet', 'un passager ne décide pas de sa propre demande');
select th.as_user(th.u(1));
select public.carpool_decide_booking(th.id('b3'), false);
select th.as_user(th.u(2));
select th.check_true(th.bal(2) = 16000 and (select status from public.carpool_bookings where id = th.id('b3')) = 'refusee', 'refus du conducteur : remboursement intégral');
select th.keep('b4', public.carpool_book(th.id('t2'), 1));
select th.as_user(th.u(1));
select public.carpool_decide_booking(th.id('b4'), true);
select th.expect_error($q$select public.carpool_decide_booking(th.id('b4'), true)$q$, 'déjà été traitée', 'décision non rejouable');
select th.as_user(th.u(3));
select th.expect_error($q$select public.carpool_cancel_booking(th.id('b4'))$q$, 'introuvable', 'on n''annule pas la réservation d''un autre');

-- ===== Annulation passager : barème dégressif =====
select th.as_user(th.u(2));
select th.check_true(public.carpool_cancel_booking(th.id('b4')) = 7000 and th.bal(2) = 16000, 'plus de 24 h : remboursement de 100 %');
reset role;
update public.carpool_trips set departs_at = now() + interval '12 hours' where id = th.id('t1');
set role authenticated;
select th.as_user(th.u(2));
select th.check_true(public.carpool_cancel_booking(th.id('b1')) = 7000 and th.bal(2) = 23000, 'entre 6 h et 24 h : remboursement de 50 %');
select th.check_true(th.bal(1) = 6440 and (select commission_fcfa from public.carpool_bookings where id = th.id('b1')) = 560, 'part conservée versée à la conductrice, nette de 8 % (6 440 / commission 560)');
reset role;
update public.carpool_trips set departs_at = now() + interval '2 hours' where id = th.id('t1');
set role authenticated;
select th.as_user(th.u(3));
select th.check_true(public.carpool_cancel_booking(th.id('b2')) = 0 and th.bal(3) = 13000, 'moins de 6 h : aucun remboursement');
select th.check_true(th.bal(1) = 12880, 'conductrice : 12 880 cumulés');
select th.expect_error($q$select public.carpool_cancel_booking(th.id('b2'))$q$, 'plus être annulée', 'annulation non rejouable');

-- ===== Fin de trajet : paiement du conducteur net de commission =====
select th.as_user(th.u(1));
select th.keep('t4', public.carpool_publish('Abidjan','Yamoussoukro', now() + interval '2 days', 3, 5000, true));
select th.as_user(th.u(2));
select th.keep('b5', public.carpool_book(th.id('t4'), 2));
select th.as_user(th.u(3));
select th.keep('b6', public.carpool_book(th.id('t4'), 1));
select th.as_user(th.u(1));
select th.expect_error($q$select public.carpool_complete_trip(th.id('t4'))$q$, 'après l''heure de départ', 'impossible de terminer avant le départ');
reset role;
update public.carpool_trips set departs_at = now() - interval '1 hour' where id = th.id('t4');
set role authenticated;
select th.as_user(th.u(2));
select th.expect_error($q$select public.carpool_complete_trip(th.id('t4'))$q$, 'introuvable', 'un passager ne clôture pas le trajet');
select th.expect_error($q$select public.carpool_cancel_booking(th.id('b5'))$q$, 'déjà parti', 'annulation impossible après le départ');
select th.as_user(th.u(1));
select th.check_true(public.carpool_complete_trip(th.id('t4')) = 13800 and th.bal(1) = 26680, 'trajet terminé : 13 800 versés (15 000 − 8 %)');
select th.check_true((select sum(commission_fcfa) from public.carpool_bookings where trip_id = th.id('t4')) = 1200, 'commission Transvia : 1 200');
select th.expect_error($q$select public.carpool_complete_trip(th.id('t4'))$q$, 'déjà clôturé', 'clôture non rejouable');

-- ===== Annulation du trajet par le conducteur =====
select th.keep('t5', public.carpool_publish('Abidjan','Yamoussoukro', now() + interval '5 days', 2, 5000, true));
select th.as_user(th.u(2));
select th.keep('b7', public.carpool_book(th.id('t5'), 1));
select th.as_user(th.u(1));
select public.carpool_cancel_trip(th.id('t5'));
select th.as_user(th.u(2));
select th.check_true(th.bal(2) = 13000 and (select status from public.carpool_bookings where id = th.id('b7')) = 'annulee_conducteur', 'trajet annulé : passager remboursé à 100 %');
select th.expect_error($q$select public.carpool_book(th.id('t5'), 1)$q$, 'indisponible', 'trajet annulé non réservable');

-- ===== Compte bloqué, anonyme, cohérence =====
reset role;
update public.profiles set status = 'bloque' where id = th.u(4)::uuid;
set role authenticated;
select th.as_user(th.u(4));
select th.expect_error($q$select public.carpool_book(th.id('t2'), 1)$q$, 'bloqué', 'compte bloqué : réservation refusée');
reset role;
set role anon;
select th.as_user(null);
select th.expect_error($q$select * from public.carpool_search(null, null, null)$q$, 'permission denied', 'anonyme : recherche interdite');
select th.check_true((select count(*) from public.carpool_trips) = 0 and (select count(*) from public.carpool_bookings) = 0, 'anonyme : aucun trajet ni réservation lisibles');
reset role;
select th.check_true(
  not exists (select 1 from public.wallets w where w.balance_fcfa <> (select coalesce(sum(e.amount_fcfa), 0) from public.wallet_entries e where e.profile_id = w.profile_id)),
  'cohérence globale : chaque solde = somme de son journal');
select th.check_true(th.bal(2) = 13000 and th.bal(3) = 8000 and th.bal(1) = 26680 and th.bal(4) = 1000, 'soldes finaux cohérents');
\echo === TOUS LES TESTS DU LOT 2 PASSENT ===
