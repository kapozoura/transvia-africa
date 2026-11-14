import { createClient } from "@/lib/supabase/server";
import { ROLE_LABELS } from "@/lib/roles";
import { decideIdentity, decideRole } from "./actions";

export const dynamic = "force-dynamic";

export default async function AdminPage({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const supabase = createClient();
  const [{ data: ids }, { data: roles }] = await Promise.all([
    supabase.from("identity_checks").select("profile_id, doc_type, doc_number, submitted_at, profiles(full_name)").eq("status", "en_attente"),
    supabase.from("profile_roles").select("profile_id, role, documents, requested_at, profiles(full_name, id_verified)").eq("status", "en_attente"),
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
    </div>
  );
}
