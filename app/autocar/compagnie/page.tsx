import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { BUS_DEPARTURE_LABELS, CITIES, fcfa, fmtDate } from "@/lib/roles";
import { addDriver, addVehicle, assignDriver, cancelDeparture, publishDeparture, registerCompany } from "../actions";

export const dynamic = "force-dynamic";

export default async function CompagniePage({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const [{ data: role }, { data: company }] = await Promise.all([
    supabase.from("profile_roles").select("status").eq("profile_id", user!.id).eq("role", "compagnie").maybeSingle(),
    supabase.from("bus_companies").select("id, name, phone").eq("owner_id", user!.id).maybeSingle(),
  ]);
  const [{ data: vehicles }, { data: drivers }, { data: departures }] = company
    ? await Promise.all([
        supabase.from("bus_vehicles").select("id, plate, model, seats, approved").eq("company_id", company.id).order("created_at"),
        supabase.from("bus_drivers").select("profile_id").eq("company_id", company.id),
        supabase.from("bus_departures").select("id, origin, destination, departs_at, price_fcfa, status, driver_id, delay_min").eq("company_id", company.id).order("departs_at", { ascending: false }).limit(20),
      ])
    : [{ data: [] }, { data: [] }, { data: [] }];

  // Noms des chauffeurs rattachés (via la liste des profils lisibles par la compagnie : on affiche l'identifiant court si inconnu).
  const driverIds = (drivers ?? []).map((d) => d.profile_id as string);

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-extrabold">Espace compagnie — Autocar</h1>
        <Link href="/autocar" className="text-sm font-semibold underline">Voir les départs</Link>
      </div>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}

      {role?.status !== "actif" ? (
        <p className="rounded-xl bg-amber/20 p-4 text-sm font-semibold">
          Le rôle « Compagnie de transport » n&apos;est pas actif ({role ? role.status : "non demandé"}). Demandez-le depuis{" "}
          <Link href="/compte" className="underline">Mon compte</Link> ; l&apos;équipe Transvia le valide après vérification.
        </p>
      ) : !company ? (
        <form action={registerCompany} className="space-y-2 rounded-xl bg-white p-4 shadow-sm">
          <h2 className="font-bold">Créer ma compagnie</h2>
          <input name="name" required placeholder="Nom de la compagnie" className="w-full rounded border px-3 py-2" />
          <input name="phone" placeholder="Téléphone" className="w-full rounded border px-3 py-2" />
          <button className="rounded bg-navy px-4 py-2 font-bold text-white" type="submit">Créer</button>
        </form>
      ) : (
        <>
          <p className="rounded-xl bg-white p-4 font-bold shadow-sm">{company.name}</p>

          <section className="space-y-3 rounded-xl bg-white p-4 shadow-sm">
            <h2 className="font-bold">Autocars</h2>
            {(vehicles ?? []).map((v) => (
              <p key={v.id} className="text-sm">{v.plate} — {v.model} ({v.seats} places) · <b>{v.approved ? "Approuvé" : "En attente d'approbation Transvia"}</b></p>
            ))}
            <form action={addVehicle} className="flex flex-wrap gap-2">
              <input name="plate" required placeholder="Plaque (CI 1234 AB)" className="rounded border px-2 py-1" />
              <input name="model" required placeholder="Modèle" className="rounded border px-2 py-1" />
              <input name="seats" type="number" min={8} max={60} defaultValue={52} className="w-20 rounded border px-2 py-1" />
              <button className="rounded bg-navy px-3 py-1 font-bold text-white" type="submit">Ajouter</button>
            </form>
          </section>

          <section className="space-y-2 rounded-xl bg-white p-4 shadow-sm">
            <h2 className="font-bold">Chauffeurs ({driverIds.length})</h2>
            <form action={addDriver} className="flex flex-wrap gap-2">
              <input name="email" type="email" required placeholder="E-mail du compte Transvia du chauffeur" className="flex-1 rounded border px-2 py-1" />
              <button className="rounded bg-navy px-3 py-1 font-bold text-white" type="submit">Rattacher</button>
            </form>
            <p className="text-xs text-navy/60">Le chauffeur doit avoir un compte Transvia. Il voit ses départs dans « Espace chauffeur ».</p>
          </section>

          <form action={publishDeparture} className="space-y-2 rounded-xl bg-white p-4 shadow-sm">
            <h2 className="font-bold">Publier un départ</h2>
            <div className="flex flex-wrap gap-2">
              <select name="vehicle" className="rounded border px-2 py-2">
                {(vehicles ?? []).filter((v) => v.approved).map((v) => <option key={v.id} value={v.id}>{v.plate}</option>)}
              </select>
              <select name="origin" className="rounded border px-2 py-2">{CITIES.map((c) => <option key={c}>{c}</option>)}</select>
              <select name="destination" defaultValue="Bouaké" className="rounded border px-2 py-2">{CITIES.map((c) => <option key={c}>{c}</option>)}</select>
              <input name="departs_at" type="datetime-local" required className="rounded border px-2 py-2" />
              <input name="arrives_at" type="datetime-local" required className="rounded border px-2 py-2" />
              <input name="price" type="number" min={500} step={500} defaultValue={17500} className="w-28 rounded border px-2 py-2" />
            </div>
            <input name="driver" placeholder="Identifiant du chauffeur (facultatif, voir ci-dessus)" className="w-full rounded border px-2 py-1 text-xs" list="drivers" />
            <datalist id="drivers">{driverIds.map((d) => <option key={d} value={d} />)}</datalist>
            <p className="text-xs text-navy/60">Seuls les autocars approuvés par Transvia peuvent être affectés. Horaires en heure d&apos;Abidjan.</p>
            <button className="rounded bg-navy px-4 py-2 font-bold text-white" type="submit">Publier</button>
          </form>

          <section className="space-y-3">
            <h2 className="font-bold">Mes départs</h2>
            {(departures ?? []).map((d) => (
              <div key={d.id} className="rounded-xl bg-white p-4 shadow-sm">
                <p className="font-bold">{d.origin} → {d.destination} <span className="text-xs font-normal">({BUS_DEPARTURE_LABELS[d.status]})</span></p>
                <p className="text-sm text-navy/70">{fmtDate(d.departs_at)} · {fcfa(d.price_fcfa)}{d.delay_min > 0 ? ` · retard +${d.delay_min} min` : ""}</p>
                {d.status === "programme" && (
                  <div className="mt-2 flex flex-wrap gap-2">
                    <form action={assignDriver} className="flex gap-1">
                      <input type="hidden" name="departure" value={d.id} />
                      <input name="driver" defaultValue={d.driver_id ?? ""} placeholder="Identifiant chauffeur" className="w-56 rounded border px-2 py-1 text-xs" list="drivers" />
                      <button className="rounded bg-navy px-2 py-1 text-xs font-bold text-white" type="submit">Affecter</button>
                    </form>
                    <form action={cancelDeparture}><input type="hidden" name="departure" value={d.id} />
                      <button className="rounded border border-red-600 px-2 py-1 text-xs font-bold text-red-700" type="submit">Annuler le départ</button></form>
                  </div>
                )}
              </div>
            ))}
          </section>
        </>
      )}
    </div>
  );
}
