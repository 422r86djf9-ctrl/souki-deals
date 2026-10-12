# Souki Deals

Le halal au meilleur prix, près de chez vous. Appli Android et iPhone (Expo SDK 54) + serveur Supabase.

## Principe
- Le client voit les commerces halal autour de lui (boucheries, restaurants, boulangeries, supermarchés, épiceries, primeurs, poissonneries) et leurs prix après remise.
- Il obtient un **bon de réduction** (QR code + code de 8 caractères, valable 24 h, une seule fois).
- En caisse, le commerçant scanne le bon (ou tape le code) et saisit le **montant payé, remise déduite**. Le client confirme sur son téléphone (ou conteste). Sans réponse en 24 h : confirmé automatiquement.
- **Remise client : 5 % minimum** (le commerçant peut offrir plus). **Commission Souki Deals : 5 % du montant payé.** Rien à payer si l'appli n'amène personne.
- **Lancement** : Île-de-France (8 départements). **3 mois sans commission pour les 150 premiers commerces** (à partir de la validation par le fondateur).
- Chaque lundi, la commission de la semaine passée devient un **prélèvement** par commerce. Paiement par carte (Stripe) à brancher quand la société existe ; en attendant, le fondateur marque les prélèvements « payé / refusé / offert ». Prélèvement refusé (ou en attente depuis 7 jours) : commerce masqué.
- **Factures** : dès qu'un prélèvement est payé, une facture numérotée (`SD-2026-000001`, numérotation continue) est créée, son PDF rangé dans le stockage privé `factures/` et envoyé au commerçant par e-mail. Le commerçant la retrouve dans Mon commerce > Mes factures (voir le PDF, renvoyer par e-mail). La commission prélevée est **TTC** (TVA réglable, 0 % = franchise, mention art. 293 B du CGI). Tant que les informations de la société (raison sociale, adresse, SIRET, n° de TVA) ne sont pas remplies dans Administration > Factures, les paiements attendent et sont facturés dès l'enregistrement. Une facture émise ne se modifie pas et ne se supprime pas ; un prélèvement facturé ne change plus de statut.
- Tous les réglages (remise minimum, commission, places et durée de l'offre de lancement, validité des bons…) se changent dans l'Administration.

## Écrans
- Client : Autour de moi (liste ou carte, rayon, type), Chercher un produit, fiche du commerce (prix remisés, itinéraire, signalement), bon QR, Mes bons et achats (économies, confirmation).
- Commerçant : inscription (conditions, carte, remise, SIRET, certification déclarée), Mon commerce (ventes amenées, commission due ou offerte, prélèvements), Mes produits, Scanner.
- Administration (Demba.sacko20@gmail.com uniquement) : résumé, commerces à valider, contestations, prélèvements, signalements, réglages et zones ouvertes.
- Langues : français, anglais, arabe (écrans de droite à gauche).

## Serveur
- `supabase/migrations/000…005` ; `supabase/INSTALLER_SOUKI_DEALS.sql` à coller dans le SQL Editor d'un **nouveau projet Supabase (région Europe)**. Une base déjà installée se met à jour avec `supabase/MISE_A_JOUR_005_FACTURES.sql` (n'efface rien, relançable). La remise à zéro est refusée dès qu'une facture existe (conservation 10 ans).
- Envoi des factures : Edge Function `supabase/functions/envoyer-facture` (PDF avec pdf-lib, e-mail avec Resend), appelée par la base via pg_net ; nouvel essai toutes les 30 minutes (5 essais), puis « Envoi impossible » visible du fondateur. Secrets : `RESEND_API_KEY`, `FACTURES_EXPEDITEUR` ; « Verify JWT » désactivé.
- Tâches automatiques toutes les 10 minutes via pg_cron (`souki_deals_tick`).
- Tests : `supabase/run_tests.sh` (113 tests sur PostgreSQL local, plus la mise à jour 005 relancée deux fois et le refus de remise à zéro).
- À vérifier après installation : `select jobname from cron.job;` doit afficher `souki-deals-taches` (sinon activer pg_cron dans Database > Extensions et relancer l'installateur).
- L'administrateur est reconnu à son e-mail **vérifié** : garder « Confirm email » activé dans Supabase et créer le compte du fondateur en premier.
- Offre de lancement attribuée à la validation par le fondateur (dans l'ordre des validations), pas à l'inscription.
- Un prélèvement payé, refusé ou offert n'est plus modifié ; les achats confirmés en retard partent dans le prélèvement suivant.

## Configuration
- Supabase : projet « Souki Deals » `https://rczotdgtkwfbnrbvyjon.supabase.co` (région Europe), clé publique dans `app.json` > `extra`. Installateur appliqué le 11/10/2026, pg_cron actif.
- Projet Expo à créer (`souki-deals`) et `extra.eas.projectId` à ajouter.
- Builds EAS depuis GitHub, profil `test` (APK).
