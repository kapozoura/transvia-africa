-- Transvia Africa — Lot 3 : Autocar (billetterie interurbaine réelle).
-- Corrige les écarts d'audit du cahier Autocar : inventaire de sièges par départ,
-- paiement et remboursement par le Wallet, statuts « embarqué » et « arrivé » distincts,
-- annulation depuis Mes billets, retard visible côté billet, manifeste réel.
-- Hypothèses à valider avec Moussa : commission Transvia de 8 % (comme le Covoiturage ;
-- non définie dans le cahier), supplément fenêtre 500 FCFA, bagage supplémentaire 2 000 FCFA,
-- barème d'annulation 100 % / 50 % / 0 % (plus de 24 h / 6 à 24 h / moins de 6 h).
-- Toute écriture passe par des fonctions « security definer » ; aucune écriture directe.

create type bus_departure_status as enum ('programme', 'en_route', 'termine', 'annule');
create type bus_booking_status as enum ('confirme', 'embarque', 'arrive', 'no_show', 'annule', 'annule_compagnie');

create table public.bus_companies (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references public.profiles(id),
  name text not null check (length(trim(name)) >= 2),
  phone text,
  created_at timestamptz not null default now()
);

create table public.bus_vehicles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.bus_companies(id),
  plate text not null unique,
  model text not null,
  seats int not null default 52 check (seats between 8 and 60),
  approved boolean not null default false,     -- approbation Transvia obligatoire avant tout départ
  created_at timestamptz not null default now()
);

create table public.bus_drivers (
  company_id uuid not null references public.bus_companies(id),
  profile_id uuid not null references public.profiles(id),
  primary key (company_id, profile_id)
);

create table public.bus_departures (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.bus_companies(id),
  vehicle_id uuid not null references public.bus_vehicles(id),
  driver_id uuid references public.profiles(id),
  origin text not null,
  destination text not null,
  departs_at timestamptz not null,
  arrives_at timestamptz not null,
  price_fcfa int not null check (price_fcfa >= 500),
  status bus_departure_status not null default 'programme',
  delay_min int not null default 0 check (delay_min between 0 and 240),
  created_at timestamptz not null default now(),
  check (origin <> destination), check (arrives_at > departs_at)
);
create index bus_departures_search_idx on public.bus_departures (origin, destination, departs_at) where status = 'programme';

create table public.bus_bookings (
  id uuid primary key default gen_random_uuid(),
  ref text not null unique,
  departure_id uuid not null references public.bus_departures(id),
  passenger_id uuid not null references public.profiles(id),
  status bus_booking_status not null default 'confirme',
  baggage_extra int not null default 0 check (baggage_extra between 0 and 4),
  total_fcfa int not null check (total_fcfa > 0),   -- payé à la réservation (séquestre)
  refunded_fcfa int not null default 0,
  company_net_fcfa int not null default 0,
  commission_fcfa int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index bus_bookings_departure_idx on public.bus_bookings (departure_id);
create index bus_bookings_passenger_idx on public.bus_bookings (passenger_id);

create table public.bus_booking_seats (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bus_bookings(id),
  departure_id uuid not null references public.bus_departures(id),
  seat_no int not null check (seat_no between 1 and 60),
  passenger_name text not null,
  passenger_phone text,
  active boolean not null default true
);
-- Garde-fou ultime contre la double réservation d'un siège.
create unique index bus_one_active_seat on public.bus_booking_seats (departure_id, seat_no) where active;
create index bus_seats_booking_idx on public.bus_booking_seats (booking_id);

-- ========================= FONCTIONS INTERNES =========================

create or replace function public.bus_my_company() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.bus_companies where owner_id = auth.uid()
$$;

create or replace function public.bus_can_run(p_departure uuid) returns boolean   -- propriétaire de la compagnie ou chauffeur affecté
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.bus_departures d join public.bus_companies c on c.id = d.company_id
                 where d.id = p_departure and (c.owner_id = auth.uid() or d.driver_id = auth.uid()))
$$;

create or replace function public.bus_seats_left(p_departure uuid) returns int
language sql stable security definer set search_path = public as $$
  select v.seats - (select count(*) from public.bus_booking_seats s where s.departure_id = d.id and s.active)::int
  from public.bus_departures d join public.bus_vehicles v on v.id = d.vehicle_id where d.id = p_departure
$$;

