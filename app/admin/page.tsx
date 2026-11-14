import { createClient } from "@/lib/supabase/server";
import { ROLE_LABELS } from "@/lib/roles";
import { decideClaim, approveVtcVehicle, approveVehicle, decideIdentity, decideRole } from "./actions";

export const dynamic = "force-dynamic";

export default async function AdminPage({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const supabase = createClient();
  const [{ data: ids }, { data: roles }, { data: vehicles }, { data: vtcVehicles }, { data: claims }] = await Promise.all([
    supabase.from("identity_checks").select("profile_id, doc_type, doc_number, submitted_at, profiles(full_name)").eq("status", "en_attente"),
    supabase.from("profile_roles").select("profile_id, role, documents, requested_at, profiles(full_name, id_verified)").eq("status", "en_attente"),
    supabase.from("bus_vehicles").select("id, plate, model, seats, bus_companies(name)").eq("approved", false),
    supabase.from("vtc_vehicles").select("id, plate, model, category").eq("approved", false),
    supabase.from("colis_claims").select("id, kind, description, colis_parcels(ref, declared_value_fcfa)").eq("status", "ouverte"),
  ]);
  const name = (p: unknown) => (Array.isArray(p) ? p[0]?.full_name : (p as { full_name?: string } | null)?.full_name) ?? "—";

  return (
    <div className="space-y-5">
      <h1 className="text-2xl font-extrabold">Administration — validations</h1>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}

      <section className="space-y-2">
        <h2 className="font-bold">Identités à vérifier ({ids?.length ?? 0})</h2>
        {(ids ?? []).map((i) => (
          <form key={i.profile_id} action={decideIdentity} className="rounded-xl bg-white p-4 shadow-sm">
            <input type="hidden" name="profile" value={i.profile_id} />
            <p className="font-semibold">{name(i.profiles)} — {i.doc_type} {i.doc_number}</p>
            <input name="reason" placeholder="Motif (obligatoire en cas de refus)" className="mt-2 w-full rounded border px-2 py-1 text-sm" />
            <div className="mt-2 flex gap-2">
              <button name="decision" value="verifie" className="rounded bg-green-600 px-3 py-1 text-sm font-bold text-white">Valider</button>
              <button name="decision" value="refuse" className="rounded bg-red-600 px-3 py-1 text-sm font-bold text-white">Refuser</button>
            </div>
          </form>
        ))}
      </section>

      <section className="space-y-2">
        <h2 className="font-bold">Demandes de rôle ({roles?.length ?? 0})</h2>
        {(roles ?? []).map((r) => (
          <form key={r.profile_id + r.role} action={decideRole} className="rounded-xl bg-white p-4 shadow-sm">
            <input type="hidden" name="profile" value={r.profile_id} />
            <input type="hidden" name="role" value={r.role} />
            <p className="font-semibold">{name(r.profiles)} — {ROLE_LABELS[r.role] ?? r.role}</p>
            <p className="text-xs text-navy/70">Pièces : {(r.documents ?? []).join(", ")}</p>
            <input name="reason" placeholder="Motif (obligatoire en cas de refus)" className="mt-2 w-full rounded border px-2 py-1 text-sm" />
            <div className="mt-2 flex gap-2">
              <button name="decision" value="actif" className="rounded bg-green-600 px-3 py-1 text-sm font-bold text-white">Activer</button>
              <button name="decision" value="refuse" className="rounded bg-red-600 px-3 py-1 text-sm font-bold text-white">Refuser</button>
            </div>
          </form>
        ))}
      </section>
      <section className="space-y-2">
        <h2 className="font-bold">Autocars à approuver ({vehicles?.length ?? 0})</h2>
        {(vehicles ?? []).map((v) => (
          <form key={v.id} action={approveVehicle} className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-white p-4 shadow-sm">
            <input type="hidden" name="vehicle" value={v.id} />
            <p className="font-semibold">{v.plate} — {v.model} ({v.seats} places) — {(Array.isArray(v.bus_companies) ? v.bus_companies[0]?.name : (v.bus_companies as { name?: string } | null)?.name) ?? "—"}</p>
            <button name="approve" value="yes" className="rounded bg-green-600 px-3 py-1 text-sm font-bold text-white">Approuver</button>
          </form>
        ))}
      </section>
      <section className="space-y-2">
        <h2 className="font-bold">Véhicules VTC à approuver ({vtcVehicles?.length ?? 0})</h2>
        {(vtcVehicles ?? []).map((v) => (
          <form key={v.id} action={approveVtcVehicle} className="flex flex-wrap items-center justify-between gap-2 rounded-xl bg-white p-4 shadow-sm">
            <input type="hidden" name="vehicle" value={v.id} />
            <p className="font-semibold">{v.plate} — {v.model} ({v.category})</p>
            <button name="approve" value="yes" className="rounded bg-green-600 px-3 py-1 text-sm font-bold text-white">Approuver</button>
          </form>
        ))}
      </section>
      <section className="space-y-2">
        <h2 className="font-bold">Réclamations Colis ({claims?.length ?? 0})</h2>
        {(claims ?? []).map((k) => {
          const p = (Array.isArray(k.colis_parcels) ? k.colis_parcels[0] : k.colis_parcels) as { ref: string; declared_value_fcfa: number } | null;
          return (
            <form key={k.id} action={decideClaim} className="space-y-2 rounded-xl bg-white p-4 shadow-sm">
              <input type="hidden" name="claim" value={k.id} />
              <p className="font-semibold">{p?.ref} — {k.kind} (valeur déclarée {p?.declared_value_fcfa} FCFA)</p>
              <p className="text-sm">{k.description}</p>
              <div className="flex flex-wrap gap-2">
                <input name="amount" type="number" min={1} placeholder="Indemnité (FCFA)" className="w-40 rounded border px-2 py-1" />
                <input name="note" required placeholder="Motif de la décision" className="flex-1 rounded border px-2 py-1" />
                <button name="decision" value="accept" className="rounded bg-green-600 px-3 py-1 text-sm font-bold text-white">Indemniser</button>
                <button name="decision" value="reject" className="rounded border border-red-600 px-3 py-1 text-sm font-bold text-red-700">Rejeter</button>
              </div>
            </form>
          );
        })}
      </section>
    </div>
  );
}
