-- Lot 5 — Colis : envoi entre particuliers (30 kg max) acheminé par un départ Autocar réel.
-- Chaîne : enregistré → déposé en gare → en transit → arrivé → livré (code de retrait), ou annulé.
-- Hypothèses à valider (reprises du cahier Colis) : 1 000 + 12 FCFA/km + 250 FCFA/kg + gabarit,
-- services ×1 / 1,35 / 1,25 / 1,6, assurance 10 / 15 / 20 %, commission compagnie 12 %, capacité 500 kg par départ.

create type colis_size as enum ('petit', 'moyen', 'grand');
create type colis_service as enum ('standard', 'express', 'fragile', 'express_fragile');
create type colis_tier as enum ('standard', 'etendue', 'premium');
create type colis_status as enum ('enregistre', 'depose', 'en_transit', 'arrive', 'livre', 'annule');
create type colis_claim_kind as enum ('retard', 'perdu', 'endommage', 'altere');
create type colis_claim_status as enum ('ouverte', 'indemnisee', 'rejetee');

create table public.colis_parcels (
  id uuid primary key default gen_random_uuid(),
  ref text not null unique,
  sender_id uuid not null references public.profiles(id),
  departure_id uuid not null references public.bus_departures(id),
  recipient_name text not null check (length(trim(recipient_name)) >= 2),
  recipient_phone text not null,
  weight_kg numeric(5,1) not null check (weight_kg > 0 and weight_kg <= 30),
  verified_weight_kg numeric(5,1),
  size colis_size not null,
  service colis_service not null default 'standard',
  tier colis_tier not null default 'standard',
  declared_value_fcfa int not null check (declared_value_fcfa >= 1000),
  transport_fcfa int not null,
  insurance_fcfa int not null,
  total_fcfa int not null,
  status colis_status not null default 'enregistre',
  otp text not null,
  refunded_fcfa int not null default 0,
  company_net_fcfa int not null default 0,
  commission_fcfa int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index colis_sender_idx on public.colis_parcels (sender_id, created_at desc);
create index colis_departure_idx on public.colis_parcels (departure_id);

create table public.colis_events (
  id bigint generated always as identity primary key,
  parcel_id uuid not null references public.colis_parcels(id),
  status colis_status not null,
  actor_id uuid references public.profiles(id),
  note text,
  at timestamptz not null default now()
);
create index colis_events_parcel_idx on public.colis_events (parcel_id, at);

create table public.colis_claims (
  id uuid primary key default gen_random_uuid(),
  parcel_id uuid not null references public.colis_parcels(id),
  claimant_id uuid not null references public.profiles(id),
  kind colis_claim_kind not null,
  description text not null check (length(trim(description)) >= 5),
  status colis_claim_status not null default 'ouverte',
  indemnity_fcfa int not null default 0,
  decision_note text,
  created_at timestamptz not null default now(),
  decided_at timestamptz
);
create unique index colis_one_open_claim on public.colis_claims (parcel_id, kind);

-- ---------- Internes ----------
create or replace function public.colis_tier_cap(p_tier colis_tier) returns int
language sql immutable set search_path = public as $$
  select case p_tier when 'standard' then 50000 when 'etendue' then 200000 else 1000000 end
$$;

create or replace function public.colis_calc(p_km int, p_weight numeric, p_size colis_size, p_service colis_service, p_tier colis_tier)
returns table (transport int, insurance int)
language sql immutable set search_path = public as $$
  with b as (
    select (1000 + 12 * p_km + 250 * p_weight + case p_size when 'petit' then 0 when 'moyen' then 1500 else 3500 end)
           * case p_service when 'standard' then 1 when 'express' then 1.35 when 'fragile' then 1.25 else 1.6 end as raw
  ), t as (select (round(raw / 100) * 100)::int as tr from b)
  select tr, (round(tr * case p_tier when 'standard' then 0.10 when 'etendue' then 0.15 else 0.20 end / 50) * 50)::int from t
$$;

create or replace function public.colis_event(p_parcel uuid, p_status colis_status, p_actor uuid, p_note text) returns void
language sql security definer set search_path = public as $$
  insert into public.colis_events (parcel_id, status, actor_id, note) values (p_parcel, p_status, p_actor, p_note)
$$;

create or replace function public.colis_refund(p_parcel uuid, p_status colis_status, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare c public.colis_parcels;
begin
  select * into c from public.colis_parcels where id = p_parcel for update;
  perform public.wallet_post(c.sender_id, c.total_fcfa, 'remboursement', 'Remboursement colis ' || c.ref, auth.uid());
  update public.colis_parcels set status = p_status, refunded_fcfa = c.total_fcfa, updated_at = now() where id = p_parcel;
  perform public.colis_event(p_parcel, p_status, auth.uid(), p_note);
end;
$$;

revoke all on function public.colis_tier_cap(colis_tier), public.colis_calc(int, numeric, colis_size, colis_service, colis_tier),
  public.colis_event(uuid, colis_status, uuid, text), public.colis_refund(uuid, colis_status, text) from public, anon, authenticated;

-- le départ change d'état : les colis suivent
create or replace function public.colis_on_departure() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.status = old.status then return new; end if;
  if new.status = 'en_route' then
    for r in select id from public.colis_parcels where departure_id = new.id and status = 'enregistre' for update loop
      perform public.colis_refund(r.id, 'annule', 'Colis non déposé avant le départ : remboursé');
    end loop;
    for r in select id from public.colis_parcels where departure_id = new.id and status = 'depose' for update loop
      update public.colis_parcels set status = 'en_transit', updated_at = now() where id = r.id;
      perform public.colis_event(r.id, 'en_transit', null, 'L''autocar a quitté la gare');
    end loop;
  elsif new.status = 'termine' then
    for r in select id from public.colis_parcels where departure_id = new.id and status = 'en_transit' for update loop
      update public.colis_parcels set status = 'arrive', updated_at = now() where id = r.id;
      perform public.colis_event(r.id, 'arrive', null, 'Arrivé en gare : retrait avec le code');
    end loop;
  elsif new.status = 'annule' then
    for r in select id from public.colis_parcels where departure_id = new.id and status in ('enregistre', 'depose') for update loop
      perform public.colis_refund(r.id, 'annule', 'Départ annulé par la compagnie : remboursé');
    end loop;
  end if;
  return new;
end;
$$;
create trigger colis_follow_departure after update of status on public.bus_departures
  for each row execute function public.colis_on_departure();
revoke all on function public.colis_on_departure() from public, anon, authenticated;

-- ---------- Expéditeur ----------
create or replace function public.colis_departures(p_origin text, p_destination text)
returns table (id uuid, company_name text, origin text, destination text, departs_at timestamptz, arrives_at timestamptz,
               delay_min int, km int, kg_left numeric)
language sql stable security definer set search_path = public as $$
  select d.id, c.name, d.origin, d.destination, d.departs_at, d.arrives_at, d.delay_min,
         public.carpool_distance(d.origin, d.destination),
         500 - coalesce((select sum(p.weight_kg) from public.colis_parcels p where p.departure_id = d.id and p.status <> 'annule'), 0)
  from public.bus_departures d join public.bus_companies c on c.id = d.company_id
  where auth.uid() is not null and d.status = 'programme' and d.departs_at > now() + interval '1 hour'
    and (p_origin is null or d.origin = p_origin) and (p_destination is null or d.destination = p_destination)
  order by d.departs_at limit 30
$$;

create or replace function public.colis_quote(p_departure uuid, p_weight numeric, p_size colis_size, p_service colis_service, p_tier colis_tier)
returns table (transport int, insurance int, total int)
language plpgsql stable security definer set search_path = public as $$
declare d public.bus_departures; v_km int;
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  select * into d from public.bus_departures where id = p_departure;
  if not found then raise exception 'Départ introuvable'; end if;
  v_km := public.carpool_distance(d.origin, d.destination);
  if p_weight is null or p_weight <= 0 or p_weight > 30 then raise exception 'Poids de 0,1 à 30 kg (au-delà, utilisez Transvia Fret)'; end if;
  if p_size = 'petit' and p_weight > 5 then raise exception 'Petit colis : 5 kg maximum'; end if;
  if p_size = 'moyen' and p_weight > 15 then raise exception 'Colis moyen : 15 kg maximum'; end if;
  return query select x.transport, x.insurance, x.transport + x.insurance
    from public.colis_calc(v_km, p_weight, p_size, p_service, p_tier) x;
end;
$$;

create or replace function public.colis_create(
  p_departure uuid, p_recipient_name text, p_recipient_phone text, p_weight numeric, p_size colis_size,
  p_service colis_service, p_tier colis_tier, p_declared int, p_forbidden_ack boolean
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); d public.bus_departures; q record; v_phone text; v_ref text; v_otp text; v_id uuid; v_bal bigint; v_used numeric;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and status = 'actif') then raise exception 'Compte bloqué'; end if;
  if p_forbidden_ack is not true then raise exception 'Vous devez certifier que le colis ne contient aucun produit interdit'; end if;
  v_phone := regexp_replace(coalesce(p_recipient_phone, ''), '[ .-]', '', 'g');
  if v_phone !~ '^(\+225|00225)?[0-9]{10}$' then raise exception 'Téléphone du destinataire invalide (10 chiffres)'; end if;
  select * into d from public.bus_departures where id = p_departure for update;
  if not found or d.status <> 'programme' then raise exception 'Départ indisponible'; end if;
  if d.departs_at <= now() + interval '1 hour' then raise exception 'Le dépôt ferme 1 h avant le départ'; end if;
  if p_declared is null or p_declared < 1000 or p_declared > public.colis_tier_cap(p_tier) then
    raise exception 'Valeur déclarée de 1 000 à % FCFA pour cette formule', public.colis_tier_cap(p_tier);
  end if;
  select sum(weight_kg) into v_used from public.colis_parcels where departure_id = p_departure and status <> 'annule';
  if coalesce(v_used, 0) + p_weight > 500 then raise exception 'Capacité colis de ce départ atteinte'; end if;
  select * into q from public.colis_quote(p_departure, p_weight, p_size, p_service, p_tier);
  select balance_fcfa into v_bal from public.wallets where profile_id = v_uid;
  if v_bal is null or v_bal < q.total then raise exception 'Solde Wallet insuffisant : il faut % FCFA', q.total; end if;
  v_ref := 'TVC-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  v_otp := lpad((floor(random() * 1000000))::int::text, 6, '0');
  perform public.wallet_post(v_uid, -q.total, 'paiement', 'Colis ' || d.origin || ' → ' || d.destination || ' (' || v_ref || ')', v_uid);
  insert into public.colis_parcels (ref, sender_id, departure_id, recipient_name, recipient_phone, weight_kg, size, service, tier,
    declared_value_fcfa, transport_fcfa, insurance_fcfa, total_fcfa, otp)
  values (v_ref, v_uid, p_departure, trim(p_recipient_name), v_phone, p_weight, p_size, p_service, p_tier, p_declared,
    q.transport, q.insurance, q.total, v_otp) returning id into v_id;
  perform public.colis_event(v_id, 'enregistre', v_uid, 'Colis enregistré et payé : à déposer en gare');
  return v_id;
end;
$$;

create or replace function public.colis_my_otp(p_parcel uuid) returns text
language sql stable security definer set search_path = public as $$
  select otp from public.colis_parcels where id = p_parcel and sender_id = auth.uid() and status not in ('livre', 'annule')
$$;

-- annulation par l'expéditeur : tant que le colis n'est pas déposé en gare
create or replace function public.colis_cancel(p_parcel uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c public.colis_parcels;
begin
  select * into c from public.colis_parcels where id = p_parcel for update;
  if not found or c.sender_id is distinct from auth.uid() then raise exception 'Colis introuvable'; end if;
  if c.status <> 'enregistre' then raise exception 'Colis déjà pris en charge : annulation impossible'; end if;
  perform public.colis_refund(p_parcel, 'annule', 'Annulé par l''expéditeur : remboursé');
end;
$$;

-- ---------- Suivi public (sans compte) ----------
create or replace function public.colis_track(p_ref text)
returns table (ref text, status colis_status, origin text, destination text, departs_at timestamptz, delay_min int,
               event_status colis_status, event_note text, event_at timestamptz)
language sql stable security definer set search_path = public as $$
  select p.ref, p.status, d.origin, d.destination, d.departs_at, d.delay_min, e.status, e.note, e.at
  from public.colis_parcels p join public.bus_departures d on d.id = p.departure_id
  join public.colis_events e on e.parcel_id = p.id
  where p.ref = upper(trim(p_ref)) order by e.at, e.id
$$;

-- ---------- Compagnie / chauffeur du départ ----------
create or replace function public.colis_receive(p_departure uuid, p_ref text, p_weight numeric) returns void
language plpgsql security definer set search_path = public as $$
declare c public.colis_parcels; d public.bus_departures;
begin
  if not public.bus_can_run(p_departure) then raise exception 'Réservé à la compagnie ou au chauffeur du départ'; end if;
  select * into d from public.bus_departures where id = p_departure;
  if d.status <> 'programme' then raise exception 'Le départ n''accepte plus de colis'; end if;
  select * into c from public.colis_parcels where ref = upper(trim(p_ref)) for update;
  if not found or c.departure_id <> p_departure then raise exception 'Colis inconnu pour ce départ'; end if;
  if c.status <> 'enregistre' then raise exception 'Colis déjà réceptionné ou annulé'; end if;
  if p_weight is null or p_weight <= 0 or p_weight > 30 then raise exception 'Poids vérifié de 0,1 à 30 kg'; end if;
  if p_weight > c.weight_kg * 1.3 then
    raise exception 'Écart de poids supérieur à 30 %% (déclaré % kg) : colis refusé, l''expéditeur doit refaire un envoi', c.weight_kg;
  end if;
  update public.colis_parcels set status = 'depose', verified_weight_kg = p_weight, updated_at = now() where id = c.id;
  perform public.colis_event(c.id, 'depose', auth.uid(), 'Déposé en gare et contrôlé (' || p_weight || ' kg)');
end;
$$;

create or replace function public.colis_deliver(p_departure uuid, p_ref text, p_otp text) returns int
language plpgsql security definer set search_path = public as $$
declare c public.colis_parcels; v_owner uuid; v_comm int; v_net int;
begin
  if not public.bus_can_run(p_departure) then raise exception 'Réservé à la compagnie ou au chauffeur du départ'; end if;
  select * into c from public.colis_parcels where ref = upper(trim(p_ref)) for update;
  if not found or c.departure_id <> p_departure then raise exception 'Colis inconnu pour ce départ'; end if;
  if c.status <> 'arrive' then raise exception 'Colis pas encore arrivé ou déjà remis'; end if;
  if c.otp <> trim(coalesce(p_otp, '')) then raise exception 'Code de retrait incorrect'; end if;
  select co.owner_id into v_owner from public.bus_departures d join public.bus_companies co on co.id = d.company_id where d.id = c.departure_id;
  v_comm := round(c.transport_fcfa * 0.12);
  v_net := c.transport_fcfa - v_comm;
  perform public.wallet_post(v_owner, v_net, 'revenu', 'Colis ' || c.ref, auth.uid());
  update public.colis_parcels set status = 'livre', company_net_fcfa = v_net, commission_fcfa = v_comm, updated_at = now() where id = c.id;
  perform public.colis_event(c.id, 'livre', auth.uid(), 'Remis au destinataire contre son code');
  return v_net;
end;
$$;

create or replace function public.colis_manifest(p_departure uuid)
returns table (ref text, recipient_name text, recipient_phone text, weight_kg numeric, size colis_size, service colis_service, status colis_status)
language sql stable security definer set search_path = public as $$
  select p.ref, p.recipient_name, p.recipient_phone, coalesce(p.verified_weight_kg, p.weight_kg), p.size, p.service, p.status
  from public.colis_parcels p
  where p.departure_id = p_departure and p.status <> 'annule' and (public.bus_can_run(p_departure) or public.is_staff())
  order by p.created_at
$$;

-- ---------- Réclamations ----------
create or replace function public.colis_open_claim(p_parcel uuid, p_kind colis_claim_kind, p_description text) returns uuid
language plpgsql security definer set search_path = public as $$
declare c public.colis_parcels; v_id uuid;
begin
  select * into c from public.colis_parcels where id = p_parcel;
  if not found or c.sender_id is distinct from auth.uid() then raise exception 'Colis introuvable'; end if;
  if c.status in ('enregistre', 'annule') then raise exception 'Pas de réclamation possible : colis non pris en charge'; end if;
  if c.status = 'livre' and p_kind in ('perdu', 'retard') then raise exception 'Colis déjà livré : seul un dommage ou une altération peut être signalé'; end if;
  if c.status <> 'livre' and p_kind in ('endommage', 'altere') then raise exception 'Dommage ou altération : possible à la livraison'; end if;
  insert into public.colis_claims (parcel_id, claimant_id, kind, description) values (p_parcel, auth.uid(), p_kind, trim(p_description))
  returning id into v_id;
  return v_id;
exception when unique_violation then raise exception 'Une réclamation de ce type existe déjà pour ce colis';
end;
$$;

create or replace function public.colis_claim_max(p_claim uuid) returns int
language sql stable security definer set search_path = public as $$
  select case when k.kind = 'retard' then (round(least(p.declared_value_fcfa, public.colis_tier_cap(p.tier)) * 0.15 / 50) * 50)::int
              else least(p.declared_value_fcfa, public.colis_tier_cap(p.tier)) end
  from public.colis_claims k join public.colis_parcels p on p.id = k.parcel_id
  where k.id = p_claim and public.is_staff()
$$;

create or replace function public.colis_decide_claim(p_claim uuid, p_accept boolean, p_amount int, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare k public.colis_claims; v_max int; p public.colis_parcels;
begin
  if not public.is_moderator() then raise exception 'Réservé à l''équipe Transvia'; end if;
  select * into k from public.colis_claims where id = p_claim for update;
  if not found or k.status <> 'ouverte' then raise exception 'Réclamation introuvable ou déjà traitée'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'Motif de la décision obligatoire'; end if;
  select * into p from public.colis_parcels where id = k.parcel_id;
  if p_accept then
    v_max := public.colis_claim_max(p_claim);
    if p_amount is null or p_amount <= 0 or p_amount > v_max then raise exception 'Indemnité de 1 à % FCFA (plafond de la formule)', v_max; end if;
    perform public.wallet_post(k.claimant_id, p_amount, 'remboursement', 'Indemnisation colis ' || p.ref, auth.uid());
    update public.colis_claims set status = 'indemnisee', indemnity_fcfa = p_amount, decision_note = trim(p_note), decided_at = now() where id = p_claim;
  else
    update public.colis_claims set status = 'rejetee', decision_note = trim(p_note), decided_at = now() where id = p_claim;
  end if;
  perform public.log_admin('colis réclamation ' || case when p_accept then 'indemnisée' else 'rejetée' end, k.claimant_id, p_claim::text);
end;
$$;

-- ---------- Droits ----------
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.colis_departures(text, text), public.colis_quote(uuid, numeric, colis_size, colis_service, colis_tier),
  public.colis_create(uuid, text, text, numeric, colis_size, colis_service, colis_tier, int, boolean),
  public.colis_my_otp(uuid), public.colis_cancel(uuid), public.colis_receive(uuid, text, numeric),
  public.colis_deliver(uuid, text, text), public.colis_manifest(uuid), public.colis_open_claim(uuid, colis_claim_kind, text),
  public.colis_claim_max(uuid), public.colis_decide_claim(uuid, boolean, int, text)
  to authenticated;
grant execute on function public.colis_track(text) to anon, authenticated;

alter table public.colis_parcels enable row level security;
alter table public.colis_events enable row level security;
alter table public.colis_claims enable row level security;
create policy colis_parcels_select on public.colis_parcels for select to authenticated
  using (sender_id = auth.uid() or public.is_staff() or public.bus_can_run(departure_id));
create policy colis_events_select on public.colis_events for select to authenticated
  using (exists (select 1 from public.colis_parcels p where p.id = parcel_id and (p.sender_id = auth.uid() or public.is_staff() or public.bus_can_run(p.departure_id))));
create policy colis_claims_select on public.colis_claims for select to authenticated using (claimant_id = auth.uid() or public.is_staff());

-- le code de retrait n'est jamais lisible en direct (ni par la compagnie)
revoke select on public.colis_parcels from authenticated;
grant select (id, ref, sender_id, departure_id, recipient_name, recipient_phone, weight_kg, verified_weight_kg, size, service, tier,
              declared_value_fcfa, transport_fcfa, insurance_fcfa, total_fcfa, status, refunded_fcfa, company_net_fcfa,
              commission_fcfa, created_at, updated_at) on public.colis_parcels to authenticated;
revoke all on public.colis_parcels, public.colis_events, public.colis_claims from anon;
revoke insert, update, delete on public.colis_parcels, public.colis_events, public.colis_claims from authenticated;
