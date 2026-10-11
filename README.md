# Souki Deals

Le halal au meilleur prix, près de chez vous. Appli Android et iPhone (Expo SDK 54) + serveur Supabase.

## Principe
- Le client voit les commerces halal autour de lui (boucheries, restaurants, boulangeries, supermarchés, épiceries, primeurs, poissonneries) et leurs prix après remise.
- Il obtient un **bon de réduction** (QR code + code de 8 caractères, valable 24 h, une seule fois).
- En caisse, le commerçant scanne le bon (ou tape le code) et saisit le **montant payé, remise déduite**. Le client confirme sur son téléphone (ou conteste). Sans réponse en 24 h : confirmé automatiquement.
- **Remise client : 5 % minimum** (le commerçant peut offrir plus). **Commission Souki Deals : 5 % du montant payé.** Rien à payer si l'appli n'amène personne.
- **Lancement** : Île-de-France (8 départements). **3 mois sans commission pour les 150 premiers commerces** (à partir de la validation par le fondateur).
- Chaque lundi, la commission de la semaine passée devient un **prélèvement** par commerce. Paiement par carte (Stripe) à brancher quand la société existe ; en attendant, le fondateur marque les prélèvements « payé / refusé / offert ». Prélèvement refusé (ou en attente depuis 7 jours) : commerce masqué.
- Tous les réglages (remise minimum, commission, places et durée de l'offre de lancement, validité des bons…) se changent dans l'Administration.

## Écrans
- Client : Autour de moi (liste ou carte, rayon, type), Chercher un produit, fiche du commerce (prix remisés, itinéraire, signalement), bon QR, Mes bons et achats (économies, confirmation).
- Commerçant : inscription (conditions, carte, remise, SIRET, certification déclarée), Mon commerce (ventes amenées, commission due ou offerte, prélèvements), Mes produits, Scanner.
- Administration (Demba.sacko20@gmail.com uniquement) : résumé, commerces à valider, contestations, prélèvements, signalements, réglages et zones ouvertes.
- Langues : français, anglais, arabe (écrans de droite à gauche).

## Serveur
- `supabase/migrations/000…004` ; `supabase/INSTALLER_SOUKI_DEALS.sql` à coller dans le SQL Editor d'un **nouveau projet Supabase (région Europe)**.
- Tâches automatiques toutes les 10 minutes via pg_cron (`souki_deals_tick`).
- Tests : `supabase/run_tests.sh` (83 tests sur PostgreSQL local).
- À vérifier après installation : `select jobname from cron.job;` doit afficher `souki-deals-taches` (sinon activer pg_cron dans Database > Extensions et relancer l'installateur).
- L'administrateur est reconnu à son e-mail **vérifié** : garder « Confirm email » activé dans Supabase et créer le compte du fondateur en premier.
- Offre de lancement attribuée à la validation par le fondateur (dans l'ordre des validations), pas à l'inscription.
- Un prélèvement payé, refusé ou offert n'est plus modifié ; les achats confirmés en retard partent dans le prélèvement suivant.

## Configuration
- Supabase : projet « Souki Deals » `https://rczotdgtkwfbnrbvyjon.supabase.co` (région Europe), clé publique dans `app.json` > `extra`. Installateur appliqué le 11/10/2026, pg_cron actif.
- Projet Expo à créer (`souki-deals`) et `extra.eas.projectId` à ajouter.
- Builds EAS depuis GitHub, profil `test` (APK).
