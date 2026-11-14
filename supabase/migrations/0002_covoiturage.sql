-- Transvia Africa — Lot 2 : Covoiturage (Transvia Carpool, partage de frais entre particuliers).
-- Règles reprises du cahier des charges et de la démo :
--  * seul un compte ayant le rôle ACTIF « conducteur_covoiturage » peut publier ;
--  * prix par place plafonné à 1,4 × le prix suggéré (500 + 18 FCFA/km, arrondi à 100) :
--    c'est un partage de frais, pas un tarif professionnel ;
--  * paiement par le Wallet, mis en séquestre à la réservation ; le conducteur est payé
--    à la fin du trajet, net de la commission Transvia de 8 % ;
--  * annulation passager : 100 % au-delà de 24 h avant le départ, 50 % entre 6 h et 24 h, 0 % en dessous ;
--  * le covoiturage reste strictement séparé de Colis / Fret / transport professionnel.
-- Toute écriture passe par des fonctions « security definer » : aucune écriture directe.

create type carpool_trip_status as enum ('ouvert', 'termine', 'annule');
create type carpool_booking_status as enum (
  'en_attente', 'confirmee', 'refusee', 'annulee_passager', 'annulee_conducteur', 'terminee'
);

-- Distances officielles (Côte d'Ivoire) : la distance ne vient jamais de l'utilisateur.
create table public.carpool_routes (
  city_a text not null,
  city_b text not null,
  distance_km int not null check (distance_km > 0),
  primary key (city_a, city_b),
  check (city_a < city_b)
);
insert into public.carpool_routes (city_a, city_b, distance_km) values
  ('Abidjan', 'Bouaké', 350), ('Abidjan', 'San Pédro', 350), ('Abidjan', 'Yamoussoukro', 240),
  ('Abidjan', 'Korhogo', 630), ('Bouaké', 'Yamoussoukro', 110), ('Bouaké', 'San Pédro', 520),
  ('Bouaké', 'Korhogo', 280), ('San Pédro', 'Yamoussoukro', 430), ('Korhogo', 'Yamoussoukro', 400),
  ('Korhogo', 'San Pédro', 650);

create table public.carpool_trips (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles(id),
  origin text not null,
  destination text not null,
  departs_at timestamptz not null,
  seats_total int not null check (seats_total between 1 and 8),
  price_fcfa int not null check (price_fcfa >= 500),     -- par place
  instant_booking boolean not null default true,
  status carpool_trip_status not null default 'ouvert',
  created_at timestamptz not null default now(),
  check (origin <> destination)
);
create index carpool_trips_search_idx on public.carpool_trips (origin, destination, departs_at) where status = 'ouvert';

create table public.carpool_bookings (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.carpool_trips(id),
  passenger_id uuid not null references public.profiles(id),
  seats int not null check (seats between 1 and 8),
  amount_fcfa int not null check (amount_fcfa > 0),        -- payé à la réservation (séquestre)
  status carpool_booking_status not null,
  refunded_fcfa int not null default 0,
  driver_net_fcfa int not null default 0,
  commission_fcfa int not null default 0,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create unique index carpool_one_active_booking on public.carpool_bookings (trip_id, passenger_id)
  where status in ('en_attente', 'confirmee');
create index carpool_bookings_trip_idx on public.carpool_bookings (trip_id);
create index carpool_bookings_passenger_idx on public.carpool_bookings (passenger_id);

-- ========================= FONCTIONS INTERNES =========================

create or replace function public.carpool_distance(p_a text, p_b text) returns int
language sql stable set search_path = public as $$
  select distance_km from public.carpool_routes where city_a = least(p_a, p_b) and city_b = greatest(p_a, p_b)
$$;

create or replace function public.carpool_suggested_price(p_origin text, p_destination text) returns int
language sql stable set search_path = public as $$
  select (round((500 + public.carpool_distance(p_origin, p_destination) * 18) / 100.0) * 100)::int
$$;

create or replace function public.carpool_seats_left(p_trip uuid) returns int
language sql stable security definer set search_path = public as $$
  select t.seats_total - coalesce((select sum(b.seats) from public.carpool_bookings b
                                   where b.trip_id = t.id and b.status in ('en_attente', 'confirmee', 'terminee')), 0)::int
  from public.carpool_trips t where t.id = p_trip
$$;

-- Rembourse un passager (séquestre) : interne.
create or replace function public.carpool_refund(p_booking uuid, p_refund int, p_status carpool_booking_status) returns void
language plpgsql security definer set search_path = public as $$
declare b public.carpool_bookings; v_retained int; v_commission int; v_net int; v_driver uuid; v_label text;
begin
  select * into b from public.carpool_bookings where id = p_booking for update;
  select driver_id into v_driver from public.carpool_trips where id = b.trip_id;
  v_label := 'Covoiturage ' || (select origin || ' → ' || destination from public.carpool_trips where id = b.trip_id);
  if p_refund > 0 then
    perform public.wallet_post(b.passenger_id, p_refund, 'remboursement', 'Remboursement — ' || v_label, auth.uid());
  end if;
  v_retained := b.amount_fcfa - p_refund;
  v_commission := 0; v_net := 0;
  if v_retained > 0 then            -- part conservée (annulation tardive) : versée au conducteur, nette de commission
    v_commission := round(v_retained * 0.08);
    v_net := v_retained - v_commission;
    perform public.wallet_post(v_driver, v_net, 'revenu', 'Annulation tardive — ' || v_label, auth.uid());
  end if;
  update public.carpool_bookings set status = p_status, refunded_fcfa = p_refund, driver_net_fcfa = v_net,
         commission_fcfa = v_commission, decided_at = now() where id = p_booking;
end;
$$;
revoke all on function public.carpool_refund(uuid, int, carpool_booking_status) from public, anon, authenticated;
revoke all on function public.carpool_distance(text, text) from public, anon, authenticated;
revoke all on function public.carpool_suggested_price(text, text) from public, anon, authenticated;
revoke all on function public.carpool_seats_left(uuid) from public, anon, authenticated;

-- ========================= RPC =========================

create or replace function public.carpool_publish(
  p_origin text, p_destination text, p_departs_at timestamptz, p_seats int, p_price int, p_instant boolean
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_suggested int; v_cap int; v_id uuid;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and status = 'actif') then raise exception 'Compte bloqué'; end if;
  if not exists (select 1 from public.profile_roles where profile_id = v_uid and role = 'conducteur_covoiturage' and status = 'actif') then
    raise exception 'Rôle Conducteur Covoiturage non activé : demandez-le depuis Mon compte';
  end if;
  v_suggested := public.carpool_suggested_price(p_origin, p_destination);
  if v_suggested is null then raise exception 'Trajet non disponible'; end if;
  if p_departs_at < now() + interval '30 minutes' then raise exception 'Le départ doit être dans plus de 30 minutes'; end if;
  if p_seats is null or p_seats < 1 or p_seats > 8 then raise exception 'Nombre de places invalide (1 à 8)'; end if;
  v_cap := round(v_suggested * 1.4);
  if p_price is null or p_price < 500 then raise exception 'Prix minimum : 500 FCFA'; end if;
  if p_price > v_cap then raise exception 'Prix trop élevé : le covoiturage est un partage de frais (maximum % FCFA par place)', v_cap; end if;
  insert into public.carpool_trips (driver_id, origin, destination, departs_at, seats_total, price_fcfa, instant_booking)
  values (v_uid, p_origin, p_destination, p_departs_at, p_seats, p_price, coalesce(p_instant, true))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.carpool_book(p_trip uuid, p_seats int) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); t public.carpool_trips; v_amount int; v_balance bigint; v_id uuid;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and status = 'actif') then raise exception 'Compte bloqué'; end if;
  select * into t from public.carpool_trips where id = p_trip for update;     -- verrou : pas de sur-réservation
  if not found or t.status <> 'ouvert' then raise exception 'Trajet indisponible'; end if;
  if t.driver_id = v_uid then raise exception 'Vous ne pouvez pas réserver votre propre trajet'; end if;
  if t.departs_at <= now() then raise exception 'Ce trajet est déjà parti'; end if;
  if p_seats is null or p_seats < 1 then raise exception 'Nombre de places invalide'; end if;
  if p_seats > public.carpool_seats_left(p_trip) then raise exception 'Pas assez de places disponibles'; end if;
  v_amount := t.price_fcfa * p_seats;
  select balance_fcfa into v_balance from public.wallets where profile_id = v_uid;
  if v_balance is null or v_balance < v_amount then raise exception 'Solde Wallet insuffisant : il faut % FCFA', v_amount; end if;
  perform public.wallet_post(v_uid, -v_amount, 'paiement', 'Covoiturage ' || t.origin || ' → ' || t.destination || ' (' || p_seats || ' place(s))', v_uid);
  insert into public.carpool_bookings (trip_id, passenger_id, seats, amount_fcfa, status)
  values (p_trip, v_uid, p_seats, v_amount, case when t.instant_booking then 'confirmee'::carpool_booking_status else 'en_attente'::carpool_booking_status end)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.carpool_decide_booking(p_booking uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare b public.carpool_bookings; t public.carpool_trips;
begin
  select * into b from public.carpool_bookings where id = p_booking for update;
  if not found then raise exception 'Réservation introuvable'; end if;
  select * into t from public.carpool_trips where id = b.trip_id;
  if t.driver_id is distinct from auth.uid() then raise exception 'Réservé au conducteur du trajet'; end if;
  if b.status <> 'en_attente' then raise exception 'Cette demande a déjà été traitée'; end if;
  if p_accept then
    update public.carpool_bookings set status = 'confirmee', decided_at = now() where id = p_booking;
  else
    perform public.carpool_refund(p_booking, b.amount_fcfa, 'refusee');
  end if;
end;
$$;

create or replace function public.carpool_cancel_booking(p_booking uuid) returns int
language plpgsql security definer set search_path = public as $$
declare b public.carpool_bookings; t public.carpool_trips; v_hours numeric; v_refund int;
begin
  select * into b from public.carpool_bookings where id = p_booking for update;
  if not found or b.passenger_id is distinct from auth.uid() then raise exception 'Réservation introuvable'; end if;
  if b.status not in ('en_attente', 'confirmee') then raise exception 'Cette réservation ne peut plus être annulée'; end if;
  select * into t from public.carpool_trips where id = b.trip_id;
  if t.departs_at <= now() then raise exception 'Le trajet est déjà parti : ouvrez un litige'; end if;
  v_hours := extract(epoch from (t.departs_at - now())) / 3600;
  v_refund := case
    when b.status = 'en_attente' then b.amount_fcfa      -- pas encore acceptée : remboursement intégral
    when v_hours >= 24 then b.amount_fcfa
    when v_hours >= 6 then round(b.amount_fcfa * 0.5)
    else 0 end;
  perform public.carpool_refund(p_booking, v_refund, 'annulee_passager');
  return v_refund;
end;
$$;

create or replace function public.carpool_cancel_trip(p_trip uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t public.carpool_trips; r record;
begin
  select * into t from public.carpool_trips where id = p_trip for update;
  if not found or t.driver_id is distinct from auth.uid() then raise exception 'Trajet introuvable'; end if;
  if t.status <> 'ouvert' then raise exception 'Ce trajet ne peut plus être annulé'; end if;
  for r in select id, amount_fcfa from public.carpool_bookings where trip_id = p_trip and status in ('en_attente', 'confirmee') loop
    perform public.carpool_refund(r.id, r.amount_fcfa, 'annulee_conducteur');
  end loop;
  update public.carpool_trips set status = 'annule' where id = p_trip;
end;
$$;

create or replace function public.carpool_complete_trip(p_trip uuid) returns int
language plpgsql security definer set search_path = public as $$
declare t public.carpool_trips; r record; v_commission int; v_net int; v_total int := 0;
begin
  select * into t from public.carpool_trips where id = p_trip for update;
  if not found or t.driver_id is distinct from auth.uid() then raise exception 'Trajet introuvable'; end if;
  if t.status <> 'ouvert' then raise exception 'Trajet déjà clôturé'; end if;
  if t.departs_at > now() then raise exception 'Le trajet ne peut être terminé qu''après l''heure de départ'; end if;
  for r in select id, amount_fcfa, status from public.carpool_bookings where trip_id = p_trip and status in ('en_attente', 'confirmee') for update loop
    if r.status = 'en_attente' then   -- demande jamais acceptée : remboursée
      perform public.carpool_refund(r.id, r.amount_fcfa, 'refusee');
    else
      v_commission := round(r.amount_fcfa * 0.08);
      v_net := r.amount_fcfa - v_commission;
      perform public.wallet_post(t.driver_id, v_net, 'revenu', 'Covoiturage ' || t.origin || ' → ' || t.destination, auth.uid());
      update public.carpool_bookings set status = 'terminee', driver_net_fcfa = v_net, commission_fcfa = v_commission, decided_at = now() where id = r.id;
      v_total := v_total + v_net;
    end if;
  end loop;
  update public.carpool_trips set status = 'termine' where id = p_trip;
  return v_total;
end;
$$;

-- Recherche publique pour les comptes connectés : les places restantes et le nom du conducteur
-- sont calculés côté serveur (le profil du conducteur n'est pas lisible directement).
create or replace function public.carpool_search(p_origin text, p_destination text, p_day date default null)
returns table (id uuid, origin text, destination text, departs_at timestamptz, price_fcfa int, instant_booking boolean,
               seats_left int, driver_name text, driver_verified boolean)
language sql stable security definer set search_path = public as $$
  select t.id, t.origin, t.destination, t.departs_at, t.price_fcfa, t.instant_booking,
         public.carpool_seats_left(t.id), p.full_name, p.id_verified
  from public.carpool_trips t join public.profiles p on p.id = t.driver_id
  where auth.uid() is not null and t.status = 'ouvert' and t.departs_at > now()
    and (p_origin is null or t.origin = p_origin) and (p_destination is null or t.destination = p_destination)
    and (p_day is null or (t.departs_at at time zone 'Africa/Abidjan')::date = p_day)
    and public.carpool_seats_left(t.id) > 0
  order by t.departs_at
  limit 50
$$;

-- Passagers d'un trajet : visibles uniquement par le conducteur (téléphone seulement si confirmé) ou l'équipe.
create or replace function public.carpool_trip_passengers(p_trip uuid)
returns table (booking_id uuid, passenger_name text, phone text, seats int, status carpool_booking_status)
language sql stable security definer set search_path = public as $$
  select b.id, p.full_name, case when b.status in ('confirmee', 'terminee') then p.phone end, b.seats, b.status
  from public.carpool_bookings b join public.profiles p on p.id = b.passenger_id
  join public.carpool_trips t on t.id = b.trip_id
  where b.trip_id = p_trip and (t.driver_id = auth.uid() or public.is_staff())
  order by b.created_at
$$;

create or replace function public.carpool_price_hint(p_origin text, p_destination text)
returns table (suggested int, cap int)
language sql stable security definer set search_path = public as $$
  select public.carpool_suggested_price(p_origin, p_destination), round(public.carpool_suggested_price(p_origin, p_destination) * 1.4)::int
  where auth.uid() is not null and public.carpool_suggested_price(p_origin, p_destination) is not null
$$;

-- ========================= DROITS =========================
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.carpool_publish(text, text, timestamptz, int, int, boolean),
  public.carpool_book(uuid, int),
  public.carpool_decide_booking(uuid, boolean),
  public.carpool_cancel_booking(uuid),
  public.carpool_cancel_trip(uuid),
  public.carpool_complete_trip(uuid),
  public.carpool_search(text, text, date),
  public.carpool_trip_passengers(uuid),
  public.carpool_price_hint(text, text)
  to authenticated;
-- Les droits du Lot 1 sont repris : on les rétablit (le revoke ci-dessus est global).
grant execute on function
  public.submit_identity(text, text), public.decide_identity(uuid, text, text),
  public.request_role(transvia_role, text[]), public.decide_role(uuid, transvia_role, role_status, text),
  public.wallet_topup_simulated(bigint), public.wallet_adjust(uuid, bigint, text),
  public.is_staff(), public.is_moderator()
  to authenticated;

-- ========================= RLS =========================
alter table public.carpool_routes enable row level security;
alter table public.carpool_trips enable row level security;
alter table public.carpool_bookings enable row level security;

create policy carpool_routes_read on public.carpool_routes for select to anon, authenticated using (true);
create policy carpool_trips_select on public.carpool_trips for select to authenticated using (true);
create policy carpool_bookings_select on public.carpool_bookings for select to authenticated
  using (passenger_id = auth.uid()
         or exists (select 1 from public.carpool_trips t where t.id = trip_id and t.driver_id = auth.uid())
         or public.is_staff());
revoke insert, update, delete on public.carpool_routes, public.carpool_trips, public.carpool_bookings from anon, authenticated;
