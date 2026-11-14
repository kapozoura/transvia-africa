-- Transvia Africa — Lot 1 : compte unique, rôles, portefeuille (Wallet).
-- Conçu pour Supabase (Postgres + Auth + RLS). Testé contre un Postgres 16 local
-- (voir supabase/testing). Principe : un seul compte par personne ; les rôles
-- (conducteur, chauffeur VTC, loueur, opérateur…) s'ajoutent à ce compte après
-- validation de l'équipe Transvia ; un seul Wallet par compte.
--
-- Règle de sécurité générale : les tables sensibles n'ont AUCUNE politique
-- d'écriture pour les utilisateurs. Toute écriture passe par une fonction
-- (RPC) "security definer" qui vérifie les droits et trace l'action.

create extension if not exists pgcrypto;

-- ========================= TYPES =========================

create type transvia_role as enum (
  'conducteur_covoiturage', 'chauffeur_vtc', 'chauffeur_fret',
  'flotte_vtc', 'loueur', 'operateur_tp', 'compagnie'
);
create type staff_role as enum ('admin', 'fondateur', 'finance', 'croissance');
create type role_status as enum ('en_attente', 'actif', 'refuse', 'suspendu');
create type identity_status as enum ('en_attente', 'verifie', 'refuse');
create type account_status as enum ('actif', 'bloque');
create type wallet_entry_kind as enum (
  'recharge_simulee', 'ajustement_equipe', 'paiement', 'remboursement', 'revenu', 'commission'
);

-- ========================= PROFILS =========================

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  city text,
  id_verified boolean not null default false,
  staff_role staff_role,                       -- posé uniquement par l'équipe technique (service role)
  status account_status not null default 'actif',
  created_at timestamptz not null default now()
);

-- Droits par colonne : un utilisateur ne peut modifier QUE son nom, son
-- téléphone et sa ville. Il ne peut ni se déclarer vérifié, ni se donner un
-- rôle d'équipe, ni se débloquer.
revoke update on public.profiles from anon, authenticated;
grant update (full_name, phone, city) on public.profiles to authenticated;
revoke insert, delete on public.profiles from anon, authenticated;

-- ========================= CATALOGUE DES RÔLES =========================

create table public.role_catalog (
  role transvia_role primary key,
  label text not null,
  required_docs text[] not null default '{}',
  sort_order int not null default 0
);

insert into public.role_catalog (role, label, required_docs, sort_order) values
  ('conducteur_covoiturage', 'Conducteur Covoiturage', array['Permis de conduire','Documents du véhicule'], 1),
  ('chauffeur_vtc',          'Chauffeur VTC',          array['Permis de conduire','Documents du véhicule'], 2),
  ('chauffeur_fret',         'Chauffeur Fret (indépendant)', array['Permis C','Carte grise du camion','Assurance marchandises'], 3),
  ('flotte_vtc',             'Entrepreneur de flotte VTC', array['Registre de commerce','Assurance de flotte'], 4),
  ('loueur',                 'Loueur de véhicules',    array['Carte grise','Assurance','Visite technique'], 5),
  ('operateur_tp',           'Opérateur de transport public', array['Autorisation de l''autorité','Assurance passagers'], 6),
  ('compagnie',              'Compagnie de transport', array['Licence de transport','Registre de commerce','Assurance'], 7);

-- ========================= RÔLES DU COMPTE =========================

create table public.profile_roles (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  role transvia_role not null references public.role_catalog(role),
  status role_status not null default 'en_attente',
  documents text[] not null default '{}',      -- pièces déclarées (le dépôt de fichiers viendra au lot suivant)
  reason text,                                  -- motif d'un refus ou d'une suspension
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references public.profiles(id),
  unique (profile_id, role)
);
create index profile_roles_status_idx on public.profile_roles (status);

-- ========================= IDENTITÉ (une seule fois) =========================

