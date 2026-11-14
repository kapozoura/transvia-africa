import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import AutoRefresh from "@/components/AutoRefresh";
import { VTC_CATEGORY_LABELS, VTC_STATUS_LABELS, VTC_ZONES, fcfa } from "@/lib/roles";
import { acceptRide, addVtcVehicle, arriveRide, completeRide, driverCancel, goOnline, startRide } from "../actions";

export const dynamic = "force-dynamic";

type Open = { id: string; ref: string; category: string; pickup: string; dropoff: string; distance_km: number; price_fcfa: number };

export default async function VtcDriverPage({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const [{ data: role }, { data: vehicles }, { data: me }, { data: rating }, { data: current }] = await Promise.all([
    supabase.from("profile_roles").select("status").eq("profile_id", user!.id).in("role", ["chauffeur_vtc", "flotte_vtc"]).eq("status", "actif").limit(1),
    supabase.from("vtc_vehicles").select("id, plate, model, category, seats, approved").eq("owner_id", user!.id).order("created_at"),
    supabase.from("vtc_drivers").select("online, zone, vehicle_id").eq("profile_id", user!.id).maybeSingle(),
    supabase.rpc("vtc_driver_rating", { p_driver: user!.id }),
    supabase.from("vtc_rides").select("id, ref, status, category, pickup, dropoff, price_fcfa")
      .eq("driver_id", user!.id).in("status", ["acceptee", "arrivee", "en_cours"]).limit(1),
  ]);
  const hasRole = (role ?? []).length > 0;
  const ride = (current ?? [])[0];
  const online = !!me?.online;
  const open: Open[] = online && !ride ? (((await supabase.rpc("vtc_open_requests")).data ?? []) as Open[]) : [];
  const stat = (Array.isArray(rating) ? rating[0] : rating) as { avg_rating: number | null; rides: number } | null;
  const approved = (vehicles ?? []).filter((v) => v.approved);

  return (
    <div className="space-y-5">
      {online && <AutoRefresh seconds={6} />}
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-extrabold">Espace chauffeur — VTC</h1>
        <Link href="/vtc" className="text-sm font-semibold underline">Commander une course</Link>
      </div>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}

      {!hasRole ? (
        <p className="rounded-xl bg-amber/20 p-4 text-sm font-semibold">
          Le rôle « Chauffeur VTC » n&apos;est pas actif. Demandez-le depuis <Link href="/compte" className="underline">Mon compte</Link> ; l&apos;équipe Transvia le valide après vérification.
        </p>
      ) : (
        <>
          <p className="text-sm text-navy/70">Note moyenne : {stat?.avg_rating ? `${stat.avg_rating} ★ (${stat.rides} avis)` : "pas encore d'avis"}</p>

          <section className="space-y-2 rounded-xl bg-white p-4 shadow-sm">
            <h2 className="font-bold">Mes véhicules</h2>
            {(vehicles ?? []).map((v) => (
              <p key={v.id} className="text-sm">{v.plate} — {v.model} · {VTC_CATEGORY_LABELS[v.category]} · <b>{v.approved ? "Approuvé" : "En attente d'approbation Transvia"}</b></p>
            ))}
            <form action={addVtcVehicle} className="flex flex-wrap gap-2">
              <input name="plate" required placeholder="Plaque" className="rounded border px-2 py-1" />
              <input name="model" required placeholder="Modèle" className="rounded border px-2 py-1" />
              <select name="category" className="rounded border px-2 py-1">{Object.entries(VTC_CATEGORY_LABELS).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
              <input name="seats" type="number" min={2} max={9} defaultValue={4} className="w-16 rounded border px-2 py-1" />
              <button className="rounded bg-navy px-3 py-1 font-bold text-white" type="submit">Ajouter</button>
            </form>
          </section>

          <section className="rounded-xl bg-white p-4 shadow-sm">
            {online ? (
              <form action={goOnline} className="flex items-center justify-between">
                <span className="font-bold text-green-700">● En ligne — zone {me?.zone}</span>
                <input type="hidden" name="online" value="no" />
                <button className="rounded border px-3 py-1 font-bold" type="submit">Passer hors ligne</button>
              </form>
            ) : (
              <form action={goOnline} className="flex flex-wrap items-center gap-2">
                <input type="hidden" name="online" value="yes" />
                <select name="vehicle" className="rounded border px-2 py-2">{approved.map((v) => <option key={v.id} value={v.id}>{v.plate} ({VTC_CATEGORY_LABELS[v.category]})</option>)}</select>
                <select name="zone" className="rounded border px-2 py-2">{VTC_ZONES.map((z) => <option key={z}>{z}</option>)}</select>
                <button className="rounded bg-green-600 px-4 py-2 font-bold text-white" type="submit">Passer en ligne</button>
                {approved.length === 0 && <span className="text-xs text-navy/60">Il faut d&apos;abord un véhicule approuvé.</span>}
              </form>
            )}
          </section>

          {ride && (
            <section className="space-y-2 rounded-xl border-2 border-amber bg-white p-4 shadow-sm">
              <p className="text-sm font-bold text-amber-700">{VTC_STATUS_LABELS[ride.status]}</p>
              <p className="font-bold">{ride.pickup} → {ride.dropoff} <span className="text-sm font-normal">· {fcfa(ride.price_fcfa)} ({ride.ref})</span></p>
              {ride.status === "acceptee" && (
                <div className="flex gap-2">
                  <form action={arriveRide}><input type="hidden" name="ride" value={ride.id} /><button className="rounded bg-navy px-4 py-2 font-bold text-white" type="submit">Je suis arrivé</button></form>
                  <form action={driverCancel}><input type="hidden" name="ride" value={ride.id} /><button className="rounded border border-red-600 px-3 py-2 text-sm font-bold text-red-700" type="submit">Annuler</button></form>
                </div>
              )}
              {ride.status === "arrivee" && (
                <div className="space-y-2">
                  <form action={startRide} className="flex gap-2">
                    <input type="hidden" name="ride" value={ride.id} />
                    <input name="pin" required inputMode="numeric" maxLength={4} placeholder="Code du passager" className="w-40 rounded border px-2 py-2" />
                    <button className="rounded bg-green-600 px-4 py-2 font-bold text-white" type="submit">Démarrer</button>
                  </form>
                  <form action={driverCancel}><input type="hidden" name="ride" value={ride.id} /><button className="rounded border border-red-600 px-3 py-1 text-xs font-bold text-red-700" type="submit">Annuler (passager absent)</button></form>
                </div>
              )}
              {ride.status === "en_cours" && (
                <form action={completeRide}><input type="hidden" name="ride" value={ride.id} /><button className="rounded bg-green-600 px-4 py-2 font-bold text-white" type="submit">Arrivée à destination</button></form>
              )}
            </section>
          )}

          {online && !ride && (
            <section className="space-y-2">
              <h2 className="font-bold">Demandes ({open.length})</h2>
              {open.length === 0 && <p className="text-sm text-navy/60">Aucune demande pour votre catégorie. La liste se met à jour toute seule.</p>}
              {open.map((o) => (
                <form key={o.id} action={acceptRide} className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-white p-4 shadow-sm">
                  <input type="hidden" name="ride" value={o.id} />
                  <div>
                    <p className="font-bold">{o.pickup} → {o.dropoff}</p>
                    <p className="text-xs text-navy/70">{o.distance_km} km · {VTC_CATEGORY_LABELS[o.category]} · vous gagnez {fcfa(Math.round(o.price_fcfa * 0.92))}</p>
                  </div>
                  <button className="rounded bg-amber px-4 py-2 font-bold text-navy" type="submit">Accepter</button>
                </form>
              ))}
            </section>
          )}
        </>
      )}
    </div>
  );
}
