import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { BOOKING_STATUS_LABELS, fcfa, fmtDate } from "@/lib/roles";
import { cancelBooking } from "../actions";

export const dynamic = "force-dynamic";

export default async function ReservationsPage({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data: bookings } = await supabase
    .from("carpool_bookings")
    .select("id, seats, amount_fcfa, status, refunded_fcfa, created_at, carpool_trips(origin, destination, departs_at)")
    .eq("passenger_id", user!.id)
    .order("created_at", { ascending: false });

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-extrabold">Mes réservations</h1>
        <Link href="/covoiturage" className="text-sm font-semibold underline">Chercher un trajet</Link>
      </div>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}
      {(bookings ?? []).length === 0 && <p className="text-sm text-navy/60">Aucune réservation.</p>}
      {(bookings ?? []).map((b) => {
        const t = (Array.isArray(b.carpool_trips) ? b.carpool_trips[0] : b.carpool_trips) as
          | { origin: string; destination: string; departs_at: string } | null;
        const active = b.status === "en_attente" || b.status === "confirmee";
        return (
          <div key={b.id} className="rounded-xl bg-white p-4 shadow-sm">
            <p className="font-bold">{t?.origin} → {t?.destination}</p>
            <p className="text-sm text-navy/70">{t ? fmtDate(t.departs_at) : ""} · {b.seats} place(s) · {fcfa(b.amount_fcfa)}</p>
            <p className="mt-1 text-xs font-bold">{BOOKING_STATUS_LABELS[b.status]}{b.refunded_fcfa > 0 ? ` · remboursé ${fcfa(b.refunded_fcfa)}` : ""}</p>
            {active && (
              <form action={cancelBooking} className="mt-2">
                <input type="hidden" name="booking" value={b.id} />
                <button className="rounded border border-red-600 px-3 py-1 text-sm font-bold text-red-700" type="submit">Annuler</button>
              </form>
            )}
          </div>
        );
      })}
    </div>
  );
}
