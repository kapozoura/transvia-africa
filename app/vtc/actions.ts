"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function done(path: string, key: "ok" | "error", msg: string): never {
  redirect(`${path}?${key}=${encodeURIComponent(msg)}`);
}
const str = (f: FormData, k: string) => String(f.get(k) ?? "").trim();

export async function requestRide(formData: FormData) {
  const { error } = await createClient().rpc("vtc_request", {
    p_pickup: str(formData, "pickup"), p_dropoff: str(formData, "dropoff"), p_category: str(formData, "category"),
  });
  revalidatePath("/vtc");
  if (error) done("/vtc", "error", error.message);
  done("/vtc", "ok", "Course demandée et payée par votre Wallet : recherche d'un chauffeur.");
}
export async function cancelRide(formData: FormData) {
  const { data, error } = await createClient().rpc("vtc_cancel_ride", { p_ride: str(formData, "ride") });
  revalidatePath("/vtc");
  if (error) done("/vtc", "error", error.message);
  done("/vtc", "ok", `Course annulée. Remboursement : ${data} FCFA.`);
}
export async function rateRide(formData: FormData) {
  const { error } = await createClient().rpc("vtc_rate", { p_ride: str(formData, "ride"), p_rating: Number(formData.get("rating")), p_comment: str(formData, "comment") });
  revalidatePath("/vtc");
  if (error) done("/vtc", "error", error.message);
  done("/vtc", "ok", "Merci pour votre note.");
}

// ---- Chauffeur ----
export async function addVtcVehicle(formData: FormData) {
  const { error } = await createClient().rpc("vtc_add_vehicle", {
    p_plate: str(formData, "plate"), p_model: str(formData, "model"), p_category: str(formData, "category"), p_seats: Number(formData.get("seats")),
  });
  revalidatePath("/vtc/chauffeur");
  if (error) done("/vtc/chauffeur", "error", error.message);
  done("/vtc/chauffeur", "ok", "Véhicule ajouté : il doit être approuvé par Transvia avant de passer en ligne.");
}
export async function goOnline(formData: FormData) {
  const online = formData.get("online") === "yes";
  const { error } = await createClient().rpc("vtc_set_online", {
    p_online: online, p_vehicle: online ? str(formData, "vehicle") : null, p_zone: online ? str(formData, "zone") : null,
  });
  revalidatePath("/vtc/chauffeur");
  if (error) done("/vtc/chauffeur", "error", error.message);
  done("/vtc/chauffeur", "ok", online ? "Vous êtes en ligne." : "Vous êtes hors ligne.");
}
export async function acceptRide(formData: FormData) {
  const { error } = await createClient().rpc("vtc_accept", { p_ride: str(formData, "ride") });
  revalidatePath("/vtc/chauffeur");
  if (error) done("/vtc/chauffeur", "error", error.message);
  done("/vtc/chauffeur", "ok", "Course acceptée.");
}
export async function arriveRide(formData: FormData) {
  const { error } = await createClient().rpc("vtc_arrive", { p_ride: str(formData, "ride") });
  revalidatePath("/vtc/chauffeur");
  if (error) done("/vtc/chauffeur", "error", error.message);
  done("/vtc/chauffeur", "ok", "Passager prévenu de votre arrivée.");
}
export async function startRide(formData: FormData) {
  const { error } = await createClient().rpc("vtc_start", { p_ride: str(formData, "ride"), p_pin: str(formData, "pin") });
  revalidatePath("/vtc/chauffeur");
  if (error) done("/vtc/chauffeur", "error", error.message);
  done("/vtc/chauffeur", "ok", "Code valide : course démarrée.");
}
export async function completeRide(formData: FormData) {
  const { data, error } = await createClient().rpc("vtc_complete", { p_ride: str(formData, "ride") });
  revalidatePath("/vtc/chauffeur");
  if (error) done("/vtc/chauffeur", "error", error.message);
  done("/vtc/chauffeur", "ok", `Course terminée. ${data} FCFA crédités sur votre Wallet (commission Transvia de 8 % déduite).`);
}
export async function driverCancel(formData: FormData) {
  const { error } = await createClient().rpc("vtc_driver_cancel", { p_ride: str(formData, "ride") });
  revalidatePath("/vtc/chauffeur");
  if (error) done("/vtc/chauffeur", "error", error.message);
  done("/vtc/chauffeur", "ok", "Course annulée : le passager est remboursé.");
}
