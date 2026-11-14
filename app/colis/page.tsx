import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import AutoRefresh from "@/components/AutoRefresh";
import { CITIES, COLIS_CLAIM_LABELS, COLIS_SERVICE_LABELS, COLIS_STATUS_LABELS, fcfa, fmtDate } from "@/lib/roles";
import { cancelParcel, openClaim } from "./actions";

export const dynamic = "force-dynamic";

type Dep = { id: string; company_name: string; origin: string; destination: string; departs_at: string; delay_min: number; kg_left: number };

export default async function ColisPage({ searchParams }: { searchParams: { from?: string; to?: string; ok?: string; error?: string } }) {
  const supabase = createClient();
  const { data: deps } = await supabase.rpc("colis_departures", { p_origin: searchParams.from || null, p_destination: searchParams.to || null });
  const { data: parcels } = await supabase
    .from("colis_parcels")
    .select("id, ref, status, recipient_name, weight_kg, service, total_fcfa, refunded_fcfa, declared_value_fcfa, created_at, bus_departures(origin, destination, departs_at)")
    .order("created_at", { ascending: false }).limit(20);
  const list = parcels ?? [];
  const otps = new Map<string, string>();
  for (const p of list) {
    if (!["livre", "annule"].includes(p.status)) {
      const { data } = await supabase.rpc("colis_my_otp", { p_parcel: p.id });
      if (data) otps.set(p.id, data as string);
    }
  }
  return (
    <div className="space-y-5">
      {list.some((p) => ["depose", "en_transit"].includes(p.status)) && <AutoRefresh seconds={15} />}
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-2xl font-extrabold">Colis</h1>
        <div className="flex gap-3 text-sm font-semibold">
          <Link href="/suivi" className="underline">Suivre un colis</Link>
          <Link href="/colis/gare" className="underline">Espace gare / compagnie</Link>
        </div>
      </div>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}

      <section className="space-y-3 rounded-xl bg-white p-4 shadow-sm">
        <h2 className="font-bold">Envoyer un colis (30 kg maximum)</h2>
        <p className="text-xs text-navy/60">Votre colis voyage dans l&apos;autocar du départ choisi. Au-delà de 30 kg, utilisez Transvia Fret.</p>
        <form className="flex flex-wrap gap-2">
          <select name="from" defaultValue={searchParams.from ?? ""} className="rounded border px-2 py-2"><option value="">Départ (toutes)</option>{CITIES.map((c) => <option key={c}>{c}</option>)}</select>
          <select name="to" defaultValue={searchParams.to ?? ""} className="rounded border px-2 py-2"><option value="">Arrivée (toutes)</option>{CITIES.map((c) => <option key={c}>{c}</option>)}</select>
          <button className="rounded bg-navy px-4 py-2 font-bold text-white" type="submit">Rechercher</button>
        </form>
        {((deps ?? []) as Dep[]).length === 0 && <p className="text-sm text-navy/60">Aucun départ ouvert aux colis pour le moment (le dépôt ferme 1 h avant le départ).</p>}
        {((deps ?? []) as Dep[]).map((d) => (
          <div key={d.id} className="flex flex-wrap items-center justify-between gap-2 rounded border px-3 py-2 text-sm">
            <span><b>{d.origin} → {d.destination}</b> · {d.company_name} · {fmtDate(d.departs_at)}{d.delay_min > 0 ? ` (retard +${d.delay_min} min)` : ""}</span>
            <Link href={`/colis/envoyer/${d.id}`} className="rounded bg-amber px-3 py-1 font-bold text-navy">Envoyer</Link>
          </div>
        ))}
      </section>

      <section className="space-y-3">
        <h2 className="font-bold">Mes colis</h2>
        {list.length === 0 && <p className="text-sm text-navy/60">Aucun colis.</p>}
        {list.map((p) => {
          const d = (Array.isArray(p.bus_departures) ? p.bus_departures[0] : p.bus_departures) as { origin: string; destination: string; departs_at: string } | null;
          const otp = otps.get(p.id);
          return (
            <div key={p.id} className="space-y-2 rounded-xl bg-white p-4 shadow-sm">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <p className="font-bold">{d?.origin} → {d?.destination} <span className="text-sm font-normal">· pour {p.recipient_name}</span></p>
                <Link href={`/suivi?ref=${p.ref}`} className="rounded bg-navy px-2 py-1 text-xs font-bold text-white">{p.ref}</Link>
              </div>
              <p className="text-sm text-navy/70">{d ? fmtDate(d.departs_at) : ""} · {p.weight_kg} kg · {COLIS_SERVICE_LABELS[p.service]} · {fcfa(p.total_fcfa)} · valeur déclarée {fcfa(p.declared_value_fcfa)}</p>
              <p className="text-xs font-bold">{COLIS_STATUS_LABELS[p.status]}{p.refunded_fcfa > 0 ? ` · remboursé ${fcfa(p.refunded_fcfa)}` : ""}</p>
              {otp && <p className="rounded bg-amber/20 p-2 text-sm">Code de retrait à donner à {p.recipient_name} : <b className="text-lg tracking-widest">{otp}</b></p>}
              {p.status === "enregistre" && (
                <form action={cancelParcel}><input type="hidden" name="parcel" value={p.id} />
                  <button className="rounded border border-red-600 px-3 py-1 text-sm font-bold text-red-700" type="submit">Annuler (remboursement intégral)</button></form>
              )}
              {["depose", "en_transit", "arrive", "livre"].includes(p.status) && (
                <details className="text-sm">
                  <summary className="cursor-pointer font-semibold underline">Signaler un problème</summary>
                  <form action={openClaim} className="mt-2 flex flex-wrap gap-2">
                    <input type="hidden" name="parcel" value={p.id} />
                    <select name="kind" className="rounded border px-2 py-1">{Object.entries(COLIS_CLAIM_LABELS).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
                    <input name="description" required minLength={5} placeholder="Décrivez le problème" className="flex-1 rounded border px-2 py-1" />
                    <button className="rounded bg-navy px-3 py-1 font-bold text-white" type="submit">Envoyer</button>
                  </form>
                </details>
              )}
            </div>
          );
        })}
      </section>
    </div>
  );
}
