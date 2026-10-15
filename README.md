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
- **Relevé annuel pour le comptable** (Mon commerce > Mes factures > Relevé annuel) : pour l'année choisie, PDF récapitulatif (commissions HT/TVA/TTC, mois par mois, liste des factures, ventes amenées et remises accordées, note pour le comptable) et deux fichiers Excel (CSV « ; », virgule décimale) : factures et achats. Partagés depuis le téléphone (e-mail, Fichiers…).
- **Conditions commerçant** : texte dans `src/lib/conditions.ts` (version `TERMS_VERSION`, identique à `current_terms_version()` dans la base). Le serveur enregistre la version, la date et les taux acceptés à l'inscription ; PDF des conditions acceptées téléchargeable. Changer le texte = nouvelle version dans les deux fichiers : les commerçants voient alors « Nouvelle version des conditions » et l'acceptent dans l'appli.
- **Scan inversé (anti-oubli)** : chaque commerce a un QR code fixe (`shops.shop_code`, « SOUKIDEALS:SHOP:<code> ») à imprimer en autocollant (Mon commerce > QR code du magasin) et à coller sur la tablette du comptoir. En entrant, le client le scanne (« Je suis dans le magasin ») : sa visite apparaît dans « Clients présents » sur la tablette, le commerçant saisit le montant payé (mêmes règles que le scan du bon) ou « Pas d'achat ». Visite sans montant après 2 h (`settings.checkin_minutes`) ou « Pas d'achat » : le client répond « Avez-vous acheté ? » ; un « oui » crée un signalement. Onglet **Méfiance** de l'Administration : score par commerce sur 90 jours (ok / orange / rouge). Le scan classique du bon client reste possible.
- **Inscrits** (Administration) : particuliers et commerçants inscrits, nouveaux du jour, de la semaine et du mois, particuliers actifs sur 30 jours, inscriptions des 12 dernières semaines, commerces par département et par type (`admin_members`).
- **Offre de bienvenue** (payée par Souki Deals) : -10 € sur le premier achat dès 30 € (réglable dans Administration > Réglages : montant, minimum, nombre de places, marche/arrêt). Une fois par compte et par numéro de téléphone. Le commerçant voit en caisse le montant à déduire (scan du bon ou « Clients présents ») ; la commission est calculée sur l'achat bienvenue comprise. Chaque lundi, prélèvement = commissions − bienvenues ; s'il est négatif (offre de lancement…), Souki Deals doit la somme au commerçant : virement, puis « Payé » dans Prélèvements. La facture porte sur la commission et indique les bienvenues déduites.
- **IBAN du commerçant** (Mon commerce > Mon IBAN, table `shop_bank` lisible seulement par lui et le fondateur, clé de contrôle vérifiée) : affiché au fondateur à côté de chaque remboursement à faire, avec une alerte si l'IBAN a changé depuis moins de 7 jours.
- **Promos des commerçants** (Mon commerce > Mes promos, à leurs frais) : offre flash (un produit de -10 à -90 %, jusqu'à 7 jours) et produit offert dès un montant (jusqu'à 30 jours) ; 3 en cours au plus. Visibles par les clients dans « Offres du moment » (rayon 15 km, flash d'abord) et sur la fiche du commerce.
- Conditions commerçant : version du 13/10/2026 (offre de bienvenue, promos) : les commerces déjà inscrits l'acceptent dans l'appli.
- **Connexion Google et Apple** (`src/lib/social.ts`) : Google par le navigateur sécurisé (OAuth Supabase, retour `soukideals://auth`), Apple sur iPhone (`signInWithIdToken`). Le nom est repris dans le profil.
- **Suppression du compte** (Mon profil, `delete_my_account`) : compte, profil et jetons effacés ; achats et factures gardés sans le nom ; refusée tant que des commissions ou remboursements sont en cours ; impossible pour le fondateur.
- **Confidentialité** : écran dans l'appli (`src/lib/confidentialite.ts`) et pages web pour les stores dans `docs/` (GitHub Pages) : `confidentialite.html`, `suppression-compte.html`.
- **Notifications** (`deals_notify`, textes en fr/en/ar dans `deals_text`, envoi Expo via pg_net, journal `notifications`) : client présent (commerçant), achat à confirmer (client), achat contesté, offre flash à moins de 5 km (une par jour au plus, désactivable dans Mon profil, zone arrondie à 1 km), commerce validé, prélèvement refusé, remboursement versé.
- **Photos des produits** (Mes produits) : une photo par produit frais ou fait maison (appareil photo ou galerie, recadrée en carré, réduite à 800 px), stockage public `photos/products/<commerce>/` ; pas de photo pour les produits emballés de marque (case « Produit emballé »). Le client agrandit la photo et peut la signaler ; le fondateur la retire depuis Signalements.
- QR codes dessinés sans internet par `src/lib/qr.ts` (versions 1 à 4, correction M, vérifié avec un décodeur).
- Tous les réglages (remise minimum, commission, places et durée de l'offre de lancement, validité des bons…) se changent dans l'Administration.

## Écrans
- Client : Autour de moi (liste ou carte, rayon, type), Chercher un produit, fiche du commerce (prix remisés, itinéraire, signalement), bon QR, Mes bons et achats (économies, confirmation).
- Commerçant : inscription (conditions, carte, remise, SIRET, certification déclarée), Mon commerce (ventes amenées, commission due ou offerte, prélèvements), Mes produits, Scanner.
- Administration (Demba.sacko20@gmail.com uniquement) : résumé, commerces à valider, contestations, prélèvements, signalements, réglages et zones ouvertes.
- Langues : français, anglais, arabe (écrans de droite à gauche).

## Serveur
- `supabase/migrations/000…012` ; `supabase/INSTALLER_SOUKI_DEALS.sql` à coller dans le SQL Editor d'un **nouveau projet Supabase (région Europe)**. Une base déjà installée se met à jour avec `supabase/MISE_A_JOUR_005_FACTURES.sql` puis `supabase/MISE_A_JOUR_006_RELEVE.sql` `supabase/MISE_A_JOUR_007_SCAN.sql` `supabase/MISE_A_JOUR_008_INSCRITS.sql` `supabase/MISE_A_JOUR_009_PROMOS.sql` `supabase/MISE_A_JOUR_010_IBAN.sql` `supabase/MISE_A_JOUR_011_COMPTE_NOTIFS.sql` et `supabase/MISE_A_JOUR_012_PHOTOS.sql` (n'effacent rien, relançables). La remise à zéro est refusée dès qu'une facture existe (conservation 10 ans).
- Envoi des factures : Edge Function `supabase/functions/envoyer-facture` (PDF avec pdf-lib, e-mail avec Resend), appelée par la base via pg_net ; nouvel essai toutes les 30 minutes (5 essais), puis « Envoi impossible » visible du fondateur. Secrets : `RESEND_API_KEY`, `FACTURES_EXPEDITEUR` ; « Verify JWT » désactivé.
- Tâches automatiques toutes les 10 minutes via pg_cron (`souki_deals_tick`).
- Tests : `supabase/run_tests.sh` (216 tests sur PostgreSQL local, plus les mises à jour 005 à 012 relancées deux fois et le refus de remise à zéro).
- À vérifier après installation : `select jobname from cron.job;` doit afficher `souki-deals-taches` (sinon activer pg_cron dans Database > Extensions et relancer l'installateur).
- L'administrateur est reconnu à son e-mail **vérifié** : garder « Confirm email » activé dans Supabase et créer le compte du fondateur en premier.
- Offre de lancement attribuée à la validation par le fondateur (dans l'ordre des validations), pas à l'inscription.
- Un prélèvement payé, refusé ou offert n'est plus modifié ; les achats confirmés en retard partent dans le prélèvement suivant.

## Configuration
- Supabase : projet « Souki Deals » `https://rczotdgtkwfbnrbvyjon.supabase.co` (région Europe), clé publique dans `app.json` > `extra`. Installateur appliqué le 11/10/2026, pg_cron actif.
- Projet Expo à créer (`souki-deals`) et `extra.eas.projectId` à ajouter.
- Builds EAS depuis GitHub, profil `test` (APK).

## À configurer (une fois)
- **Google** : Google Cloud Console > identifiants OAuth « Application Web » ; dans Supabase > Authentication > Providers > Google : ID client + secret ; dans Supabase > Authentication > URL Configuration > Redirect URLs : `soukideals://**`.
- **Apple** (iPhone, compte Apple Developer) : Supabase > Providers > Apple activé avec le Bundle ID `fr.soukideals.app`.
- **Notifications Android** : projet Firebase, `google-services.json` à la racine + `"googleServicesFile": "./google-services.json"` dans `app.json` > `android`, clé FCM V1 déposée sur expo.dev (Credentials). Sans ça, l'appli marche mais sans notifications.
- **E-mails** : nom de domaine + Resend branché en SMTP dans Supabase > Authentication > Emails (sinon quelques e-mails de confirmation par heure seulement).
- **Pages web** : GitHub > souki-deals > Settings > Pages > « Deploy from a branch », `main`, dossier `/docs`.

## Mises à jour à distance (EAS Update, depuis la version 0.7.0)
- `expo-updates` installé ; `runtimeVersion` = version de `app.json` ; canaux `test` et `production` (eas.json).
- À chaque envoi sur `main`, le workflow `.eas/workflows/mises-a-jour.yml` publie la mise à jour sur Expo (projet relié à GitHub). Elle arrive sur les téléphones à l'ouverture de l'appli et s'applique à l'ouverture suivante. Le bas de « Mon profil » affiche la date de la dernière mise à jour reçue.
- **Règle** : ne changer la version de `app.json` que quand un module natif change (nouvelle dépendance expo-…, plugin, permission, icône, nom). Dans ce cas, refaire un build. Pour tout le reste (écrans, textes, calculs), pas de build : l'envoi sur GitHub suffit.

