"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

function back(path: string, message: string): never {
  redirect(`${path}?error=${encodeURIComponent(message)}`);
}

export async function signUp(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const fullName = String(formData.get("full_name") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim();
  const city = String(formData.get("city") ?? "").trim();
  if (!email || !fullName) back("/auth/signup", "Nom et e-mail obligatoires.");
  if (password.length < 8) back("/auth/signup", "Mot de passe : 8 caractères minimum.");
  // Seuls nom, téléphone et ville passent par les métadonnées : jamais de rôle.
  const { data, error } = await createClient().auth.signUp({
    email,
    password,
    options: { data: { full_name: fullName, phone, city } },
  });
  if (error) back("/auth/signup", error.message);
  if (!data.session) redirect("/auth/login?ok=" + encodeURIComponent("Compte créé : confirmez votre e-mail puis connectez-vous."));
  redirect("/compte");
}

export async function signIn(formData: FormData) {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const next = String(formData.get("next") ?? "/compte");
  const { error } = await createClient().auth.signInWithPassword({ email, password });
  if (error) back("/auth/login", "E-mail ou mot de passe incorrect.");
  // On n'accepte qu'une redirection interne.
  redirect(next.startsWith("/") && !next.startsWith("//") ? next : "/compte");
}

export async function signOut() {
  await createClient().auth.signOut();
  redirect("/");
}