create table public.identity_checks (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  doc_type text not null check (doc_type in ('CNI', 'Passeport', 'Attestation d''identité')),
  doc_number text not null check (length(trim(doc_number)) >= 5),
  status identity_status not null default 'en_attente',
  reason text,
  submitted_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references public.profiles(id)
);

-- ========================= WALLET =========================

create table public.wallets (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  balance_fcfa bigint not null default 0 check (balance_fcfa >= 0),
  updated_at timestamptz not null default now()
);

create table public.wallet_entries (
  id bigint generated always as identity primary key,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  amount_fcfa bigint not null check (amount_fcfa <> 0),
  kind wallet_entry_kind not null,
  label text not null,
  balance_after bigint not null,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create index wallet_entries_profile_idx on public.wallet_entries (profile_id, id desc);

-- Journal inaltérable : aucune modification ni suppression, même par erreur.
create or replace function public.wallet_entries_immutable() returns trigger
language plpgsql as $$
begin
  raise exception 'Le journal du Wallet est inaltérable';
end;
$$;
create trigger wallet_entries_no_update before update or delete on public.wallet_entries
  for each row execute function public.wallet_entries_immutable();

-- ========================= JOURNAL D'AUDIT ÉQUIPE =========================

create table public.admin_log (
  id bigint generated always as identity primary key,
  actor_id uuid not null references public.profiles(id),
  action text not null,
  target_profile_id uuid references public.profiles(id),
  detail text,
  created_at timestamptz not null default now()
);

-- ========================= FONCTIONS UTILITAIRES =========================

create or replace function public.staff_role_of(p_uid uuid) returns staff_role
language sql stable security definer set search_path = public as $$
  select staff_role from public.profiles where id = p_uid and status = 'actif'
$$;

create or replace function public.is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select public.staff_role_of(auth.uid()) is not null
$$;

create or replace function public.is_moderator() returns boolean   -- valide identités et rôles
language sql stable security definer set search_path = public as $$
  select coalesce(public.staff_role_of(auth.uid()) in ('admin', 'fondateur'), false)   -- coalesce : NULL (non-équipe) doit valoir faux
$$;

-- Écriture dans le Wallet : fonction INTERNE (aucun droit d'exécution pour les
-- utilisateurs) appelée uniquement par les RPC ci-dessous.
create or replace function public.wallet_post(
  p_profile uuid, p_amount bigint, p_kind wallet_entry_kind, p_label text, p_actor uuid
) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_balance bigint;
begin
  if p_amount = 0 then raise exception 'Montant nul'; end if;
  update public.wallets set balance_fcfa = balance_fcfa + p_amount, updated_at = now()
   where profile_id = p_profile returning balance_fcfa into v_balance;
  if not found then raise exception 'Wallet introuvable'; end if;   -- le check >= 0 refuse un solde négatif
  insert into public.wallet_entries (profile_id, amount_fcfa, kind, label, balance_after, created_by)
  values (p_profile, p_amount, p_kind, p_label, v_balance, p_actor);
  return v_balance;
end;
$$;
revoke all on function public.wallet_post(uuid, bigint, wallet_entry_kind, text, uuid) from public, anon, authenticated;

create or replace function public.log_admin(p_action text, p_target uuid, p_detail text) returns void
language sql security definer set search_path = public as $$
  insert into public.admin_log (actor_id, action, target_profile_id, detail) values (auth.uid(), p_action, p_target, p_detail)
$$;
revoke all on function public.log_admin(text, uuid, text) from public, anon, authenticated;

-- ========================= CRÉATION DU COMPTE =========================
-- Le rôle d'équipe et la vérification ne peuvent JAMAIS venir des métadonnées
-- d'inscription (modifiables par l'utilisateur) : seuls nom, téléphone, ville.

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, phone, city)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''), new.raw_user_meta_data->>'phone', new.raw_user_meta_data->>'city')
  on conflict (id) do nothing;
  insert into public.wallets (profile_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ========================= RPC : IDENTITÉ =========================

create or replace function public.submit_identity(p_doc_type text, p_doc_number text) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if exists (select 1 from public.identity_checks where profile_id = v_uid and status = 'verifie') then
    raise exception 'Identité déjà vérifiée';
  end if;
  insert into public.identity_checks (profile_id, doc_type, doc_number, status, reason, submitted_at, decided_at, decided_by)
  values (v_uid, p_doc_type, trim(p_doc_number), 'en_attente', null, now(), null, null)
  on conflict (profile_id) do update
    set doc_type = excluded.doc_type, doc_number = excluded.doc_number, status = 'en_attente',
        reason = null, submitted_at = now(), decided_at = null, decided_by = null;
end;
$$;

create or replace function public.decide_identity(p_profile uuid, p_decision text, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_moderator() then raise exception 'Réservé à l''équipe Transvia'; end if;
  if p_decision not in ('verifie', 'refuse') then raise exception 'Décision invalide'; end if;
  if p_decision = 'refuse' and coalesce(trim(p_reason), '') = '' then raise exception 'Motif obligatoire pour un refus'; end if;
  update public.identity_checks set status = p_decision::identity_status, reason = nullif(trim(coalesce(p_reason,'')), ''),
         decided_at = now(), decided_by = auth.uid()
   where profile_id = p_profile and status = 'en_attente';
  if not found then raise exception 'Aucune identité en attente pour ce compte'; end if;
  update public.profiles set id_verified = (p_decision = 'verifie') where id = p_profile;
  perform public.log_admin('identité ' || p_decision, p_profile, p_reason);
end;
$$;

-- ========================= RPC : RÔLES =========================

create or replace function public.request_role(p_role transvia_role, p_documents text[]) returns void
language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid(); v_req text[]; v_missing text[]; v_current role_status;
begin
  if v_uid is null then raise exception 'Connexion requise'; end if;
  if not exists (select 1 from public.profiles where id = v_uid and status = 'actif') then raise exception 'Compte bloqué'; end if;
  if not exists (select 1 from public.identity_checks where profile_id = v_uid and status in ('en_attente', 'verifie')) then
    raise exception 'Soumettez d''abord votre pièce d''identité';
  end if;
  select required_docs into v_req from public.role_catalog where role = p_role;
  select array_agg(d) into v_missing from unnest(v_req) d where not (d = any(coalesce(p_documents, '{}')));
  if v_missing is not null then raise exception 'Pièces manquantes : %', array_to_string(v_missing, ', '); end if;
  select status into v_current from public.profile_roles where profile_id = v_uid and role = p_role;
  if v_current in ('en_attente', 'actif', 'suspendu') then raise exception 'Rôle déjà demandé ou actif'; end if;
  insert into public.profile_roles (profile_id, role, status, documents)
  values (v_uid, p_role, 'en_attente', p_documents)
  on conflict (profile_id, role) do update
    set status = 'en_attente', documents = excluded.documents, reason = null,
        requested_at = now(), decided_at = null, decided_by = null;
end;
$$;

create or replace function public.decide_role(p_profile uuid, p_role transvia_role, p_decision role_status, p_reason text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_moderator() then raise exception 'Réservé à l''équipe Transvia'; end if;
  if p_decision not in ('actif', 'refuse', 'suspendu') then raise exception 'Décision invalide'; end if;
  if p_decision in ('refuse', 'suspendu') and coalesce(trim(p_reason), '') = '' then raise exception 'Motif obligatoire'; end if;
  if p_decision = 'actif' and not exists (select 1 from public.profiles where id = p_profile and id_verified) then
    raise exception 'Identité non vérifiée : validez d''abord la pièce d''identité';
  end if;
  update public.profile_roles
     set status = p_decision, reason = case when p_decision = 'actif' then null else trim(p_reason) end,
         decided_at = now(), decided_by = auth.uid()
   where profile_id = p_profile and role = p_role and (status = 'en_attente' or (p_decision = 'suspendu' and status = 'actif') or (p_decision = 'actif' and status = 'suspendu'));
  if not found then raise exception 'Aucune demande applicable pour ce rôle'; end if;
  perform public.log_admin('rôle ' || p_role || ' ' || p_decision, p_profile, p_reason);
end;
$$;

-- Le propriétaire de la ligne ne peut pas se « réactiver » : les rôles n'ont pas d'écriture directe.

-- ========================= RPC : WALLET =========================

-- Recharge SIMULÉE (bêta) : aucun vrai paiement. Remplacée plus tard par un
-- agrégateur (CinetPay / PayDunya) — le journal conservera ces écritures.
create or replace function public.wallet_topup_simulated(p_amount bigint) returns bigint
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise'; end if;
  if p_amount is null or p_amount < 1000 or p_amount > 100000 then raise exception 'Montant de 1 000 à 100 000 FCFA'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid() and status = 'actif') then raise exception 'Compte bloqué'; end if;
  return public.wallet_post(auth.uid(), p_amount, 'recharge_simulee', 'Recharge simulée (bêta)', auth.uid());
end;
$$;

create or replace function public.wallet_adjust(p_profile uuid, p_amount bigint, p_reason text) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_balance bigint;
begin
  if not coalesce(public.staff_role_of(auth.uid()) in ('admin', 'fondateur', 'finance'), false) then raise exception 'Réservé à l''équipe Transvia'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'Motif obligatoire'; end if;
  v_balance := public.wallet_post(p_profile, p_amount, 'ajustement_equipe', 'Équipe : ' || trim(p_reason), auth.uid());
  perform public.log_admin('ajustement wallet ' || p_amount, p_profile, p_reason);
  return v_balance;
end;
$$;

-- ========================= DROITS D'EXÉCUTION =========================

revoke execute on all functions in schema public from public, anon;
grant execute on function public.submit_identity(text, text),
  public.decide_identity(uuid, text, text),
  public.request_role(transvia_role, text[]),
  public.decide_role(uuid, transvia_role, role_status, text),
  public.wallet_topup_simulated(bigint),
  public.wallet_adjust(uuid, bigint, text),
  public.is_staff(), public.is_moderator()
  to authenticated;
-- wallet_post, log_admin et staff_role_of restent internes (aucun droit d'exécution).
revoke execute on function public.staff_role_of(uuid) from authenticated;
revoke execute on function public.wallet_post(uuid, bigint, wallet_entry_kind, text, uuid) from authenticated;
revoke execute on function public.log_admin(text, uuid, text) from authenticated;

-- ========================= RLS =========================

alter table public.profiles enable row level security;
alter table public.role_catalog enable row level security;
alter table public.profile_roles enable row level security;
alter table public.identity_checks enable row level security;
alter table public.wallets enable row level security;
alter table public.wallet_entries enable row level security;
alter table public.admin_log enable row level security;

create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_staff());
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy catalog_read on public.role_catalog for select to anon, authenticated using (true);

create policy roles_select on public.profile_roles for select to authenticated
  using (profile_id = auth.uid() or public.is_staff());

create policy identity_select on public.identity_checks for select to authenticated
  using (profile_id = auth.uid() or public.is_staff());

create policy wallets_select on public.wallets for select to authenticated
  using (profile_id = auth.uid() or public.is_staff());
create policy wallet_entries_select on public.wallet_entries for select to authenticated
  using (profile_id = auth.uid() or public.is_staff());

create policy admin_log_select on public.admin_log for select to authenticated using (public.is_staff());

-- Aucune politique INSERT/UPDATE/DELETE sur profile_roles, identity_checks,
-- wallets, wallet_entries, admin_log : écriture uniquement via les RPC.
revoke insert, update, delete on public.profile_roles, public.identity_checks, public.wallets, public.wallet_entries, public.admin_log, public.role_catalog from anon, authenticated;
