import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import AutoRefresh from "@/components/AutoRefresh";
import { VTC_CATEGORY_LABELS, VTC_STATUS_LABELS, VTC_ZONES, fcfa, fmtDate } from "@/lib/roles";
import { cancelRide, rateRide, requestRide } from "./actions";

export const dynamic = "force-dynamic";

type Quote = { category: string; price_fcfa: number; distance_km: number };
type Ride = {
  id: string; ref: string; status: string; category: string; pickup: string; dropoff: string; price_fcfa: number;
  refunded_fcfa: number; rating: number | null; created_at: string; vehicle_id: string | null;
};

export default async function VtcPage({ searchParams }: { searchParams: { from?: string; to?: string; ok?: string; error?: string } }) {
  const supabase = createClient();
  await supabase.rpc("vtc_sweep");
  const { data: rides } = await supabase
    .from("vtc_rides")
    .select("id, ref, status, category, pickup, dropoff, price_fcfa, refunded_fcfa, rating, created_at, vehicle_id")
    .order("created_at", { ascending: false }).limit(15);
  const list = ((rides ?? []) as Ride[]);
  const active = list.find((r) => ["demande", "acceptee", "arrivee", "en_cours"].includes(r.status));
  let pin: string | null = null;
  let vehicle: { plate: string; model: string } | null = null;
  if (active) {
    const { data } = await supabase.rpc("vtc_my_pin", { p_ride: active.id });
    pin = (data as string) ?? null;
    if (active.vehicle_id) {
      const { data: v } = await supabase.from("vtc_vehicles").select("plate, model").eq("id", active.vehicle_id).maybeSingle();
      vehicle = v;
    }
  }
  const quotes: Quote[] = searchParams.from && searchParams.to && searchParams.from !== searchParams.to
    ? (((await supabase.rpc("vtc_quote", { p_pickup: searchParams.from, p_dropoff: searchParams.to })).data ?? []) as Quote[])
    : [];

  return (
    <div className="space-y-5">
      {active && <AutoRefresh />}
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h1 className="text-2xl font-extrabold">VTC</h1>
        <Link href="/vtc/chauffeur" className="text-sm font-semibold underline">Espace chauffeur</Link>
      </div>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}

      {active ? (
        <section className="space-y-2 rounded-xl bg-white p-4 shadow-sm">
          <p className="text-sm font-bold text-amber-700">{VTC_STATUS_LABELS[active.status]}</p>
          <p className="font-bold">{active.pickup} → {active.dropoff} <span className="text-sm font-normal">· {VTC_CATEGORY_LABELS[active.category]} · {fcfa(active.price_fcfa)}</span></p>
          {vehicle && <p className="text-sm">Véhicule : {vehicle.model} — <b>{vehicle.plate}</b></p>}
          {pin && active.status !== "demande" && (
            <p className="rounded bg-amber/20 p-3 text-center">
              Code de prise en charge à donner au chauffeur : <b className="text-2xl tracking-widest">{pin}</b>
            </p>
          )}
          {["demande", "acceptee", "arrivee"].includes(active.status) && (
            <form action={cancelRide}>
              <input type="hidden" name="ride" value={active.id} />
              <button className="rounded border border-red-600 px-3 py-1 text-sm font-bold text-red-700" type="submit">Annuler la course</button>
              <span className="ml-2 text-xs text-navy/60">
                {active.status === "demande" ? "Remboursement intégral" : active.status === "acceptee" ? "Frais de 500 FCFA" : "Frais de 1 000 FCFA"}
              </span>
            </form>
          )}
        </section>
      ) : (
        <section className="space-y-3 rounded-xl bg-white p-4 shadow-sm">
          <h2 className="font-bold">Où allez-vous ?</h2>
          <form className="flex flex-wrap gap-2">
            <select name="from" defaultValue={searchParams.from ?? "Plateau"} className="rounded border px-2 py-2">{VTC_ZONES.map((z) => <option key={z}>{z}</option>)}</select>
            <select name="to" defaultValue={searchParams.to ?? "Cocody"} className="rounded border px-2 py-2">{VTC_ZONES.map((z) => <option key={z}>{z}</option>)}</select>
            <button className="rounded bg-navy px-4 py-2 font-bold text-white" type="submit">Voir les tarifs</button>
          </form>
          {quotes.length > 0 && (
            <div className="space-y-2">
              <p className="text-xs text-navy/60">{quotes[0].distance_km} km estimés. Le prix est débité de votre Wallet et gardé en séquestre jusqu&apos;à l&apos;arrivée.</p>
              {quotes.map((q) => (
                <form key={q.category} action={requestRide} className="flex items-center justify-between rounded border px-3 py-2">
                  <input type="hidden" name="pickup" value={searchParams.from} />
                  <input type="hidden" name="dropoff" value={searchParams.to} />
                  <input type="hidden" name="category" value={q.category} />
                  <span className="font-semibold">{VTC_CATEGORY_LABELS[q.category]}</span>
                  <span className="flex items-center gap-3"><b>{fcfa(q.price_fcfa)}</b>
                    <button className="rounded bg-amber px-3 py-1 font-bold text-navy" type="submit">Commander</button></span>
                </form>
              ))}
            </div>
          )}
        </section>
      )}

      <section className="space-y-2">
        <h2 className="font-bold">Mes courses</h2>
        {list.filter((r) => r !== active).length === 0 && <p className="text-sm text-navy/60">Aucune course pour le moment.</p>}
        {list.filter((r) => r !== active).map((r) => (
          <div key={r.id} className="rounded-xl bg-white p-3 text-sm shadow-sm">
            <p className="font-semibold">{r.pickup} → {r.dropoff} · {fcfa(r.price_fcfa)} <span className="text-xs font-normal">({r.ref})</span></p>
            <p className="text-xs text-navy/70">{fmtDate(r.created_at)} · {VTC_STATUS_LABELS[r.status]}{r.refunded_fcfa > 0 ? ` · remboursé ${fcfa(r.refunded_fcfa)}` : ""}</p>
            {r.status === "terminee" && !r.rating && (
              <form action={rateRide} className="mt-1 flex flex-wrap items-center gap-2">
                <input type="hidden" name="ride" value={r.id} />
                <select name="rating" defaultValue="5" className="rounded border px-2 py-1">{[5, 4, 3, 2, 1].map((n) => <option key={n} value={n}>{n} ★</option>)}</select>
                <input name="comment" placeholder="Commentaire (facultatif)" className="flex-1 rounded border px-2 py-1" />
                <button className="rounded bg-navy px-3 py-1 font-bold text-white" type="submit">Noter</button>
              </form>
            )}
            {r.rating && <p className="text-xs">Votre note : {r.rating} ★</p>}
          </div>
        ))}
      </section>
    </div>
  );
}
