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

export const CITIES = ["Abidjan", "Bouaké", "Korhogo", "San Pédro", "Yamoussoukro"];

export const BOOKING_STATUS_LABELS: Record<string, string> = {
  en_attente: "En attente du conducteur",
  confirmee: "Confirmée",
  refusee: "Refusée (remboursée)",
  annulee_passager: "Annulée par vous",
  annulee_conducteur: "Annulée par le conducteur (remboursée)",
  terminee: "Terminée",
};

// Les horaires sont saisis et affichés à l'heure d'Abidjan (GMT).
export const fmtDate = (iso: string) =>
  new Date(iso).toLocaleString("fr-FR", { timeZone: "Africa/Abidjan", dateStyle: "medium", timeStyle: "short" });

export const BUS_BOOKING_LABELS: Record<string, string> = {
  confirme: "Confirmé",
  embarque: "Embarqué",
  arrive: "Arrivé",
  no_show: "Absent au départ",
  annule: "Annulé par vous",
  annule_compagnie: "Annulé par la compagnie (remboursé)",
};
export const BUS_DEPARTURE_LABELS: Record<string, string> = {
  programme: "Programmé", en_route: "En route", termine: "Terminé", annule: "Annulé",
};
// Heure locale d'Abidjan (GMT) pour les champs datetime-local.
export const toIsoZ = (local: string) => (local ? `${local}:00Z` : null);
