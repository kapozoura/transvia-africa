import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { BUS_BOOKING_LABELS, BUS_DEPARTURE_LABELS, fmtDate } from "@/lib/roles";
import { boardTicket, completeDeparture, reportDelay, startDeparture } from "../actions";

export const dynamic = "force-dynamic";

type Row = { booking_ref: string; seat_no: number; passenger_name: string; passenger_phone: string | null; status: string };

export default async function ChauffeurPage({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data: mine } = await supabase.from("bus_departures")
    .select("id, origin, destination, departs_at, status, delay_min")
    .eq("driver_id", user!.id).in("status", ["programme", "en_route"]).order("departs_at").limit(10);
  const manifests = new Map<string, Row[]>();
  for (const d of mine ?? []) {
    const { data } = await supabase.rpc("bus_manifest", { p_departure: d.id });
    manifests.set(d.id, (data ?? []) as Row[]);
  }
  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-extrabold">Espace chauffeur — Autocar</h1>
        <Link href="/autocar" className="text-sm font-semibold underline">Voir les départs</Link>
      </div>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}
      {(mine ?? []).length === 0 && (
        <p className="text-sm text-navy/60">Aucun départ ne vous est affecté. Votre compagnie doit vous rattacher (avec l&apos;e-mail de ce compte) puis vous affecter à un départ.</p>
      )}
      {(mine ?? []).map((d) => {
        const rows = manifests.get(d.id) ?? [];
        const boarded = rows.filter((r) => r.status === "embarque").length;
        return (
          <section key={d.id} className="space-y-3 rounded-xl bg-white p-4 shadow-sm">
            <p className="font-bold">{d.origin} → {d.destination} <span className="text-xs font-normal">({BUS_DEPARTURE_LABELS[d.status]})</span></p>
            <p className="text-sm text-navy/70">{fmtDate(d.departs_at)}{d.delay_min > 0 ? ` · retard +${d.delay_min} min` : ""} · {boarded}/{rows.length} embarqué(s)</p>
            <ul className="divide-y text-sm">
              {rows.map((r) => (
                <li key={r.booking_ref + r.seat_no} className="flex justify-between py-1">
                  <span>Siège {r.seat_no} — {r.passenger_name}{r.passenger_phone ? ` — ${r.passenger_phone}` : ""} <span className="text-xs text-navy/50">{r.booking_ref}</span></span>
                  <em className="text-xs">{BUS_BOOKING_LABELS[r.status]}</em>
                </li>
              ))}
            </ul>
            {d.status === "programme" && (
              <>
                <form action={boardTicket} className="flex gap-2">
                  <input type="hidden" name="departure" value={d.id} />
                  <input name="ref" required placeholder="Référence du billet (TVB-XXXXXXXX)" className="flex-1 rounded border px-2 py-1" />
                  <button className="rounded bg-green-600 px-3 py-1 font-bold text-white" type="submit">Embarquer</button>
                </form>
                <form action={reportDelay} className="flex items-center gap-2 text-sm">
                  <input type="hidden" name="departure" value={d.id} />
                  <input name="minutes" type="number" min={0} max={240} defaultValue={15} className="w-20 rounded border px-2 py-1" /> min
                  <button className="rounded border px-3 py-1 font-bold" type="submit">Signaler un retard</button>
                </form>
                <form action={startDeparture}><input type="hidden" name="departure" value={d.id} />
                  <button className="rounded bg-navy px-4 py-2 font-bold text-white" type="submit">Démarrer le trajet</button></form>
              </>
            )}
            {d.status === "en_route" && (
              <form action={completeDeparture}><input type="hidden" name="departure" value={d.id} />
                <button className="rounded bg-green-600 px-4 py-2 font-bold text-white" type="submit">Arrivée à destination</button></form>
            )}
          </section>
        );
      })}
    </div>
  );
}
