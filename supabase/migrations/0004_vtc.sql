-- Lot 4 — VTC : commande immédiate, chauffeurs en ligne, code de prise en charge,
-- paiement Wallet en séquestre, commission 8 %, notation.
-- Hypothèses à valider : tarif 600 + 250 FCFA/km (min 1 000), multiplicateurs de catégorie,
-- frais d'annulation 500 FCFA (course acceptée) / 1 000 FCFA (chauffeur arrivé), expiration 10 min.

create type vtc_category as enum ('eco', 'standard', 'confort', 'premium', 'xl', 'pmr');
create type vtc_ride_status as enum ('demande', 'acceptee', 'arrivee', 'en_cours', 'terminee',
                                     'annulee_passager', 'annulee_chauffeur', 'expiree');

create table public.vtc_zones (
  name text primary key,
  lat double precision not null,
  lon double precision not null
);
insert into public.vtc_zones values
  ('Plateau', 5.3197, -4.0161), ('Adjamé', 5.3600, -4.0230), ('Cocody', 5.3540, -3.9870),
  ('Riviera', 5.3380, -3.9560), ('Angré', 5.3980, -3.9960), ('Marcory', 5.3030, -3.9930),
  ('Treichville', 5.2970, -4.0120), ('Koumassi', 5.2900, -3.9500), ('Port-Bouët', 5.2540, -3.9300),
  ('Yopougon', 5.3400, -4.0870), ('Abobo', 5.4200, -4.0200), ('Bingerville', 5.3550, -3.8870);

create table public.vtc_vehicles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id),
  plate text not null unique,
  model text not null,
  category vtc_category not null default 'standard',
  seats int not null default 4 check (seats between 2 and 9),
  approved boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.vtc_drivers (
  profile_id uuid primary key references public.profiles(id),
  vehicle_id uuid references public.vtc_vehicles(id),
  online boolean not null default false,
  zone text references public.vtc_zones(name),
  updated_at timestamptz not null default now()
);

create table public.vtc_rides (
  id uuid primary key default gen_random_uuid(),
  ref text not null unique,
  passenger_id uuid not null references public.profiles(id),
  driver_id uuid references public.profiles(id),
  vehicle_id uuid references public.vtc_vehicles(id),
  category vtc_category not null,
  pickup text not null references public.vtc_zones(name),
  dropoff text not null references public.vtc_zones(name),
  distance_km numeric(6,1) not null,
  price_fcfa int not null check (price_fcfa >= 1000),
  pin text not null,
  status vtc_ride_status not null default 'demande',
  refunded_fcfa int not null default 0,
  driver_net_fcfa int not null default 0,
  commission_fcfa int not null default 0,
  rating int check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (pickup <> dropoff)
);
create index vtc_rides_open_idx on public.vtc_rides (category, created_at) where status = 'demande';
create index vtc_rides_passenger_idx on public.vtc_rides (passenger_id, created_at desc);
create index vtc_rides_driver_idx on public.vtc_rides (driver_id, created_at desc);
-- un passager n'a qu'une course active à la fois ; un chauffeur aussi
create unique index vtc_one_active_passenger on public.vtc_rides (passenger_id) where status in ('demande','acceptee','arrivee','en_cours');
create unique index vtc_one_active_driver on public.vtc_rides (driver_id) where status in ('acceptee','arrivee','en_cours');

-- ---------- Internes ----------
create or replace function public.vtc_km(p_a text, p_b text) returns numeric
language sql stable set search_path = public as $$
  select round((2 * 6371 * asin(sqrt(
      power(sin(radians(b.lat - a.lat) / 2), 2) +
      cos(radians(a.lat)) * cos(radians(b.lat)) * power(sin(radians(b.lon - a.lon) / 2), 2))) * 1.3)::numeric, 1)
  from public.vtc_zones a, public.vtc_zones b where a.name = p_a and b.name = p_b
$$;