-- Règle un billet : rembourse p_refund au passager, verse le reste à la compagnie (net de 8 %).
create or replace function public.bus_settle(p_booking uuid, p_refund int, p_status bus_booking_status, p_release boolean) returns void
language plpgsql security definer set search_path = public as $$
declare b public.bus_bookings; d public.bus_departures; v_owner uuid; v_retained int; v_commission int := 0; v_net int := 0; v_label text;
begin
  select * into b from public.bus_bookings where id = p_booking for update;
  select * into d from public.bus_departures where id = b.departure_id;
  select owner_id into v_owner from public.bus_companies where id = d.company_id;
  v_label := 'Autocar ' || d.origin || ' → ' || d.destination || ' (' || b.ref || ')';
  if p_refund > 0 then
    perform public.wallet_post(b.passenger_id, p_refund, 'remboursement', 'Remboursement — ' || v_label, auth.uid());
  end if;
  v_retained := b.total_fcfa - p_refund;
  if v_retained > 0 then
    v_commission := round(v_retained * 0.08);
    v_net := v_retained - v_commission;
    perform public.wallet_post(v_owner, v_net, 'revenu', v_label, auth.uid());
  end if;
  update public.bus_bookings set status = p_status, refunded_fcfa = p_refund, company_net_fcfa = v_net,
         commission_fcfa = v_commission, updated_at = now() where id = p_booking;
  if p_release then update public.bus_booking_seats set active = false where booking_id = p_booking; end if;
end;
$$;
revoke all on function public.bus_seats_left(uuid), public.bus_settle(uuid, int, bus_booking_status, boolean) from public, anon, authenticated;

-- ========================= COMPAGNIE =========================

