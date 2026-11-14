"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { toIsoZ } from "@/lib/roles";

function done(path: string, key: "ok" | "error", msg: string): never {
  redirect(`${path}?${key}=${encodeURIComponent(msg)}`);
}
const str = (f: FormData, k: string) => String(f.get(k) ?? "").trim();

export async function bookBus(formData: FormData) {
  const id = str(formData, "departure");
  const seats = formData.getAll("seat").map((s) => Number(s)).sort((a, b) => a - b);
  const payload = seats.map((seat, i) => ({ seat, name: str(formData, `name_${i + 1}`), phone: str(formData, `phone_${i + 1}`) }));
  const { error } = await createClient().rpc("bus_book", {
    p_departure: id, p_seats: payload, p_baggage_extra: Number(formData.get("baggage") ?? 0),
  });
  if (error) done(`/autocar/${id}`, "error", error.message);
  revalidatePath("/autocar");
  done("/autocar/billets", "ok", "Billet confirmé, payé par votre Wallet (gardé en séquestre jusqu'à l'arrivée).");
}

export async function cancelBusBooking(formData: FormData) {
  const { data, error } = await createClient().rpc("bus_cancel_booking", { p_booking: str(formData, "booking") });
  revalidatePath("/autocar/billets");
  if (error) done("/autocar/billets", "error", error.message);
  done("/autocar/billets", "ok", `Billet annulé. Remboursement : ${data} FCFA.`);
}

// ---- Compagnie ----
export async function registerCompany(formData: FormData) {
  const { error } = await createClient().rpc("bus_register_company", { p_name: str(formData, "name"), p_phone: str(formData, "phone") });
  revalidatePath("/autocar/compagnie");
  if (error) done("/autocar/compagnie", "error", error.message);
  done("/autocar/compagnie", "ok", "Compagnie enregistrée.");
}
export async function addVehicle(formData: FormData) {
  const { error } = await createClient().rpc("bus_add_vehicle", { p_plate: str(formData, "plate"), p_model: str(formData, "model"), p_seats: Number(formData.get("seats")) });
  revalidatePath("/autocar/compagnie");
  if (error) done("/autocar/compagnie", "error", error.message);
  done("/autocar/compagnie", "ok", "Véhicule ajouté : il doit être approuvé par Transvia avant d'être affecté à un départ.");
}
export async function addDriver(formData: FormData) {
  const { error } = await createClient().rpc("bus_add_driver", { p_email: str(formData, "email") });
  revalidatePath("/autocar/compagnie");
  if (error) done("/autocar/compagnie", "error", error.message);
  done("/autocar/compagnie", "ok", "Chauffeur rattaché à la compagnie.");
}
export async function publishDeparture(formData: FormData) {
  const driver = str(formData, "driver");
  const { error } = await createClient().rpc("bus_publish_departure", {
    p_vehicle: str(formData, "vehicle"), p_origin: str(formData, "origin"), p_destination: str(formData, "destination"),
    p_departs_at: toIsoZ(str(formData, "departs_at")), p_arrives_at: toIsoZ(str(formData, "arrives_at")),
    p_price: Number(formData.get("price")), p_driver: driver || null,
  });
  revalidatePath("/autocar/compagnie");
  if (error) done("/autocar/compagnie", "error", error.message);
  done("/autocar/compagnie", "ok", "Départ publié.");
}
export async function assignDriver(formData: FormData) {
  const { error } = await createClient().rpc("bus_assign_driver", { p_departure: str(formData, "departure"), p_driver: str(formData, "driver") || null });
  revalidatePath("/autocar/compagnie");
  if (error) done("/autocar/compagnie", "error", error.message);
  done("/autocar/compagnie", "ok", "Chauffeur affecté.");
}
export async function cancelDeparture(formData: FormData) {
  const { error } = await createClient().rpc("bus_cancel_departure", { p_departure: str(formData, "departure") });
  revalidatePath("/autocar/compagnie");
  if (error) done("/autocar/compagnie", "error", error.message);
  done("/autocar/compagnie", "ok", "Départ annulé, les voyageurs sont remboursés à 100 %.");
}

// ---- Chauffeur (et compagnie) ----
export async function boardTicket(formData: FormData) {
  const { error } = await createClient().rpc("bus_board", { p_departure: str(formData, "departure"), p_ref: str(formData, "ref") });
  revalidatePath("/autocar/chauffeur");
  if (error) done("/autocar/chauffeur", "error", error.message);
  done("/autocar/chauffeur", "ok", "Billet valide : voyageur embarqué.");
}
export async function reportDelay(formData: FormData) {
  const { error } = await createClient().rpc("bus_report_delay", { p_departure: str(formData, "departure"), p_minutes: Number(formData.get("minutes")) });
  revalidatePath("/autocar/chauffeur");
  if (error) done("/autocar/chauffeur", "error", error.message);
  done("/autocar/chauffeur", "ok", "Retard enregistré : il apparaît sur les billets des voyageurs.");
}
export async function startDeparture(formData: FormData) {
  const { error } = await createClient().rpc("bus_start_departure", { p_departure: str(formData, "departure") });
  revalidatePath("/autocar/chauffeur");
  if (error) done("/autocar/chauffeur", "error", error.message);
  done("/autocar/chauffeur", "ok", "Départ démarré.");
}
export async function completeDeparture(formData: FormData) {
  const { data, error } = await createClient().rpc("bus_complete_departure", { p_departure: str(formData, "departure") });
  revalidatePath("/autocar/chauffeur");
  if (error) done("/autocar/chauffeur", "error", error.message);
  done("/autocar/chauffeur", "ok", `Arrivée enregistrée. ${data} FCFA versés à la compagnie (commission Transvia de 8 % déduite).`);
}
