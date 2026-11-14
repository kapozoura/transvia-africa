"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function done(path: string, key: "ok" | "error", msg: string): never {
  redirect(`${path}?${key}=${encodeURIComponent(msg)}`);
}

export async function bookTrip(formData: FormData) {
  const { error } = await createClient().rpc("carpool_book", {
    p_trip: String(formData.get("trip")),
    p_seats: Number(formData.get("seats") ?? 1),
  });
  revalidatePath("/covoiturage");
  if (error) done("/covoiturage", "error", error.message);
  done("/covoiturage/reservations", "ok", "Réservation enregistrée, le montant est gardé en séquestre jusqu'à la fin du trajet.");
}

export async function cancelBooking(formData: FormData) {
  const { data, error } = await createClient().rpc("carpool_cancel_booking", { p_booking: String(formData.get("booking")) });
  revalidatePath("/covoiturage/reservations");
  if (error) done("/covoiturage/reservations", "error", error.message);
  done("/covoiturage/reservations", "ok", `Réservation annulée. Remboursement : ${data} FCFA.`);
}

export async function publishTrip(formData: FormData) {
  const when = String(formData.get("departs_at") ?? ""); // saisi à l'heure d'Abidjan (GMT)
  const { error } = await createClient().rpc("carpool_publish", {
    p_origin: String(formData.get("origin")),
    p_destination: String(formData.get("destination")),
    p_departs_at: when ? `${when}:00Z` : null,
    p_seats: Number(formData.get("seats")),
    p_price: Number(formData.get("price")),
    p_instant: formData.get("instant") === "on",
  });
  revalidatePath("/covoiturage/conducteur");
  if (error) done("/covoiturage/conducteur", "error", error.message);
  done("/covoiturage/conducteur", "ok", "Trajet publié.");
}

export async function decideBooking(formData: FormData) {
  const { error } = await createClient().rpc("carpool_decide_booking", {
    p_booking: String(formData.get("booking")),
    p_accept: formData.get("decision") === "accept",
  });
  revalidatePath("/covoiturage/conducteur");
  if (error) done("/covoiturage/conducteur", "error", error.message);
  done("/covoiturage/conducteur", "ok", "Décision enregistrée.");
}

export async function completeTrip(formData: FormData) {
  const { data, error } = await createClient().rpc("carpool_complete_trip", { p_trip: String(formData.get("trip")) });
  revalidatePath("/covoiturage/conducteur");
  if (error) done("/covoiturage/conducteur", "error", error.message);
  done("/covoiturage/conducteur", "ok", `Trajet terminé. ${data} FCFA versés sur votre Wallet (commission Transvia de 8 % déduite).`);
}

export async function cancelTrip(formData: FormData) {
  const { error } = await createClient().rpc("carpool_cancel_trip", { p_trip: String(formData.get("trip")) });
  revalidatePath("/covoiturage/conducteur");
  if (error) done("/covoiturage/conducteur", "error", error.message);
  done("/covoiturage/conducteur", "ok", "Trajet annulé, les passagers sont remboursés.");
}
