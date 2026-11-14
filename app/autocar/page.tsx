import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { CITIES, fcfa, fmtDate } from "@/lib/roles";

export const dynamic = "force-dynamic";

type Dep = {
  id: string; company_name: string; origin: string; destination: string; departs_at: string; arrives_at: string;
  delay_min: number; price_fcfa: number; seats_left: number; vehicle_model: string;
};

export default async function AutocarPage({ searchParams }: { searchParams: { from?: string; to?: string; ok?: string; error?: string } }) {
  const { data } = await createClient().rpc("bus_search", {
    p_origin: searchParams.from || null, p_destination: searchParams.to || null, p_day: null,
  });
  const deps = (data ?? []) as Dep[];
  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-2xl font-extrabold">Autocar</h1>
        <div className="flex gap-3 text-sm font-semibold">
          <Link href="/autocar/billets" className="underline">Mes billets</Link>
          <Link href="/autocar/compagnie" className="underline">Espace compagnie</Link>
          <Link href="/autocar/chauffeur" className="underline">Espace chauffeur</Link>
        </div>
      </div>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}
      <form className="flex flex-wrap gap-2 rounded-xl bg-white p-4 shadow-sm">
        <select name="from" defaultValue={searchParams.from ?? ""} className="rounded border px-2 py-2">
          <option value="">Départ (toutes)</option>{CITIES.map((c) => <option key={c}>{c}</option>)}
        </select>
        <select name="to" defaultValue={searchParams.to ?? ""} className="rounded border px-2 py-2">
          <option value="">Arrivée (toutes)</option>{CITIES.map((c) => <option key={c}>{c}</option>)}
        </select>
        <button className="rounded bg-navy px-4 py-2 font-bold text-white" type="submit">Rechercher</button>
      </form>
      {deps.length === 0 && <p className="text-sm text-navy/60">Aucun départ disponible pour le moment.</p>}
      <div className="space-y-3">
        {deps.map((d) => (
          <div key={d.id} className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-white p-4 shadow-sm">
            <div>
              <p className="font-bold">{d.origin} → {d.destination} <span className="text-sm font-normal">· {d.company_name}</span></p>
              <p className="text-sm text-navy/70">{fmtDate(d.departs_at)} → {fmtDate(d.arrives_at)} · {d.vehicle_model}</p>
              {d.delay_min > 0 && <p className="text-sm font-bold text-red-700">Retard annoncé : +{d.delay_min} min</p>}
              <p className="text-xs text-navy/60">{d.seats_left} place(s) restante(s)</p>
            </div>
            <div className="text-right">
              <p className="text-lg font-extrabold">{fcfa(d.price_fcfa)}</p>
              <Link href={`/autocar/${d.id}`} className="mt-1 inline-block rounded bg-amber px-3 py-1 font-bold text-navy">Choisir mes sièges</Link>
            </div>
          </div>
        ))}
      </div>
      <p className="text-xs text-navy/60">Siège fenêtre +500 FCFA, bagage supplémentaire 2 000 FCFA, 4 sièges maximum. Annulation : 100 % à plus de 24 h du départ, 50 % entre 6 h et 24 h, 0 % en dessous.</p>
    </div>
  );
}
