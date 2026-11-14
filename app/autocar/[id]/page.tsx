import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { fcfa, fmtDate } from "@/lib/roles";
import { bookBus } from "../actions";

export const dynamic = "force-dynamic";

export default async function SeatPage({ params, searchParams }: { params: { id: string }; searchParams: { error?: string } }) {
  const supabase = createClient();
  const { data: dep } = await supabase
    .from("bus_departures")
    .select("id, origin, destination, departs_at, price_fcfa, status, bus_vehicles(seats, model), bus_companies(name)")
    .eq("id", params.id).maybeSingle();
  if (!dep) notFound();
  const { data: taken } = await supabase.rpc("bus_taken_seats", { p_departure: params.id });
  const takenSet = new Set<number>((taken ?? []) as number[]);
  const vehicle = (Array.isArray(dep.bus_vehicles) ? dep.bus_vehicles[0] : dep.bus_vehicles) as { seats: number; model: string };
  const rows = Math.ceil(vehicle.seats / 4);

  return (
    <div className="space-y-4">
      <Link href="/autocar" className="text-sm font-semibold underline">← Retour aux départs</Link>
      <h1 className="text-2xl font-extrabold">{dep.origin} → {dep.destination}</h1>
      <p className="text-sm text-navy/70">{fmtDate(dep.departs_at)} · {fcfa(dep.price_fcfa)} par siège</p>
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}
      {dep.status !== "programme" ? (
        <p className="rounded bg-amber/20 p-3 text-sm font-semibold">Ce départ n&apos;est plus réservable.</p>
      ) : (
        <form action={bookBus} className="space-y-4">
          <input type="hidden" name="departure" value={dep.id} />
          <section className="rounded-xl bg-white p-4 shadow-sm">
            <h2 className="mb-2 font-bold">Plan des sièges (4 maximum)</h2>
            <div className="mx-auto grid w-fit gap-1" style={{ gridTemplateColumns: "repeat(2, 2.2rem) 1.2rem repeat(2, 2.2rem)" }}>
              {Array.from({ length: rows }).flatMap((_, r) => {
                const cells = [1, 2, null, 3, 4].map((p) => (p === null ? -1 : r * 4 + p));
                return cells.map((n, i) =>
                  n === -1 ? <span key={`g${r}`} /> : n > vehicle.seats ? <span key={`${r}-${i}`} /> : (
                    <label key={n} className={`flex h-9 cursor-pointer items-center justify-center rounded border text-xs font-bold ${takenSet.has(n) ? "cursor-not-allowed bg-navy/20 text-navy/40" : "bg-white hover:bg-amber/30"} ${(n - 1) % 4 === 0 || (n - 1) % 4 === 3 ? "border-amber" : ""}`}>
                      <input type="checkbox" name="seat" value={n} disabled={takenSet.has(n)} className="peer sr-only" />
                      <span className="peer-checked:rounded peer-checked:bg-navy peer-checked:px-1 peer-checked:text-white">{n}</span>
                    </label>
                  ),
                );
              })}
            </div>
            <p className="mt-2 text-xs text-navy/60">Contour jaune = siège fenêtre (+500 FCFA). Grisé = déjà réservé.</p>
          </section>
          <section className="space-y-2 rounded-xl bg-white p-4 shadow-sm">
            <h2 className="font-bold">Voyageurs (dans l&apos;ordre des numéros de siège choisis)</h2>
            {[1, 2, 3, 4].map((i) => (
              <div key={i} className="flex gap-2">
                <input name={`name_${i}`} placeholder={`Nom du voyageur ${i}`} className="flex-1 rounded border px-2 py-1" />
                <input name={`phone_${i}`} placeholder="Téléphone" className="w-40 rounded border px-2 py-1" />
              </div>
            ))}
            <label className="block text-sm">Bagages supplémentaires (2 000 FCFA chacun) :{" "}
              <select name="baggage" className="rounded border px-2 py-1">{[0, 1, 2, 3, 4].map((n) => <option key={n}>{n}</option>)}</select>
            </label>
          </section>
          <button className="rounded bg-amber px-5 py-2 font-bold text-navy" type="submit">Payer avec mon Wallet et réserver</button>
        </form>
      )}
    </div>
  );
}
