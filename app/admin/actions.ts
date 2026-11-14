"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function done(key: "ok" | "error", msg: string): never {
  redirect(`/admin?${key}=${encodeURIComponent(msg)}`);
}

export async function decideIdentity(formData: FormData) {
  const decision = String(formData.get("decision"));
  const { error } = await createClient().rpc("decide_identity", {
    p_profile: String(formData.get("profile")),
    p_decision: decision,
    p_reason: String(formData.get("reason") ?? "") || null,
  });
  revalidatePath("/admin");
  if (error) done("error", error.message);
  done("ok", decision === "verifie" ? "Identité validée." : "Identité refusée.");
}

export async function decideRole(formData: FormData) {
  const decision = String(formData.get("decision"));
  const { error } = await createClient().rpc("decide_role", {
    p_profile: String(formData.get("profile")),
    p_role: String(formData.get("role")),
    p_decision: decision,
    p_reason: String(formData.get("reason") ?? "") || null,
  });
  revalidatePath("/admin");
  if (error) done("error", error.message);
  done("ok", "Décision enregistrée.");
}

export async function approveVehicle(formData: FormData) {
  const { error } = await createClient().rpc("bus_approve_vehicle", {
    p_vehicle: String(formData.get("vehicle")), p_approved: formData.get("approve") === "yes",
  });
  revalidatePath("/admin");
  if (error) done("error", error.message);
  done("ok", "Décision sur le véhicule enregistrée.");
}

export async function approveVtcVehicle(formData: FormData) {
  const { error } = await createClient().rpc("vtc_approve_vehicle", {
    p_vehicle: String(formData.get("vehicle")), p_approved: formData.get("approve") === "yes",
  });
  revalidatePath("/admin");
  if (error) done("error", error.message);
  done("ok", "Décision sur le véhicule VTC enregistrée.");
}
