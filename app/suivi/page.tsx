import { createClient } from "@/lib/supabase/server";
import { COLIS_STATUS_LABELS, fmtDate } from "@/lib/roles";

export const dynamic = "force-dynamic";

type Row = { ref: string; status: string; origin: string; destination: string; departs_at: string; delay_min: number; event_status: string; event_note: string; event_at: string };

export default async function SuiviPage({ searchParams }: { searchParams: { ref?: string } }) {
  const ref = (searchParams.ref ?? "").trim();
  const rows = ref ? (((await createClient().rpc("colis_track", { p_ref: ref })).data ?? []) as Row[]) : [];
  return (
    <div className="mx-auto max-w-xl space-y-4">
      <h1 className="text-2xl font-extrabold">Suivre un colis</h1>
      <form className="flex gap-2">
        <input name="ref" defaultValue={ref} placeholder="Code de suivi (TVC-XXXXXX)" className="flex-1 rounded border px-3 py-2" />
        <button className="rounded bg-navy px-4 py-2 font-bold text-white" type="submit">Suivre</button>
      </form>
      {ref && rows.length === 0 && <p className="rounded bg-amber/20 p-3 text-sm font-semibold">Code introuvable.</p>}
      {rows.length > 0 && (
        <section className="space-y-2 rounded-xl bg-white p-4 shadow-sm">
          <p className="font-bold">{rows[0].origin} → {rows[0].destination} · départ {fmtDate(rows[0].departs_at)}</p>
          {rows[0].delay_min > 0 && <p className="text-sm font-bold text-red-700">Retard annoncé : +{rows[0].delay_min} min</p>}
          <p className="text-sm font-bold text-amber-700">{COLIS_STATUS_LABELS[rows[0].status]}</p>
          <ol className="space-y-1 border-l-2 border-amber pl-3 text-sm">
            {rows.map((r, i) => <li key={i}><b>{fmtDate(r.event_at)}</b> — {r.event_note}</li>)}
          </ol>
          <p className="text-xs text-navy/60">Le retrait en gare d&apos;arrivée se fait avec le code de retrait fourni à l&apos;expéditeur.</p>
        </section>
      )}
    </div>
  );
}