create or replace function public.vtc_price(p_a text, p_b text, p_cat vtc_category) returns int
language sql stable set search_path = public as $$
  select greatest(1000, (round((600 + 250 * public.vtc_km(p_a, p_b)) *
    case p_cat when 'eco' then 0.85 when 'standard' then 1 when 'confort' then 1.3 when 'premium' then 1.8
               when 'xl' then 1.6 else 1 end / 100) * 100)::int)
$$;

-- règlement d'une course : remboursement passager + paiement net du chauffeur
create or replace function public.vtc_settle(p_ride uuid, p_refund int, p_status vtc_ride_status) returns void
language plpgsql security definer set search_path = public as $$
declare r public.vtc_rides; v_retained int; v_comm int := 0; v_net int := 0; v_label text;
begin
  select * into r from public.vtc_rides where id = p_ride for update;
  v_label := 'VTC ' || r.pickup || ' → ' || r.dropoff || ' (' || r.ref || ')';
  if p_refund > 0 then
    perform public.wallet_post(r.passenger_id, p_refund, 'remboursement', 'Remboursement — ' || v_label, auth.uid());
  end if;
  v_retained := r.price_fcfa - p_refund;
  if v_retained > 0 and r.driver_id is not null then
    v_comm := round(v_retained * 0.08);
    v_net := v_retained - v_comm;
    perform public.wallet_post(r.driver_id, v_net, 'revenu', v_label, auth.uid());
  elsif v_retained > 0 then
    -- aucun chauffeur : tout est rendu
    perform public.wallet_post(r.passenger_id, v_retained, 'remboursement', 'Remboursement — ' || v_label, auth.uid());
    p_refund := r.price_fcfa;
  end if;
  update public.vtc_rides set status = p_status, refunded_fcfa = p_refund, driver_net_fcfa = v_net,
         commission_fcfa = v_comm, updated_at = now() where id = p_ride;
end;
$$;
revoke all on function public.vtc_settle(uuid, int, vtc_ride_status) from public, anon, authenticated;

-- ---------- Chauffeur ----------
create or replace function public.vtc_add_vehicle(p_plate text, p_model text, p_category vtc_category, p_seats int) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not exists (select 1 from public.profile_roles where profile_id = v_uid and status = 'actif' and role in ('chauffeur_vtc','flotte_vtc')) then
    raise exception 'Rôle Chauffeur VTC non activé : demandez-le depuis Mon compte';
  end if;
  if coalesce(trim(p_plate), '') = '' or coalesce(trim(p_model), '') = '' then raise exception 'Plaque et modèle obligatoires'; end if;
  insert into public.vtc_vehicles (owner_id, plate, model, category, seats)
  values (v_uid, upper(trim(p_plate)), trim(p_model), p_category, p_seats) returning id into v_id;
  return v_id;
exception when unique_violation then raise exception 'Cette plaque est déjà enregistrée';
end;
$$;

