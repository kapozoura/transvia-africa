# Transvia Africa — démo en ligne

Démonstrateur interactif (Autocar, Covoiturage, VTC, Colis, Fret Cargo, Location, Transports publics, compte unique).
Aucun backend : toutes les données sont des **données de démonstration** et restent dans le navigateur.

## Mettre en ligne (comme Immovia : GitHub + Vercel)

1. Sur github.com, créer un dépôt **transvia-africa** (privé ou public) et y déposer ces 3 fichiers : `index.html`, `vercel.json`, `README.md`.
2. Sur vercel.com : **Add New → Project** → importer le dépôt `transvia-africa`.
3. Réglages : *Framework Preset* = **Other**, *Build Command* et *Output Directory* laissés vides. Cliquer **Deploy**.
4. Vercel donne une adresse du type `transvia-africa.vercel.app`. Chaque modification poussée sur GitHub redéploie automatiquement.

## Domaine

*Settings → Domains* sur Vercel : ajouter par exemple `transvia.africa` ou `demo.transvia.africa` et suivre les enregistrements DNS indiqués.

## À savoir

- La page charge React, Tailwind et Babel depuis des CDN : un accès Internet est nécessaire pour l'ouvrir.
- Le premier affichage prend quelques secondes (compilation dans le navigateur) ; une vraie compilation (Vite ou Next.js) l'accélérera.
