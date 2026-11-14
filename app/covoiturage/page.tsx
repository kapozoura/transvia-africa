import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { CITIES, fcfa, fmtDate } from "@/lib/roles";
import { bookTrip } from "./actions";

export const dynamic = "force-dynamic";

type Trip = {
  id: string; origin: string; destination: string; departs_at: string; price_fcfa: number;
  instant_booking: boolean; seats_left: number; driver_name: string; driver_verified: boolean;
};

export default async function CovoituragePage({
  searchParams,
}: { searchParams: { from?: string; to?: string; ok?: string; error?: string } }) {
  const supabase = createClient();
  const { data } = await supabase.rpc("carpool_search", {
    p_origin: searchParams.from || null,
    p_destination: searchParams.to || null,
    p_day: null,
  });
  const trips = (data ?? []) as Trip[];

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-2xl font-extrabold">Covoiturage</h1>
        <div className="flex gap-3 text-sm font-semibold">
          <Link href="/covoiturage/reservations" className="underline">Mes réservations</Link>
          <Link href="/covoiturage/conducteur" className="underline">Espace conducteur</Link>
        </div>
      </div>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}

      <form className="flex flex-wrap gap-2 rounded-xl bg-white p-4 shadow-sm">
        <select name="from" defaultValue={searchParams.from ?? ""} className="rounded border px-2 py-2">
          <option value="">Départ (toutes)</option>
          {CITIES.map((c) => <option key={c}>{c}</option>)}
        </select>
        <select name="to" defaultValue={searchParams.to ?? ""} className="rounded border px-2 py-2">
          <option value="">Arrivée (toutes)</option>
          {CITIES.map((c) => <option key={c}>{c}</option>)}
        </select>
        <button className="rounded bg-navy px-4 py-2 font-bold text-white" type="submit">Rechercher</button>
      </form>

      {trips.length === 0 && <p className="text-sm text-navy/60">Aucun trajet disponible pour le moment.</p>}
      <div className="space-y-3">
        {trips.map((t) => (
          <form key={t.id} action={bookTrip} className="rounded-xl bg-white p-4 shadow-sm">
            <input type="hidden" name="trip" value={t.id} />
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <p className="font-bold">{t.origin} → {t.destination}</p>
                <p className="text-sm text-navy/70">
                  {fmtDate(t.departs_at)} · {t.driver_name || "Conducteur"}{t.driver_verified ? " ✓ identité vérifiée" : ""}
                </p>
                <p className="text-xs text-navy/60">
                  {t.seats_left} place(s) · {t.instant_booking ? "Réservation instantanée" : "Sur validation du conducteur"}
                </p>
              </div>
              <div className="text-right">
                <p className="text-lg font-extrabold">{fcfa(t.price_fcfa)}<span className="text-xs font-normal"> / place</span></p>
                <div className="mt-1 flex items-center gap-2">
                  <input name="seats" type="number" min={1} max={t.seats_left} defaultValue={1} className="w-16 rounded border px-2 py-1" />
                  <button className="rounded bg-amber px-3 py-1 font-bold text-navy" type="submit">Réserver</button>
                </div>
              </div>
            </div>
          </form>
        ))}
      </div>
      <p className="text-xs text-navy/60">Paiement par Wallet, gardé en séquestre jusqu&apos;à la fin du trajet. Annulation : remboursement total à plus de 24 h du départ, 50 % entre 6 h et 24 h, 0 % en dessous.</p>
    </div>
  );
}
