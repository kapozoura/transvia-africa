# Transvia Africa

Plateforme de mobilité et de logistique (autocar, covoiturage, VTC, colis, fret, location, transports publics).
Next.js 14 + Supabase + Vercel. La démo interactive reste accessible sur `/demo/index.html`.

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
