# Transvia Africa

Plateforme de mobilité et de logistique (autocar, covoiturage, VTC, colis, fret, location, transports publics).
Next.js 14 + Supabase + Vercel. L'ancienne maquette reste archivée dans `public/demo/` (non liée au site).

## Lot 1 — Compte unique, rôles, Wallet
- `supabase/migrations/0001_compte_unique.sql` : schéma, RPC et RLS.
- `supabase/testing/run_tests.sh` : 40+ tests de droits sur un Postgres 16 local.
- Pages : `/auth/login`, `/auth/signup`, `/compte`, `/wallet`, `/admin` (équipe).

## Lot 2 — Covoiturage (branche `lot-2-covoiturage`, basée sur le Lot 1)
- `supabase/migrations/0002_covoiturage.sql` : trajets, réservations, séquestre Wallet, commission 8 %, barème d'annulation (100 % / 50 % / 0 %), prix plafonné à 1,4 × le prix suggéré.
- Pages : `/covoiturage` (recherche et réservation), `/covoiturage/reservations`, `/covoiturage/conducteur`.
- Tests : `supabase/testing/02_covoiturage_test.sql` (rejoués par `run_tests.sh`).

## Mise en route
1. Créer un projet Supabase, exécuter `supabase/migrations/0001_compte_unique.sql` (SQL Editor).
2. Vercel → Settings → Environment Variables : `NEXT_PUBLIC_SUPABASE_URL` et `NEXT_PUBLIC_SUPABASE_ANON_KEY` (voir `.env.example`). Ne jamais publier la clé `service_role`.
3. Framework Preset Vercel : Next.js.
4. Premier administrateur : après inscription, dans le SQL Editor :
   `update public.profiles set staff_role = 'admin' where id = (select id from auth.users where email = 'VOTRE_EMAIL');`

## Lot 3 — Autocar
Migration `supabase/migrations/0003_autocar.sql` (tests : `supabase/testing/03_autocar_test.sql`).
Pages : `/autocar` (recherche), `/autocar/[id]` (plan des sièges), `/autocar/billets`, `/autocar/compagnie`, `/autocar/chauffeur`.
Les autocars doivent être approuvés par l'équipe Transvia dans `/admin`. Commission 8 %, paiement par Wallet en séquestre jusqu'à l'arrivée.

## Lot 4 — VTC
Migration `supabase/migrations/0004_vtc.sql` (tests : `supabase/testing/04_vtc_test.sql`).
Pages : `/vtc` (commande, suivi, notation), `/vtc/chauffeur` (véhicules, en ligne, demandes, course). Véhicules approuvés dans `/admin`.
Tarif 600 + 250 FCFA/km (min 1 000), 6 catégories, paiement Wallet en séquestre, code de prise en charge, commission 8 %.

## Lot 5 — Colis
Migration `supabase/migrations/0005_colis.sql` (tests : `supabase/testing/05_colis_test.sql`).
Pages : `/colis` (envoi, mes colis, réclamations), `/colis/envoyer/[id]`, `/colis/gare` (compagnie et chauffeur : réception, remise), `/suivi` (public, sans compte). Réclamations traitées dans `/admin`.
Un colis (30 kg max) voyage dans un départ Autocar réel : paiement Wallet, valeur déclarée, code de retrait à 6 chiffres, commission compagnie 12 %.
