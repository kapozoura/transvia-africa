import { createClient } from "@/lib/supabase/server";
import { ROLE_LABELS, ROLE_STATUS_LABELS } from "@/lib/roles";
import { requestRole, submitIdentity } from "./actions";

export const dynamic = "force-dynamic";

export default async function ComptePage({ searchParams }: { searchParams: { ok?: string; error?: string } }) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const [{ data: profile }, { data: identity }, { data: roles }, { data: catalog }] = await Promise.all([
    supabase.from("profiles").select("full_name, phone, city, id_verified, staff_role").eq("id", user!.id).single(),
    supabase.from("identity_checks").select("doc_type, status, reason").eq("profile_id", user!.id).maybeSingle(),
    supabase.from("profile_roles").select("role, status, reason").eq("profile_id", user!.id),
    supabase.from("role_catalog").select("role, required_docs").order("sort_order"),
  ]);
  const mine = new Map((roles ?? []).map((r) => [r.role as string, r]));

  return (
    <div className="space-y-5">
      <h1 className="text-2xl font-extrabold">Mon compte unique</h1>
      {searchParams.ok && <p className="rounded bg-green-50 p-3 text-sm font-semibold text-green-700">{searchParams.ok}</p>}
      {searchParams.error && <p className="rounded bg-red-50 p-3 text-sm font-semibold text-red-700">{searchParams.error}</p>}

      <section className="rounded-xl bg-white p-4 shadow-sm">
        <p className="font-bold">{profile?.full_name}</p>
        <p className="text-sm text-navy/70">{[profile?.phone, profile?.city, user?.email].filter(Boolean).join(" · ")}</p>
        {profile?.staff_role && <p className="mt-1 text-xs font-bold text-amber">Équipe Transvia : {profile.staff_role}</p>}
      </section>

      <section className="rounded-xl bg-white p-4 shadow-sm">
        <h2 className="font-bold">Identité</h2>
        {profile?.id_verified ? (
          <p className="mt-1 text-sm font-semibold text-green-700">Identité vérifiée (une seule fois pour tous vos rôles).</p>
        ) : identity && identity.status !== "refuse" ? (
          <p className="mt-1 text-sm">Pièce {identity.doc_type} envoyée — en attente de validation.</p>
        ) : (
          <>
            {identity?.status === "refuse" && <p className="mt-1 text-sm font-semibold text-red-700">Refusée : {identity.reason}</p>}
            <form action={submitIdentity} className="mt-2 flex flex-wrap gap-2">
              <select name="doc_type" className="rounded border px-2 py-2">
                <option>CNI</option>
                <option>Passeport</option>
                <option>Attestation d&apos;identité</option>
              </select>
              <input name="doc_number" required minLength={5} placeholder="Numéro de la pièce" className="rounded border px-3 py-2" />
              <button className="rounded bg-navy px-4 py-2 font-bold text-white" type="submit">Envoyer</button>
            </form>
          </>
        )}
      </section>

      <section className="space-y-3">
        <h2 className="font-bold">Mes rôles</h2>
        {(catalog ?? []).map((c) => {
          const r = mine.get(c.role as string);
          const canAsk = !r || r.status === "refuse";
          return (
            <div key={c.role} className="rounded-xl bg-white p-4 shadow-sm">
              <div className="flex items-center justify-between">
                <p className="font-semibold">{ROLE_LABELS[c.role as string] ?? c.role}</p>
                {r && <span className="text-xs font-bold">{ROLE_STATUS_LABELS[r.status as string]}</span>}
              </div>
              {r?.reason && <p className="mt-1 text-xs text-red-700">Motif : {r.reason}</p>}
              {canAsk && (
                <form action={requestRole} className="mt-2 space-y-1">
                  <input type="hidden" name="role" value={c.role as string} />
                  <p className="text-xs text-navy/70">Pièces à déclarer :</p>
                  {(c.required_docs as string[]).map((d) => (
                    <label key={d} className="block text-sm">
                      <input type="checkbox" name="documents" value={d} className="mr-2" />
                      {d}
                    </label>
                  ))}
                  <button className="mt-2 rounded bg-amber px-3 py-1 text-sm font-bold text-navy" type="submit">Demander ce rôle</button>
                </form>
              )}
            </div>
          );
        })}
      </section>
    </div>
  );
}
