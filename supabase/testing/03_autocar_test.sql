-- Tests réels du Lot 3 (Autocar). 
set client_min_messages to notice;
reset role;
drop schema if exists th cascade;
create schema th;
grant usage on schema th to anon, authenticated;

create function th.u(n int) returns text language sql immutable as $$ select '00000000-0000-0000-0000-0000000000e' || n::text $$;
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


-- Comptes : 1 Compagnie, 2 Chauffeur, 3 Pax A, 4 Pax B, 5 Pax C (sans fonds), 9 admin
insert into auth.users (id, email, raw_user_meta_data)
select th.u(n)::uuid, 'e' || n || '@test.ci', jsonb_build_object('full_name', nm, 'phone', '+22508000000' || n)
from (values (1,'Compagnie UTB'),(2,'Chauffeur Brahima'),(3,'Pax A'),(4,'Pax B'),(5,'Pax C'),(9,'Admin3')) v(n, nm);
update public.profiles set staff_role = 'admin' where id = th.u(9)::uuid;

set role authenticated;
select th.as_user(th.u(9));
select public.wallet_adjust(th.u(3)::uuid, 100000, 'dotation test');
select public.wallet_adjust(th.u(4)::uuid, 100000, 'dotation test');

-- ===== Activation du rôle Compagnie (Lot 1) =====
select th.as_user(th.u(3));
select th.expect_error($q$select public.bus_register_company('Pirate', null)$q$, 'Rôle Compagnie', 'sans rôle activé : création de compagnie refusée');
select th.as_user(th.u(1));
select public.submit_identity('CNI', 'CI-UTB-12345');
select public.request_role('compagnie', array['Licence de transport','Registre de commerce','Assurance']);
select th.as_user(th.u(9));
select public.decide_identity(th.u(1)::uuid, 'verifie', null);
select public.decide_role(th.u(1)::uuid, 'compagnie', 'actif', null);

-- ===== Compagnie, véhicule, approbation, chauffeur, départ =====
select th.as_user(th.u(1));
select th.expect_error($q$select public.bus_add_vehicle('CI 1111 AB', 'Mercedes', 52)$q$, 'Créez d''abord', 'véhicule impossible sans compagnie');
select th.keep('co', public.bus_register_company('UTB', '+2250700000000'));
select th.keep('v1', public.bus_add_vehicle('ci 4521 ab', 'Mercedes Tourismo', 52));
select th.expect_error($q$select public.bus_add_vehicle('CI 4521 AB', 'Autre', 52)$q$, 'déjà enregistrée', 'plaque unique');
select th.expect_error($q$select public.bus_publish_departure(th.id('v1'), 'Abidjan', 'Bouaké', now() + interval '3 days', now() + interval '3 days 6 hours', 17500)$q$, 'non approuvé', 'départ refusé : véhicule non approuvé');
select th.as_user(th.u(3));
select th.expect_error($q$select public.bus_approve_vehicle(th.id('v1'), true)$q$, 'Réservé', 'un voyageur n''approuve pas un véhicule');
select th.check_true((select count(*) from public.bus_vehicles) = 0, 'un voyageur ne voit pas les véhicules des compagnies');
select th.as_user(th.u(9));
select public.bus_approve_vehicle(th.id('v1'), true);
select th.as_user(th.u(1));
select th.expect_error($q$select public.bus_add_driver('inconnu@test.ci')$q$, 'Aucun compte', 'chauffeur inconnu refusé');
select public.bus_add_driver('E2@test.ci');
select th.expect_error($q$select public.bus_publish_departure(th.id('v1'), 'Abidjan', 'Paris', now() + interval '3 days', now() + interval '3 days 6 hours', 17500)$q$, 'non disponible', 'liaison hors réseau refusée');
select th.expect_error($q$select public.bus_publish_departure(th.id('v1'), 'Abidjan', 'Bouaké', now() + interval '10 minutes', now() + interval '6 hours', 17500)$q$, '30 minutes', 'départ trop proche refusé');
select th.expect_error($q$select public.bus_publish_departure(th.id('v1'), 'Abidjan', 'Bouaké', now() + interval '3 days', now() + interval '3 days 6 hours', 17500, th.u(3)::uuid)$q$, 'non rattaché', 'chauffeur d''une autre compagnie refusé');
select th.keep('d1', public.bus_publish_departure(th.id('v1'), 'Abidjan', 'Bouaké', now() + interval '3 days', now() + interval '3 days 6 hours', 17500, th.u(2)::uuid));
select th.expect_error($q$insert into public.bus_departures (company_id, vehicle_id, origin, destination, departs_at, arrives_at, price_fcfa) values (th.id('co'), th.id('v1'), 'a', 'b', now(), now() + interval '1 hour', 500)$q$, 'permission denied', 'écriture directe sur les départs interdite');

