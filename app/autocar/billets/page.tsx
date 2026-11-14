import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { BUS_BOOKING_LABELS, fcfa, fmtDate } from "@/lib/roles";
import { cancelBusBooking } from "../actions";

export const dynamic = "force-dynamic";

export default async function BilletsPage({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data: bookings } = await supabase
    .from("bus_bookings")
    .select("id, ref, status, total_fcfa, refunded_fcfa, created_at, bus_departures(origin, destination, departs_at, delay_min, bus_companies(name)), bus_booking_seats(seat_no, passenger_name, active)")
    .eq("passenger_id", user!.id).order("created_at", { ascending: false });

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-extrabold">Mes billets Autocar</h1>
        <Link href="/autocar" className="text-sm font-semibold underline">Chercher un départ</Link>
      </div>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}
      {(bookings ?? []).length === 0 && <p className="text-sm text-navy/60">Aucun billet.</p>}
      {(bookings ?? []).map((b) => {
        const d = (Array.isArray(b.bus_departures) ? b.bus_departures[0] : b.bus_departures) as
          | { origin: string; destination: string; departs_at: string; delay_min: number; bus_companies: { name: string } | { name: string }[] } | null;
        const company = d ? (Array.isArray(d.bus_companies) ? d.bus_companies[0]?.name : d.bus_companies?.name) : "";
        return (
          <div key={b.id} className="rounded-xl bg-white p-4 shadow-sm">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <p className="font-bold">{d?.origin} → {d?.destination} <span className="text-sm font-normal">· {company}</span></p>
              <span className="rounded bg-navy px-2 py-1 text-xs font-bold text-white">{b.ref}</span>
            </div>
            <p className="text-sm text-navy/70">{d ? fmtDate(d.departs_at) : ""}{d && d.delay_min > 0 ? ` · retard annoncé +${d.delay_min} min` : ""}</p>
            <ul className="mt-1 text-sm">
              {(b.bus_booking_seats ?? []).filter((s) => s.active).map((s) => <li key={s.seat_no}>Siège {s.seat_no} — {s.passenger_name}</li>)}
            </ul>
            <p className="mt-1 text-xs font-bold">
              {BUS_BOOKING_LABELS[b.status]} · {fcfa(b.total_fcfa)}{b.refunded_fcfa > 0 ? ` · remboursé ${fcfa(b.refunded_fcfa)}` : ""}
            </p>
            {b.status === "confirme" && (
              <form action={cancelBusBooking} className="mt-2">
                <input type="hidden" name="booking" value={b.id} />
                <button className="rounded border border-red-600 px-3 py-1 text-sm font-bold text-red-700" type="submit">Annuler ce billet</button>
              </form>
            )}
          </div>
        );
      })}
    </div>
  );
}