create or replace function public.bus_register_company(p_name text, p_phone text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not exists (select 1 from public.profile_roles where profile_id = v_uid and role = 'compagnie' and status = 'actif') then
    raise exception 'Rôle Compagnie de transport non activé : demandez-le depuis Mon compte';
  end if;
  insert into public.bus_companies (owner_id, name, phone) values (v_uid, trim(p_name), nullif(trim(coalesce(p_phone, '')), ''))
  on conflict (owner_id) do update set name = excluded.name, phone = excluded.phone
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.bus_add_vehicle(p_plate text, p_model text, p_seats int) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_company uuid := public.bus_my_company(); v_id uuid;
begin
  if v_company is null then raise exception 'Créez d''abord votre compagnie'; end if;
  if coalesce(trim(p_plate), '') = '' or coalesce(trim(p_model), '') = '' then raise exception 'Plaque et modèle obligatoires'; end if;
  insert into public.bus_vehicles (company_id, plate, model, seats) values (v_company, upper(trim(p_plate)), trim(p_model), p_seats)
  returning id into v_id;
  return v_id;
exception when unique_violation then raise exception 'Cette plaque est déjà enregistrée';
end;
$$;

create or replace function public.bus_approve_vehicle(p_vehicle uuid, p_approved boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_moderator() then raise exception 'Réservé à l''équipe Transvia'; end if;
  update public.bus_vehicles set approved = p_approved where id = p_vehicle;
  if not found then raise exception 'Véhicule introuvable'; end if;
  perform public.log_admin('autocar ' || case when p_approved then 'approuvé' else 'approbation retirée' end, null, p_vehicle::text);
end;
$$;

create or replace function public.bus_add_driver(p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare v_company uuid := public.bus_my_company(); v_profile uuid;
begin
  if v_company is null then raise exception 'Créez d''abord votre compagnie'; end if;
  select id into v_profile from auth.users where lower(email) = lower(trim(p_email));
  if v_profile is null then raise exception 'Aucun compte Transvia avec cet e-mail : le chauffeur doit d''abord s''inscrire'; end if;
  insert into public.bus_drivers (company_id, profile_id) values (v_company, v_profile) on conflict do nothing;
end;
$$;

create or replace function public.bus_publish_departure(
  p_vehicle uuid, p_origin text, p_destination text, p_departs_at timestamptz, p_arrives_at timestamptz, p_price int, p_driver uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_company uuid := public.bus_my_company(); v_id uuid;
begin
  if v_company is null then raise exception 'Créez d''abord votre compagnie'; end if;
  if not exists (select 1 from public.bus_vehicles where id = p_vehicle and company_id = v_company) then raise exception 'Véhicule introuvable'; end if;
  if not exists (select 1 from public.bus_vehicles where id = p_vehicle and approved) then raise exception 'Véhicule non approuvé par Transvia'; end if;
  if public.carpool_distance(p_origin, p_destination) is null then raise exception 'Liaison non disponible'; end if;
  if p_departs_at < now() + interval '30 minutes' then raise exception 'Le départ doit être dans plus de 30 minutes'; end if;
  if p_arrives_at <= p_departs_at then raise exception 'L''arrivée doit suivre le départ'; end if;
  if p_price is null or p_price < 500 or p_price > 200000 then raise exception 'Prix de 500 à 200 000 FCFA'; end if;
  if p_driver is not null and not exists (select 1 from public.bus_drivers where company_id = v_company and profile_id = p_driver) then
    raise exception 'Chauffeur non rattaché à votre compagnie';
  end if;
  insert into public.bus_departures (company_id, vehicle_id, driver_id, origin, destination, departs_at, arrives_at, price_fcfa)
  values (v_company, p_vehicle, p_driver, p_origin, p_destination, p_departs_at, p_arrives_at, p_price)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.bus_assign_driver(p_departure uuid, p_driver uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_company uuid := public.bus_my_company();
begin
  if not exists (select 1 from public.bus_departures where id = p_departure and company_id = v_company and status = 'programme') then
    raise exception 'Départ introuvable ou déjà parti';
  end if;
  if p_driver is not null and not exists (select 1 from public.bus_drivers where company_id = v_company and profile_id = p_driver) then
    raise exception 'Chauffeur non rattaché à votre compagnie';
  end if;
  update public.bus_departures set driver_id = p_driver where id = p_departure;
end;
$$;

create or replace function public.bus_cancel_departure(p_departure uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d public.bus_departures; r record;
begin
  select * into d from public.bus_departures where id = p_departure for update;
  if not found or d.company_id is distinct from public.bus_my_company() then raise exception 'Départ introuvable'; end if;
  if d.status <> 'programme' then raise exception 'Ce départ ne peut plus être annulé'; end if;
  for r in select id, total_fcfa from public.bus_bookings where departure_id = p_departure and status = 'confirme' loop
    perform public.bus_settle(r.id, r.total_fcfa, 'annule_compagnie', true);
  end loop;
  update public.bus_departures set status = 'annule' where id = p_departure;
end;
$$;

-- ========================= VOYAGEUR =========================

create or replace function public.bus_search(p_origin text, p_destination text, p_day date default null)
returns table (id uuid, company_name text, origin text, destination text, departs_at timestamptz, arrives_at timestamptz,
               delay_min int, price_fcfa int, seats_left int, vehicle_model text)
language sql stable security definer set search_path = public as $$
  select d.id, c.name, d.origin, d.destination, d.departs_at, d.arrives_at, d.delay_min, d.price_fcfa,
         public.bus_seats_left(d.id), v.model
  from public.bus_departures d join public.bus_companies c on c.id = d.company_id join public.bus_vehicles v on v.id = d.vehicle_id
  where auth.uid() is not null and d.status = 'programme' and d.departs_at > now()
    and (p_origin is null or d.origin = p_origin) and (p_destination is null or d.destination = p_destination)
    and (p_day is null or (d.departs_at at time zone 'Africa/Abidjan')::date = p_day)
    and public.bus_seats_left(d.id) > 0
  order by d.departs_at limit 50
$$;

create or replace function public.bus_taken_seats(p_departure uuid) returns int[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(seat_no order by seat_no), '{}') from public.bus_booking_seats
  where departure_id = p_departure and active and auth.uid() is not null
$$;

-- p_seats : [{ "seat": 7, "name": "Aïcha", "phone": "+225…" }, …] — 4 sièges maximum par réservation.
create or replace function public.bus_book(p_departure uuid, p_seats jsonb, p_baggage_extra int default 0) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.bus_departures; v_cap int; s jsonb; v_n int; v_seat int; v_total int; v_balance bigint; v_id uuid; v_ref text; v_windows int := 0;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and status = 'actif') then raise exception 'Compte bloqué'; end if;
  select * into d from public.bus_departures where id = p_departure for update;     -- verrou : pas de sur-réservation
  if not found or d.status <> 'programme' then raise exception 'Départ indisponible'; end if;
  if d.departs_at <= now() then raise exception 'Ce départ est déjà passé'; end if;
  if jsonb_typeof(p_seats) <> 'array' then raise exception 'Sièges invalides'; end if;
  v_n := jsonb_array_length(p_seats);
  if v_n < 1 or v_n > 4 then raise exception 'De 1 à 4 sièges par réservation'; end if;
  if p_baggage_extra is null or p_baggage_extra < 0 or p_baggage_extra > 4 then raise exception 'Bagages supplémentaires : 0 à 4'; end if;
  select seats into v_cap from public.bus_vehicles where id = d.vehicle_id;
  for s in select * from jsonb_array_elements(p_seats) loop
    v_seat := (s->>'seat')::int;
    if v_seat is null or v_seat < 1 or v_seat > v_cap then raise exception 'Siège % invalide', v_seat; end if;
    if coalesce(trim(s->>'name'), '') = '' then raise exception 'Nom du voyageur obligatoire pour le siège %', v_seat; end if;
    if exists (select 1 from public.bus_booking_seats where departure_id = p_departure and seat_no = v_seat and active) then
      raise exception 'Le siège % vient d''être réservé', v_seat;
    end if;
    if ((v_seat - 1) % 4) + 1 in (1, 4) then v_windows := v_windows + 1; end if;
  end loop;
  if (select count(distinct (e->>'seat')) from jsonb_array_elements(p_seats) e) <> v_n then raise exception 'Siège en double'; end if;
  v_total := d.price_fcfa * v_n + 500 * v_windows + 2000 * p_baggage_extra;
  select balance_fcfa into v_balance from public.wallets where profile_id = v_uid;
  if v_balance is null or v_balance < v_total then raise exception 'Solde Wallet insuffisant : il faut % FCFA', v_total; end if;
  v_ref := 'TVB-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
  perform public.wallet_post(v_uid, -v_total, 'paiement', 'Autocar ' || d.origin || ' → ' || d.destination || ' (' || v_ref || ')', v_uid);
  insert into public.bus_bookings (ref, departure_id, passenger_id, baggage_extra, total_fcfa) values (v_ref, p_departure, v_uid, p_baggage_extra, v_total) returning id into v_id;
  insert into public.bus_booking_seats (booking_id, departure_id, seat_no, passenger_name, passenger_phone)
  select v_id, p_departure, (e->>'seat')::int, trim(e->>'name'), nullif(trim(coalesce(e->>'phone', '')), '') from jsonb_array_elements(p_seats) e;
  return v_id;
end;
$$;

create or replace function public.bus_cancel_booking(p_booking uuid) returns int
language plpgsql security definer set search_path = public as $$
declare b public.bus_bookings; d public.bus_departures; v_hours numeric; v_refund int;
begin
  select * into b from public.bus_bookings where id = p_booking for update;
  if not found or b.passenger_id is distinct from auth.uid() then raise exception 'Billet introuvable'; end if;
  if b.status <> 'confirme' then raise exception 'Ce billet ne peut plus être annulé'; end if;
  select * into d from public.bus_departures where id = b.departure_id;
  if d.status <> 'programme' or d.departs_at <= now() then raise exception 'Le départ est déjà parti'; end if;
  v_hours := extract(epoch from (d.departs_at - now())) / 3600;
  v_refund := case when v_hours >= 24 then b.total_fcfa when v_hours >= 6 then round(b.total_fcfa * 0.5) else 0 end;
  perform public.bus_settle(p_booking, v_refund, 'annule', true);     -- les sièges sont remis en vente
  return v_refund;
end;
$$;

-- ========================= GARE / CHAUFFEUR =========================

-- Embarquement : le chauffeur ou la compagnie saisit (ou scanne) la référence du billet.
create or replace function public.bus_board(p_departure uuid, p_ref text) returns text
language plpgsql security definer set search_path = public as $$
declare d public.bus_departures; b public.bus_bookings;
begin
  if not public.bus_can_run(p_departure) then raise exception 'Réservé au chauffeur ou à la compagnie du départ'; end if;
  select * into d from public.bus_departures where id = p_departure;
  if d.status <> 'programme' then raise exception 'Embarquement fermé'; end if;
  if now() < d.departs_at - interval '2 hours' then raise exception 'Embarquement ouvert 2 h avant le départ'; end if;
  select * into b from public.bus_bookings where ref = upper(trim(p_ref));
  if not found or b.departure_id <> p_departure then raise exception 'Billet refusé : ne correspond pas à ce départ'; end if;
  if b.status = 'embarque' then raise exception 'Billet déjà embarqué'; end if;
  if b.status <> 'confirme' then raise exception 'Billet refusé : annulé'; end if;
  update public.bus_bookings set status = 'embarque', updated_at = now() where id = b.id;
  return 'Valide';
end;
$$;

create or replace function public.bus_report_delay(p_departure uuid, p_minutes int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.bus_can_run(p_departure) then raise exception 'Réservé au chauffeur ou à la compagnie du départ'; end if;
  if p_minutes is null or p_minutes < 0 or p_minutes > 240 then raise exception 'Retard de 0 à 240 minutes'; end if;
  update public.bus_departures set delay_min = p_minutes where id = p_departure and status = 'programme';
  if not found then raise exception 'Départ déjà parti ou introuvable'; end if;
end;
$$;

create or replace function public.bus_start_departure(p_departure uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d public.bus_departures;
begin
  if not public.bus_can_run(p_departure) then raise exception 'Réservé au chauffeur ou à la compagnie du départ'; end if;
  select * into d from public.bus_departures where id = p_departure for update;
  if d.status <> 'programme' then raise exception 'Départ déjà démarré ou clos'; end if;
  if now() < d.departs_at - interval '2 hours' then raise exception 'Trop tôt pour démarrer ce départ'; end if;
  update public.bus_departures set status = 'en_route' where id = p_departure;
end;
$$;

-- Arrivée : les voyageurs embarqués passent « arrivé » ; les absents « no_show » (non remboursés). La compagnie est payée net de 8 %.
create or replace function public.bus_complete_departure(p_departure uuid) returns int
language plpgsql security definer set search_path = public as $$
declare d public.bus_departures; r record; v_total int := 0;
begin
  if not public.bus_can_run(p_departure) then raise exception 'Réservé au chauffeur ou à la compagnie du départ'; end if;
  select * into d from public.bus_departures where id = p_departure for update;
  if d.status <> 'en_route' then raise exception 'Le départ doit d''abord être démarré'; end if;
  for r in select id, status from public.bus_bookings where departure_id = p_departure and status in ('confirme', 'embarque') loop
    perform public.bus_settle(r.id, 0, case when r.status = 'embarque' then 'arrive'::bus_booking_status else 'no_show'::bus_booking_status end, false);
  end loop;
  update public.bus_departures set status = 'termine' where id = p_departure;
  select coalesce(sum(company_net_fcfa), 0) into v_total from public.bus_bookings where departure_id = p_departure and status in ('arrive', 'no_show');
  return v_total;
end;
$$;

create or replace function public.bus_manifest(p_departure uuid)
returns table (booking_ref text, seat_no int, passenger_name text, passenger_phone text, status bus_booking_status, baggage_extra int)
language sql stable security definer set search_path = public as $$
  select b.ref, s.seat_no, s.passenger_name, s.passenger_phone, b.status, b.baggage_extra
  from public.bus_booking_seats s join public.bus_bookings b on b.id = s.booking_id
  where s.departure_id = p_departure and (public.bus_can_run(p_departure) or public.is_staff()) and b.status <> 'annule' and b.status <> 'annule_compagnie'
  order by s.seat_no
$$;

-- ========================= DROITS =========================
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.bus_my_company(), public.bus_can_run(uuid),   -- utilisées par les politiques RLS
  public.bus_register_company(text, text), public.bus_add_vehicle(text, text, int), public.bus_approve_vehicle(uuid, boolean),
  public.bus_add_driver(text), public.bus_publish_departure(uuid, text, text, timestamptz, timestamptz, int, uuid),
  public.bus_assign_driver(uuid, uuid), public.bus_cancel_departure(uuid), public.bus_search(text, text, date),
  public.bus_taken_seats(uuid), public.bus_book(uuid, jsonb, int), public.bus_cancel_booking(uuid), public.bus_board(uuid, text),
  public.bus_report_delay(uuid, int), public.bus_start_departure(uuid), public.bus_complete_departure(uuid), public.bus_manifest(uuid)
  to authenticated;

-- ========================= RLS =========================
alter table public.bus_companies enable row level security;
alter table public.bus_vehicles enable row level security;
alter table public.bus_drivers enable row level security;
alter table public.bus_departures enable row level security;
alter table public.bus_bookings enable row level security;
alter table public.bus_booking_seats enable row level security;

create policy bus_companies_select on public.bus_companies for select to authenticated using (owner_id = auth.uid() or public.is_staff());
create policy bus_vehicles_select on public.bus_vehicles for select to authenticated
  using (public.is_staff() or company_id = public.bus_my_company());
create policy bus_drivers_select on public.bus_drivers for select to authenticated
  using (profile_id = auth.uid() or company_id = public.bus_my_company() or public.is_staff());
create policy bus_departures_select on public.bus_departures for select to authenticated using (true);
create policy bus_bookings_select on public.bus_bookings for select to authenticated
  using (passenger_id = auth.uid() or public.is_staff() or public.bus_can_run(departure_id));
create policy bus_seats_select on public.bus_booking_seats for select to authenticated
  using (public.is_staff() or public.bus_can_run(departure_id)
         or exists (select 1 from public.bus_bookings b where b.id = booking_id and b.passenger_id = auth.uid()));
revoke insert, update, delete on public.bus_companies, public.bus_vehicles, public.bus_drivers, public.bus_departures,
  public.bus_bookings, public.bus_booking_seats from anon, authenticated;
