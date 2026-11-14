import { createClient } from "@/lib/supabase/server";
import { fcfa } from "@/lib/roles";
import { topUp } from "@/app/compte/actions";

export const dynamic = "force-dynamic";

export default async function WalletPage({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const supabase = createClient();
  const { data: wallet } = await supabase.from("wallets").select("balance_fcfa").maybeSingle();
  const { data: entries } = await supabase
    .from("wallet_entries")
    .select("id, amount_fcfa, kind, label, balance_after, created_at")
    .order("id", { ascending: false })
    .limit(50);

  return (
    <div className="space-y-5">
      <h1 className="text-2xl font-extrabold">Mon Wallet</h1>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}
      <section className="rounded-2xl bg-navy p-5 text-white">
        <p className="text-sm text-white/70">Solde</p>
        <p className="text-3xl font-extrabold">{fcfa(wallet?.balance_fcfa)}</p>
        <form action={topUp} className="mt-3 flex gap-2">
          <input name="amount" type="number" min={1000} max={100000} step={500} defaultValue={5000} className="w-32 rounded px-2 py-1 text-navy" />
          <button className="rounded bg-amber px-3 py-1 font-bold text-navy" type="submit">Recharger (simulation)</button>
        </form>
        <p className="mt-2 text-xs text-white/60">Recharge de démonstration : aucun paiement réel (Mobile Money à venir).</p>
      </section>
      <section className="rounded-xl bg-white p-4 shadow-sm">
        <h2 className="font-bold">Mouvements</h2>
        {(entries ?? []).length === 0 && <p className="mt-2 text-sm text-navy/60">Aucun mouvement.</p>}
        <ul className="mt-2 divide-y text-sm">
          {(entries ?? []).map((e) => (
            <li key={e.id} className="flex justify-between py-2">
              <span>{e.label} <span className="text-xs text-navy/50">· {new Date(e.created_at).toLocaleDateString("fr-FR")}</span></span>
              <span className={e.amount_fcfa < 0 ? "font-bold text-red-700" : "font-bold text-green-700"}>{fcfa(e.amount_fcfa)}</span>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
