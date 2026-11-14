import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { BOOKING_STATUS_LABELS, CITIES, fcfa, fmtDate } from "@/lib/roles";
import { cancelTrip, completeTrip, decideBooking, publishTrip } from "../actions";

export const dynamic = "force-dynamic";

type Passenger = { booking_id: string; passenger_name: string; phone: string | null; seats: number; status: string };

export default async function ConducteurPage({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const [{ data: role }, { data: trips }] = await Promise.all([
    supabase.from("profile_roles").select("status").eq("profile_id", user!.id).eq("role", "conducteur_covoiturage").maybeSingle(),
    supabase.from("carpool_trips").select("id, origin, destination, departs_at, seats_total, price_fcfa, instant_booking, status")
      .eq("driver_id", user!.id).order("departs_at", { ascending: false }).limit(20),
  ]);
  const passengersByTrip = new Map<string, Passenger[]>();
  for (const t of trips ?? []) {
    const { data } = await supabase.rpc("carpool_trip_passengers", { p_trip: t.id });
    passengersByTrip.set(t.id, (data ?? []) as Passenger[]);
  }

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-extrabold">Espace conducteur — Covoiturage</h1>
        <Link href="/covoiturage" className="text-sm font-semibold underline">Voir les trajets</Link>
      </div>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}

      {role?.status !== "actif" ? (
        <p className="rounded-xl bg-amber/20 p-4 text-sm font-semibold">
          Le rôle « Conducteur Covoiturage » n&apos;est pas encore actif ({role ? role.status : "non demandé"}). Demandez-le depuis{" "}
          <Link href="/compte" className="underline">Mon compte</Link> ; l&apos;équipe Transvia le valide après vérification de votre identité.
        </p>
      ) : (
        <form action={publishTrip} className="space-y-2 rounded-xl bg-white p-4 shadow-sm">
          <h2 className="font-bold">Publier un trajet</h2>
          <div className="flex flex-wrap gap-2">
            <select name="origin" className="rounded border px-2 py-2">{CITIES.map((c) => <option key={c}>{c}</option>)}</select>
            <select name="destination" defaultValue="Bouaké" className="rounded border px-2 py-2">{CITIES.map((c) => <option key={c}>{c}</option>)}</select>
            <input name="departs_at" type="datetime-local" required className="rounded border px-2 py-2" />
            <input name="seats" type="number" min={1} max={8} defaultValue={3} className="w-20 rounded border px-2 py-2" />
            <input name="price" type="number" min={500} step={100} defaultValue={7000} className="w-28 rounded border px-2 py-2" />
          </div>
          <label className="block text-sm"><input type="checkbox" name="instant" defaultChecked className="mr-2" />Réservation instantanée</label>
          <p className="text-xs text-navy/60">Le prix par place est plafonné (partage de frais, pas un tarif professionnel). Horaire en heure d&apos;Abidjan.</p>
          <button className="rounded bg-navy px-4 py-2 font-bold text-white" type="submit">Publier</button>
        </form>
      )}

      <section className="space-y-3">
        <h2 className="font-bold">Mes trajets</h2>
        {(trips ?? []).length === 0 && <p className="text-sm text-navy/60">Aucun trajet publié.</p>}
        {(trips ?? []).map((t) => (
          <div key={t.id} className="rounded-xl bg-white p-4 shadow-sm">
            <p className="font-bold">{t.origin} → {t.destination} <span className="text-xs font-normal">({t.status})</span></p>
            <p className="text-sm text-navy/70">{fmtDate(t.departs_at)} · {t.seats_total} place(s) · {fcfa(t.price_fcfa)} / place · {t.instant_booking ? "instantané" : "sur validation"}</p>
            <ul className="mt-2 space-y-1 text-sm">
              {(passengersByTrip.get(t.id) ?? []).map((p) => (
                <li key={p.booking_id} className="flex flex-wrap items-center justify-between gap-2">
                  <span>{p.passenger_name} — {p.seats} place(s){p.phone ? ` — ${p.phone}` : ""} · <em>{BOOKING_STATUS_LABELS[p.status]}</em></span>
                  {p.status === "en_attente" && t.status === "ouvert" && (
                    <form action={decideBooking} className="flex gap-1">
                      <input type="hidden" name="booking" value={p.booking_id} />
                      <button name="decision" value="accept" className="rounded bg-green-600 px-2 py-1 text-xs font-bold text-white">Accepter</button>
                      <button name="decision" value="refuse" className="rounded bg-red-600 px-2 py-1 text-xs font-bold text-white">Refuser</button>
                    </form>
                  )}
                </li>
              ))}
            </ul>
            {t.status === "ouvert" && (
              <div className="mt-3 flex gap-2">
                <form action={completeTrip}><input type="hidden" name="trip" value={t.id} />
                  <button className="rounded bg-green-600 px-3 py-1 text-sm font-bold text-white" type="submit">Terminer le trajet</button></form>
                <form action={cancelTrip}><input type="hidden" name="trip" value={t.id} />
                  <button className="rounded border border-red-600 px-3 py-1 text-sm font-bold text-red-700" type="submit">Annuler le trajet</button></form>
              </div>
            )}
          </div>
        ))}
      </section>
    </div>
  );
}
