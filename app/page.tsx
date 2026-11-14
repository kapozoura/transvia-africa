import Link from "next/link";
import { configured } from "@/lib/roles";

export default function Home() {
  return (
    <div className="space-y-6">
      <section className="rounded-2xl bg-navy p-8 text-white">
        <h1 className="text-3xl font-extrabold">Voyagez l&apos;Afrique autrement</h1>
        <p className="mt-2 text-white/80">Réservez. Voyagez. Suivez. Autocar, covoiturage, VTC, colis, fret, location et transports publics — avec un seul compte et un seul Wallet.</p>
        <div className="mt-5 flex flex-wrap gap-3">
          <Link href="/auth/signup" className="rounded bg-amber px-4 py-2 font-bold text-navy">Créer mon compte unique</Link>
          <Link href="/auth/login" className="rounded border border-white/40 px-4 py-2 font-semibold">Se connecter</Link>
        </div>
      </section>
      {!configured() && (
        <p className="rounded-xl bg-amber/20 p-4 text-sm font-semibold">
          Base de données non configurée : renseignez NEXT_PUBLIC_SUPABASE_URL et NEXT_PUBLIC_SUPABASE_ANON_KEY (voir README) pour activer les comptes.
        </p>
      )}
      <section className="grid gap-3 sm:grid-cols-3">
        {[
          ["Un seul compte", "Une identité vérifiée une seule fois, valable pour tous les services."],
          ["Des rôles à la demande", "Conducteur, chauffeur, loueur, opérateur… activés sur le même compte après validation Transvia."],
          ["Un seul Wallet", "Un portefeuille unique pour payer, être payé et suivre chaque mouvement."],
        ].map(([t, d]) => (
          <div key={t} className="rounded-xl bg-white p-4 shadow-sm">
            <p className="font-bold">{t}</p>
            <p className="mt-1 text-sm text-navy/70">{d}</p>
          </div>
        ))}
      </section>
    </div>
  );
}
