import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { COLIS_SERVICE_LABELS, COLIS_SIZE_LABELS, COLIS_TIER_LABELS, fcfa, fmtDate } from "@/lib/roles";
import { createParcel } from "../../actions";

export const dynamic = "force-dynamic";

type SP = { weight?: string; size?: string; service?: string; tier?: string; error?: string };

export default async function SendPage({ params, searchParams }: { params: { id: string }; searchParams: SP }) {
  const supabase = createClient();
  const { data: dep } = await supabase.from("bus_departures").select("id, origin, destination, departs_at").eq("id", params.id).maybeSingle();
  if (!dep) notFound();
  const weight = searchParams.weight ?? "2";
  const size = searchParams.size ?? "petit";
  const service = searchParams.service ?? "standard";
  const tier = searchParams.tier ?? "standard";
  const { data: q, error: qErr } = await supabase.rpc("colis_quote", {
    p_departure: params.id, p_weight: Number(weight.replace(",", ".")), p_size: size, p_service: service, p_tier: tier,
  });
  const quote = (Array.isArray(q) ? q[0] : q) as { transport: number; insurance: number; total: number } | null;

  return (
    <div className="space-y-4">
      <Link href="/colis" className="text-sm font-semibold underline">← Retour</Link>
      <h1 className="text-2xl font-extrabold">Colis {dep.origin} → {dep.destination}</h1>
      <p className="text-sm text-navy/70">Départ de l&apos;autocar : {fmtDate(dep.departs_at)}. Dépôt en gare jusqu&apos;à 1 h avant, retrait en gare à l&apos;arrivée avec le code.</p>
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}

      <form className="space-y-2 rounded-xl bg-white p-4 shadow-sm">
        <h2 className="font-bold">1. Caractéristiques</h2>
        <div className="flex flex-wrap gap-2">
          <input name="weight" defaultValue={weight} inputMode="decimal" className="w-24 rounded border px-2 py-2" aria-label="Poids en kg" /> <span className="self-center text-sm">kg</span>
          <select name="size" defaultValue={size} className="rounded border px-2 py-2">{Object.entries(COLIS_SIZE_LABELS).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
          <select name="service" defaultValue={service} className="rounded border px-2 py-2">{Object.entries(COLIS_SERVICE_LABELS).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
          <select name="tier" defaultValue={tier} className="rounded border px-2 py-2">{Object.entries(COLIS_TIER_LABELS).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
          <button className="rounded bg-navy px-4 py-2 font-bold text-white" type="submit">Calculer le prix</button>
        </div>
        {quote ? (
          <p className="text-sm">Transport {fcfa(quote.transport)} + assurance {fcfa(quote.insurance)} = <b>{fcfa(quote.total)}</b></p>
        ) : (
          <p className="text-sm font-semibold text-red-700">{qErr?.message}</p>
        )}
      </form>

      {quote && (
        <form action={createParcel} className="space-y-2 rounded-xl bg-white p-4 shadow-sm">
          <h2 className="font-bold">2. Destinataire et paiement</h2>
          <input type="hidden" name="departure" value={dep.id} />
          <input type="hidden" name="weight" value={weight} />
          <input type="hidden" name="size" value={size} />
          <input type="hidden" name="service" value={service} />
          <input type="hidden" name="tier" value={tier} />
          <input name="recipient_name" required placeholder="Nom du destinataire" className="w-full rounded border px-3 py-2" />
          <input name="recipient_phone" required placeholder="Téléphone du destinataire (10 chiffres)" className="w-full rounded border px-3 py-2" />
          <input name="declared" type="number" required min={1000} step={500} placeholder="Valeur du contenu (FCFA)" className="w-full rounded border px-3 py-2" />
          <label className="flex items-start gap-2 text-sm"><input type="checkbox" name="ack" className="mt-1" />
            Je certifie que le colis ne contient ni explosif, ni produit inflammable, illicite ou dangereux.</label>
          <button className="rounded bg-amber px-5 py-2 font-bold text-navy" type="submit">Payer {fcfa(quote.total)} avec mon Wallet</button>
        </form>
      )}
    </div>
  );
}