-- ===== Réservation =====
select th.as_user(th.u(3));
select th.check_true((select count(*) from public.bus_search('Abidjan', 'Bouaké', null)) = 1 and (select seats_left from public.bus_search('Abidjan', 'Bouaké', null)) = 52, 'recherche : 1 départ, 52 places');
select th.expect_error($q$select public.bus_book(th.id('d1'), '[]'::jsonb)$q$, 'De 1 à 4', 'aucun siège refusé');
select th.expect_error($q$select public.bus_book(th.id('d1'), '[{"seat":1,"name":"a"},{"seat":2,"name":"b"},{"seat":3,"name":"c"},{"seat":6,"name":"d"},{"seat":7,"name":"e"}]'::jsonb)$q$, 'De 1 à 4', 'plus de 4 sièges refusé');
select th.expect_error($q$select public.bus_book(th.id('d1'), '[{"seat":1,"name":"a"},{"seat":1,"name":"b"}]'::jsonb)$q$, 'en double', 'siège en double refusé');
select th.expect_error($q$select public.bus_book(th.id('d1'), '[{"seat":53,"name":"a"}]'::jsonb)$q$, 'invalide', 'siège hors du véhicule refusé');
select th.expect_error($q$select public.bus_book(th.id('d1'), '[{"seat":1,"name":""}]'::jsonb)$q$, 'Nom du voyageur', 'nom du voyageur obligatoire');
select th.keep('b1', public.bus_book(th.id('d1'), '[{"seat":1,"name":"Aïcha","phone":"+2250700000001"},{"seat":2,"name":"Junior"}]'::jsonb, 1));
select th.check_true(th.bal(3) = 62500 and (select total_fcfa from public.bus_bookings where id = th.id('b1')) = 37500, 'Pax A : 2 sièges (dont 1 fenêtre) + 1 bagage = 37 500, Wallet 62 500');
select th.as_user(th.u(4));
select th.expect_error($q$select public.bus_book(th.id('d1'), '[{"seat":1,"name":"x"}]'::jsonb)$q$, 'vient d''être réservé', 'siège déjà pris refusé');
select th.keep('b2', public.bus_book(th.id('d1'), '[{"seat":4,"name":"Koffi"},{"seat":5,"name":"Awa"}]'::jsonb));
select th.check_true(th.bal(4) = 64000 and public.bus_taken_seats(th.id('d1')) = array[1,2,4,5], 'Pax B : 36 000 ; sièges pris 1, 2, 4, 5');
select th.check_true((select count(*) from public.bus_bookings) = 1 and (select count(*) from public.bus_booking_seats) = 2, 'Pax B ne voit que son billet');
select th.as_user(th.u(5));
select th.expect_error($q$select public.bus_book(th.id('d1'), '[{"seat":20,"name":"Pauvre"}]'::jsonb)$q$, 'Solde Wallet insuffisant', 'solde insuffisant refusé');

-- ===== Annulation : barème et remise en vente =====
select th.as_user(th.u(3));
select th.check_true(public.bus_cancel_booking(th.id('b1')) = 37500 and th.bal(3) = 100000, 'plus de 24 h : remboursement de 100 % au Wallet');
select th.check_true(public.bus_taken_seats(th.id('d1')) = array[4,5] and (select seats_left from public.bus_search('Abidjan', 'Bouaké', null)) = 50, 'sièges annulés remis en vente');
select th.expect_error($q$select public.bus_cancel_booking(th.id('b1'))$q$, 'ne peut plus', 'annulation non rejouable');
reset role;
update public.bus_departures set departs_at = now() + interval '12 hours', arrives_at = now() + interval '18 hours' where id = th.id('d1');
set role authenticated;
select th.as_user(th.u(4));
select th.check_true(public.bus_cancel_booking(th.id('b2')) = 18000 and th.bal(4) = 82000, 'entre 6 h et 24 h : remboursement de 50 %');
select th.as_user(th.u(1));
select th.check_true(th.bal(1) = 16560 and (select commission_fcfa from public.bus_bookings where id = th.id('b2')) = 1440, 'part conservée versée à la compagnie, nette de 8 % (16 560)');

