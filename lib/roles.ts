export const ROLE_LABELS: Record<string, string> = {
  conducteur_covoiturage: "Conducteur Covoiturage",
  chauffeur_vtc: "Chauffeur VTC",
  chauffeur_fret: "Chauffeur Fret (indépendant)",
  flotte_vtc: "Entrepreneur de flotte VTC",
  loueur: "Loueur de véhicules",
  operateur_tp: "Opérateur de transport public",
  compagnie: "Compagnie de transport",
};

export const ROLE_STATUS_LABELS: Record<string, string> = {
  en_attente: "En attente de validation",
  actif: "Actif",
  refuse: "Refusé",
  suspendu: "Suspendu",
};

export const fcfa = (n: number | null | undefined) =>
  `${new Intl.NumberFormat("fr-FR").format(n ?? 0)} FCFA`;

export const configured = () =>
  Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);
