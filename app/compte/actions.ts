"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function done(path: string, key: "ok" | "error", msg: string): never {
  redirect(`${path}?${key}=${encodeURIComponent(msg)}`);
}

// Toutes les écritures passent par des fonctions SQL qui contrôlent les droits.
export async function submitIdentity(formData: FormData) {
  const { error } = await createClient().rpc("submit_identity", {
    p_doc_type: String(formData.get("doc_type") ?? ""),
    p_doc_number: String(formData.get("doc_number") ?? ""),
  });
  revalidatePath("/compte");
  if (error) done("/compte", "error", error.message);
  done("/compte", "ok", "Pièce d'identité envoyée : elle sera examinée par l'équipe Transvia.");
}

export async function requestRole(formData: FormData) {
  const role = String(formData.get("role") ?? "");
  const docs = formData.getAll("documents").map(String);
  const { error } = await createClient().rpc("request_role", { p_role: role, p_documents: docs });
  revalidatePath("/compte");
  if (error) done("/compte", "error", error.message);
  done("/compte", "ok", "Demande envoyée : l'équipe Transvia va la valider.");
}

export async function topUp(formData: FormData) {
  const amount = Number(formData.get("amount"));
  const { error } = await createClient().rpc("wallet_topup_simulated", { p_amount: amount });
  revalidatePath("/wallet");
  if (error) done("/wallet", "error", error.message);
  done("/wallet", "ok", "Recharge simulée effectuée (aucun vrai paiement).");
}
