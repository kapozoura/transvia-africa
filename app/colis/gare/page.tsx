import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { BUS_DEPARTURE_LABELS, COLIS_STATUS_LABELS, fmtDate } from "@/lib/roles";
import { deliverParcel, receiveParcel } from "../actions";

export const dynamic = "force-dynamic";

type M = { ref: string; recipient_name: string; recipient_phone: string; weight_kg: number; status: string };

export default async function GarePage({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data: company } = await supabase.from("bus_companies").select("id").eq("owner_id", user!.id).maybeSingle();
  const filter = company ? `company_id.eq.${company.id},driver_id.eq.${user!.id}` : `driver_id.eq.${user!.id}`;
  const { data: deps } = await supabase.from("bus_departures")
    .select("id, origin, destination, departs_at, status")
    .or(filter).in("status", ["programme", "en_route", "termine"]).order("departs_at", { ascending: false }).limit(10);
  const manifests = new Map<string, M[]>();
  for (const d of deps ?? []) {
    const { data } = await supabase.rpc("colis_manifest", { p_departure: d.id });
    manifests.set(d.id, (data ?? []) as M[]);
  }
  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-extrabold">Colis — espace gare et compagnie</h1>
        <Link href="/colis" className="text-sm font-semibold underline">Mes colis</Link>
      </div>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}
      {(deps ?? []).length === 0 && <p className="text-sm text-navy/60">Aucun départ. Cet espace est réservé aux compagnies Autocar et à leurs chauffeurs affectés.</p>}
      {(deps ?? []).map((d) => {
        const rows = manifests.get(d.id) ?? [];
        return (
          <section key={d.id} className="space-y-3 rounded-xl bg-white p-4 shadow-sm">
            <p className="font-bold">{d.origin} → {d.destination} <span className="text-xs font-normal">({BUS_DEPARTURE_LABELS[d.status]})</span></p>
            <p className="text-sm text-navy/70">{fmtDate(d.departs_at)} · {rows.length} colis</p>
            <ul className="divide-y text-sm">
              {rows.map((r) => (
                <li key={r.ref} className="flex justify-between py-1"><span>{r.ref} — {r.recipient_name} ({r.recipient_phone}) · {r.weight_kg} kg</span><em className="text-xs">{COLIS_STATUS_LABELS[r.status]}</em></li>
              ))}
            </ul>
            {d.status === "programme" && (
              <form action={receiveParcel} className="flex flex-wrap gap-2">
                <input type="hidden" name="departure" value={d.id} />
                <input name="ref" required placeholder="Code du colis (TVC-XXXXXX)" className="flex-1 rounded border px-2 py-1" />
                <input name="weight" required inputMode="decimal" placeholder="Poids pesé (kg)" className="w-32 rounded border px-2 py-1" />
                <button className="rounded bg-navy px-3 py-1 font-bold text-white" type="submit">Réceptionner</button>
              </form>
            )}
            {d.status === "termine" && (
              <form action={deliverParcel} className="flex flex-wrap gap-2">
                <input type="hidden" name="departure" value={d.id} />
                <input name="ref" required placeholder="Code du colis" className="flex-1 rounded border px-2 py-1" />
                <input name="otp" required inputMode="numeric" maxLength={6} placeholder="Code de retrait du destinataire" className="w-52 rounded border px-2 py-1" />
                <button className="rounded bg-green-600 px-3 py-1 font-bold text-white" type="submit">Remettre le colis</button>
              </form>
            )}
          </section>
        );
      })}
      <p className="text-xs text-navy/60">Le colis passe « en transit » quand le départ démarre et « arrivé » quand le trajet est terminé (espace chauffeur Autocar).</p>
    </div>
  );
}
