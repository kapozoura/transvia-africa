"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function done(path: string, key: "ok" | "error", msg: string): never {
  redirect(`${path}?${key}=${encodeURIComponent(msg)}`);
}
const str = (f: FormData, k: string) => String(f.get(k) ?? "").trim();

export async function createParcel(formData: FormData) {
  const dep = str(formData, "departure");
  const { error } = await createClient().rpc("colis_create", {
    p_departure: dep, p_recipient_name: str(formData, "recipient_name"), p_recipient_phone: str(formData, "recipient_phone"),
    p_weight: Number(str(formData, "weight").replace(",", ".")), p_size: str(formData, "size"), p_service: str(formData, "service"),
    p_tier: str(formData, "tier"), p_declared: Number(formData.get("declared")), p_forbidden_ack: formData.get("ack") === "on",
  });
  if (error) done(`/colis/envoyer/${dep}`, "error", error.message);
  revalidatePath("/colis");
  done("/colis", "ok", "Colis enregistré et payé par votre Wallet. Déposez-le en gare avant le départ et donnez le code de retrait à votre destinataire.");
}
export async function cancelParcel(formData: FormData) {
  const { error } = await createClient().rpc("colis_cancel", { p_parcel: str(formData, "parcel") });
  revalidatePath("/colis");
  if (error) done("/colis", "error", error.message);
  done("/colis", "ok", "Colis annulé et remboursé.");
}
export async function openClaim(formData: FormData) {
  const { error } = await createClient().rpc("colis_open_claim", {
    p_parcel: str(formData, "parcel"), p_kind: str(formData, "kind"), p_description: str(formData, "description"),
  });
  revalidatePath("/colis");
  if (error) done("/colis", "error", error.message);
  done("/colis", "ok", "Réclamation enregistrée : l'équipe Transvia va l'instruire.");
}

// ---- Gare : compagnie et chauffeur ----
export async function receiveParcel(formData: FormData) {
  const { error } = await createClient().rpc("colis_receive", {
    p_departure: str(formData, "departure"), p_ref: str(formData, "ref"), p_weight: Number(str(formData, "weight").replace(",", ".")),
  });
  revalidatePath("/colis/gare");
  if (error) done("/colis/gare", "error", error.message);
  done("/colis/gare", "ok", "Colis réceptionné et contrôlé.");
}
export async function deliverParcel(formData: FormData) {
  const { data, error } = await createClient().rpc("colis_deliver", {
    p_departure: str(formData, "departure"), p_ref: str(formData, "ref"), p_otp: str(formData, "otp"),
  });
  revalidatePath("/colis/gare");
  if (error) done("/colis/gare", "error", error.message);
  done("/colis/gare", "ok", `Colis remis au destinataire. ${data} FCFA versés à la compagnie (commission Transvia de 12 % déduite).`);
}