create or replace function public.vtc_approve_vehicle(p_vehicle uuid, p_approved boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_moderator() then raise exception 'Réservé à l''équipe Transvia'; end if;
  update public.vtc_vehicles set approved = p_approved where id = p_vehicle;
  if not found then raise exception 'Véhicule introuvable'; end if;
  if not p_approved then
    update public.vtc_drivers set online = false where vehicle_id = p_vehicle;
  end if;
  perform public.log_admin('vtc ' || case when p_approved then 'véhicule approuvé' else 'approbation retirée' end, null, p_vehicle::text);
end;
$$;

create or replace function public.vtc_set_online(p_online boolean, p_vehicle uuid, p_zone text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not exists (select 1 from public.profile_roles where profile_id = v_uid and status = 'actif' and role in ('chauffeur_vtc','flotte_vtc')) then
    raise exception 'Rôle Chauffeur VTC non activé';
  end if;
  if not exists (select 1 from public.profiles where id = v_uid and status = 'actif') then raise exception 'Compte bloqué'; end if;
  if p_online then
    if not exists (select 1 from public.vtc_vehicles where id = p_vehicle and owner_id = v_uid and approved) then
      raise exception 'Choisissez un véhicule approuvé par Transvia';
    end if;
    if not exists (select 1 from public.vtc_zones where name = p_zone) then raise exception 'Zone inconnue'; end if;
  elsif exists (select 1 from public.vtc_rides where driver_id = v_uid and status in ('acceptee','arrivee','en_cours')) then
    raise exception 'Terminez votre course en cours avant de passer hors ligne';
  end if;
  insert into public.vtc_drivers (profile_id, vehicle_id, online, zone, updated_at)
  values (v_uid, case when p_online then p_vehicle end, p_online, case when p_online then p_zone end, now())
  on conflict (profile_id) do update set vehicle_id = excluded.vehicle_id, online = excluded.online,
    zone = excluded.zone, updated_at = now();
end;
$$;

-- ---------- Passager ----------
create or replace function public.vtc_quote(p_pickup text, p_dropoff text)
returns table (category vtc_category, price_fcfa int, distance_km numeric)
language sql stable security definer set search_path = public as $$
  select c, public.vtc_price(p_pickup, p_dropoff, c), public.vtc_km(p_pickup, p_dropoff)
  from unnest(enum_range(null::vtc_category)) c
  where auth.uid() is not null and p_pickup <> p_dropoff
$$;

-- demandes expirées (10 min sans chauffeur) : remboursement intégral
create or replace function public.vtc_sweep() returns int
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  for r in select id from public.vtc_rides where status = 'demande' and created_at < now() - interval '10 minutes' for update skip locked loop
    perform public.vtc_settle(r.id, (select price_fcfa from public.vtc_rides where id = r.id), 'expiree');
    n := n + 1;
  end loop;
  return n;
end;
$$;

create or replace function public.vtc_request(p_pickup text, p_dropoff text, p_category vtc_category) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_price int; v_km numeric; v_ref text; v_pin text; v_id uuid; v_bal bigint;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and status = 'actif') then raise exception 'Compte bloqué'; end if;
  if p_pickup = p_dropoff then raise exception 'Départ et arrivée identiques'; end if;
  if not exists (select 1 from public.vtc_zones where name = p_pickup) or not exists (select 1 from public.vtc_zones where name = p_dropoff) then
    raise exception 'Zone inconnue';
  end if;
  perform public.vtc_sweep();
  if exists (select 1 from public.vtc_rides where passenger_id = v_uid and status in ('demande','acceptee','arrivee','en_cours')) then
    raise exception 'Vous avez déjà une course en cours';
  end if;
  v_km := public.vtc_km(p_pickup, p_dropoff);
  v_price := public.vtc_price(p_pickup, p_dropoff, p_category);
  select balance_fcfa into v_bal from public.wallets where profile_id = v_uid;
  if v_bal is null or v_bal < v_price then raise exception 'Solde Wallet insuffisant : il faut % FCFA', v_price; end if;
  v_ref := 'TVV-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
  v_pin := lpad((floor(random() * 10000))::int::text, 4, '0');
  perform public.wallet_post(v_uid, -v_price, 'paiement', 'VTC ' || p_pickup || ' → ' || p_dropoff || ' (' || v_ref || ')', v_uid);
  insert into public.vtc_rides (ref, passenger_id, category, pickup, dropoff, distance_km, price_fcfa, pin)
  values (v_ref, v_uid, p_category, p_pickup, p_dropoff, v_km, v_price, v_pin) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.vtc_cancel_ride(p_ride uuid) returns int
language plpgsql security definer set search_path = public as $$
declare r public.vtc_rides; v_fee int; v_refund int;
begin
  select * into r from public.vtc_rides where id = p_ride for update;
  if not found or r.passenger_id is distinct from auth.uid() then raise exception 'Course introuvable'; end if;
  if r.status not in ('demande','acceptee','arrivee') then raise exception 'Cette course ne peut plus être annulée'; end if;
  v_fee := case r.status when 'demande' then 0 when 'acceptee' then 500 else 1000 end;
  v_refund := r.price_fcfa - v_fee;
  perform public.vtc_settle(p_ride, v_refund, 'annulee_passager');
  return v_refund;
end;
$$;

create or replace function public.vtc_rate(p_ride uuid, p_rating int, p_comment text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'Note de 1 à 5'; end if;
  update public.vtc_rides set rating = p_rating, comment = nullif(trim(coalesce(p_comment, '')), ''), updated_at = now()
  where id = p_ride and passenger_id = auth.uid() and status = 'terminee' and rating is null;
  if not found then raise exception 'Course introuvable ou déjà notée'; end if;
end;
$$;

-- ---------- Chauffeur : courses ----------
create or replace function public.vtc_open_requests()
returns table (id uuid, ref text, category vtc_category, pickup text, dropoff text, distance_km numeric, price_fcfa int, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  perform public.vtc_sweep();
  return query
  select r.id, r.ref, r.category, r.pickup, r.dropoff, r.distance_km, r.price_fcfa, r.created_at
  from public.vtc_rides r
  join public.vtc_drivers d on d.profile_id = auth.uid() and d.online
  join public.vtc_vehicles v on v.id = d.vehicle_id and v.approved
  where r.status = 'demande' and r.category = v.category
  order by (r.pickup = d.zone) desc, r.created_at
  limit 20;
end;
$$;

create or replace function public.vtc_accept(p_ride uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); r public.vtc_rides; d public.vtc_drivers;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  select * into d from public.vtc_drivers where profile_id = v_uid;
  if not found or not d.online or d.vehicle_id is null then raise exception 'Passez en ligne avec un véhicule approuvé'; end if;
  if not exists (select 1 from public.vtc_vehicles where id = d.vehicle_id and approved and owner_id = v_uid) then raise exception 'Véhicule non approuvé'; end if;
  select * into r from public.vtc_rides where id = p_ride for update;
  if not found or r.status <> 'demande' then raise exception 'Course déjà prise ou annulée'; end if;
  if r.category <> (select category from public.vtc_vehicles where id = d.vehicle_id) then raise exception 'Catégorie incompatible avec votre véhicule'; end if;
  if exists (select 1 from public.vtc_rides where driver_id = v_uid and status in ('acceptee','arrivee','en_cours')) then
    raise exception 'Vous avez déjà une course en cours';
  end if;
  update public.vtc_rides set driver_id = v_uid, vehicle_id = d.vehicle_id, status = 'acceptee', updated_at = now() where id = p_ride;
end;
$$;

create or replace function public.vtc_arrive(p_ride uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.vtc_rides set status = 'arrivee', updated_at = now()
  where id = p_ride and driver_id = auth.uid() and status = 'acceptee';
  if not found then raise exception 'Course introuvable ou pas à cette étape'; end if;
end;
$$;

create or replace function public.vtc_start(p_ride uuid, p_pin text) returns void
language plpgsql security definer set search_path = public as $$
declare r public.vtc_rides;
begin
  select * into r from public.vtc_rides where id = p_ride and driver_id = auth.uid() for update;
  if not found or r.status <> 'arrivee' then raise exception 'Course introuvable ou chauffeur pas encore arrivé'; end if;
  if r.pin <> trim(coalesce(p_pin, '')) then raise exception 'Code de prise en charge incorrect'; end if;
  update public.vtc_rides set status = 'en_cours', updated_at = now() where id = p_ride;
end;
$$;

create or replace function public.vtc_complete(p_ride uuid) returns int
language plpgsql security definer set search_path = public as $$
declare r public.vtc_rides;
begin
  select * into r from public.vtc_rides where id = p_ride and driver_id = auth.uid() for update;
  if not found or r.status <> 'en_cours' then raise exception 'Course introuvable ou pas en cours'; end if;
  perform public.vtc_settle(p_ride, 0, 'terminee');
  return (select driver_net_fcfa from public.vtc_rides where id = p_ride);
end;
$$;

-- le chauffeur annule : le passager est remboursé en totalité
create or replace function public.vtc_driver_cancel(p_ride uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r public.vtc_rides;
begin
  select * into r from public.vtc_rides where id = p_ride and driver_id = auth.uid() for update;
  if not found or r.status not in ('acceptee','arrivee') then raise exception 'Course introuvable ou ne peut plus être annulée'; end if;
  update public.vtc_rides set driver_id = null where id = p_ride;  -- plus de chauffeur : règlement = remboursement total
  perform public.vtc_settle(p_ride, r.price_fcfa, 'annulee_chauffeur');
end;
$$;

create or replace function public.vtc_driver_rating(p_driver uuid) returns table (avg_rating numeric, rides int)
language sql stable security definer set search_path = public as $$
  select round(avg(rating)::numeric, 2), count(*)::int from public.vtc_rides
  where driver_id = p_driver and rating is not null and auth.uid() is not null
$$;

-- ---------- Droits ----------
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.vtc_add_vehicle(text, text, vtc_category, int), public.vtc_approve_vehicle(uuid, boolean),
  public.vtc_set_online(boolean, uuid, text), public.vtc_quote(text, text), public.vtc_sweep(),
  public.vtc_request(text, text, vtc_category), public.vtc_cancel_ride(uuid), public.vtc_rate(uuid, int, text),
  public.vtc_open_requests(), public.vtc_accept(uuid), public.vtc_arrive(uuid), public.vtc_start(uuid, text),
  public.vtc_complete(uuid), public.vtc_driver_cancel(uuid), public.vtc_driver_rating(uuid)
  to authenticated;
revoke execute on function public.vtc_km(text, text), public.vtc_price(text, text, vtc_category) from public, anon, authenticated;

alter table public.vtc_zones enable row level security;
alter table public.vtc_vehicles enable row level security;
alter table public.vtc_drivers enable row level security;
alter table public.vtc_rides enable row level security;
create policy vtc_zones_select on public.vtc_zones for select to authenticated using (true);
create policy vtc_vehicles_select on public.vtc_vehicles for select to authenticated
  using (owner_id = auth.uid() or public.is_staff()
         or exists (select 1 from public.vtc_rides r where r.vehicle_id = vtc_vehicles.id and r.passenger_id = auth.uid()));
create policy vtc_drivers_select on public.vtc_drivers for select to authenticated using (profile_id = auth.uid() or public.is_staff());
create policy vtc_rides_select on public.vtc_rides for select to authenticated
  using (passenger_id = auth.uid() or driver_id = auth.uid() or public.is_staff());
-- le code de prise en charge n'est lisible que par le passager (jamais par le chauffeur)
revoke select on public.vtc_rides from authenticated;
grant select (id, ref, passenger_id, driver_id, vehicle_id, category, pickup, dropoff, distance_km, price_fcfa, status,
              refunded_fcfa, driver_net_fcfa, commission_fcfa, rating, comment, created_at, updated_at)
  on public.vtc_rides to authenticated;
create or replace function public.vtc_my_pin(p_ride uuid) returns text
language sql stable security definer set search_path = public as $$
  select pin from public.vtc_rides where id = p_ride and passenger_id = auth.uid() and status in ('demande','acceptee','arrivee')
$$;
revoke execute on function public.vtc_my_pin(uuid) from public, anon;
grant execute on function public.vtc_my_pin(uuid) to authenticated;
revoke insert, update, delete on public.vtc_zones, public.vtc_vehicles, public.vtc_drivers, public.vtc_rides from anon, authenticated;