-- ===== Nouvelles réservations, embarquement, retard =====
select th.as_user(th.u(3));
select th.keep('b3', public.bus_book(th.id('d1'), '[{"seat":10,"name":"Aïcha"}]'::jsonb));
select th.as_user(th.u(4));
select th.keep('b4', public.bus_book(th.id('d1'), '[{"seat":11,"name":"Koffi"}]'::jsonb));
select th.check_true(th.bal(3) = 82500 and th.bal(4) = 64500, 'Wallets : 82 500 et 64 500');
select th.as_user(th.u(2));
select th.expect_error($q$select public.bus_board(th.id('d1'), (select ref from public.bus_bookings where id = th.id('b3')))$q$, '2 h avant', 'embarquement fermé plus de 2 h avant');
reset role;
update public.bus_departures set departs_at = now() + interval '1 hour' where id = th.id('d1');
set role authenticated;
select th.as_user(th.u(2));
select th.check_true((select count(*) from public.bus_manifest(th.id('d1'))) = 2, 'manifeste du chauffeur : 2 voyageurs (annulés exclus)');
select th.check_true(public.bus_board(th.id('d1'), (select ref from public.bus_bookings where id = th.id('b3'))) = 'Valide', 'embarquement : billet valide');
select th.expect_error($q$select public.bus_board(th.id('d1'), (select ref from public.bus_bookings where id = th.id('b3')))$q$, 'déjà embarqué', 'billet déjà embarqué refusé');
select th.expect_error($q$select public.bus_board(th.id('d1'), (select ref from public.bus_bookings where id = th.id('b2')))$q$, 'annulé', 'billet annulé refusé');
select th.expect_error($q$select public.bus_board(th.id('d1'), 'TVB-FAUX0000')$q$, 'refusé', 'billet inconnu refusé');
select th.as_user(th.u(3));
select th.expect_error($q$select public.bus_board(th.id('d1'), 'X')$q$, 'Réservé', 'un voyageur ne peut pas embarquer');
select th.expect_error($q$select public.bus_report_delay(th.id('d1'), 30)$q$, 'Réservé', 'un voyageur ne signale pas de retard');
select th.expect_error($q$select public.bus_cancel_booking(th.id('b3'))$q$, 'ne peut plus', 'billet embarqué : annulation refusée');
select th.check_true((select count(*) from public.bus_manifest(th.id('d1'))) = 0, 'un voyageur ne voit pas le manifeste');
select th.as_user(th.u(2));
select public.bus_report_delay(th.id('d1'), 25);
select th.as_user(th.u(3));
select th.check_true((select delay_min from public.bus_search('Abidjan', 'Bouaké', null)) = 25, 'le retard de 25 min est visible côté voyageur');

-- ===== Départ et arrivée =====
select th.as_user(th.u(2));
select th.expect_error($q$select public.bus_complete_departure(th.id('d1'))$q$, 'démarré', 'impossible de terminer avant de démarrer');
select public.bus_start_departure(th.id('d1'));
select th.expect_error($q$select public.bus_start_departure(th.id('d1'))$q$, 'déjà démarré', 'double démarrage refusé');
select th.expect_error($q$select public.bus_board(th.id('d1'), (select ref from public.bus_bookings where id = th.id('b4')))$q$, 'fermé', 'embarquement impossible après le départ');
select th.check_true(public.bus_complete_departure(th.id('d1')) = 32200, 'arrivée : 32 200 versés à la compagnie (2 × 17 500 − 8 %)');
select th.check_true((select status from public.bus_bookings where id = th.id('b3')) = 'arrive' and (select status from public.bus_bookings where id = th.id('b4')) = 'no_show', 'embarqué = arrivé ; absent = no_show (distincts)');
select th.as_user(th.u(1));
select th.check_true(th.bal(1) = 48760, 'compagnie : 48 760 au total');

-- ===== Annulation d'un départ par la compagnie =====
select th.keep('d2', public.bus_publish_departure(th.id('v1'), 'Abidjan', 'Yamoussoukro', now() + interval '5 days', now() + interval '5 days 4 hours', 17500));
select th.as_user(th.u(3));
select th.keep('b5', public.bus_book(th.id('d2'), '[{"seat":3,"name":"Aïcha"}]'::jsonb));
select th.as_user(th.u(1));
select public.bus_cancel_departure(th.id('d2'));
select th.as_user(th.u(3));
select th.check_true(th.bal(3) = 82500 and (select status from public.bus_bookings where id = th.id('b5')) = 'annule_compagnie', 'départ annulé par la compagnie : remboursement intégral');
select th.expect_error($q$select public.bus_book(th.id('d2'), '[{"seat":3,"name":"x"}]'::jsonb)$q$, 'indisponible', 'départ annulé non réservable');

-- ===== Droits de lecture, anonyme, cohérence =====
select th.as_user(th.u(4));
select th.check_true((select count(*) from public.bus_bookings where passenger_id <> th.u(4)::uuid) = 0, 'Pax B ne voit jamais les billets d''un autre');
reset role;
set role anon;
select th.as_user(null);
select th.expect_error($q$select * from public.bus_search(null, null, null)$q$, 'permission denied', 'anonyme : recherche interdite');
select th.check_true((select count(*) from public.bus_departures) = 0 and (select count(*) from public.bus_bookings) = 0, 'anonyme : rien de lisible');
reset role;
select th.check_true(
  not exists (select 1 from public.wallets w where w.balance_fcfa <> (select coalesce(sum(e.amount_fcfa), 0) from public.wallet_entries e where e.profile_id = w.profile_id)),
  'cohérence globale : chaque solde = somme de son journal');
select th.check_true(th.bal(3) = 82500 and th.bal(4) = 64500 and th.bal(1) = 48760, 'soldes finaux cohérents');
\echo === TOUS LES TESTS DU LOT 3 PASSENT ===
