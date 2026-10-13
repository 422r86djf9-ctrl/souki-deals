// Texte de la politique de confidentialité (le même est publié sur le site : docs/confidentialite.html)
export const PRIVACY_UPDATED = '13/10/2026';

export const PRIVACY_SECTIONS: { title: string; body: string[] }[] = [
  {
    title: '1. Qui sommes-nous',
    body: [
      'Souki Deals (la société éditrice de l\'application) est responsable du traitement de vos données. Contact : Demba.sacko20@gmail.com.',
    ],
  },
  {
    title: '2. Données collectées',
    body: [
      'Compte : adresse e-mail, nom, téléphone (facultatif), langue choisie. Si vous vous connectez avec Google ou Apple, nous recevons votre nom et votre e-mail.',
      'Utilisation : bons de réduction, visites dans les magasins (QR code scanné), achats enregistrés (montant, date, commerce), signalements.',
      'Position : seulement si vous l\'autorisez, pour afficher les commerces et les offres proches. Nous gardons une zone arrondie à environ 1 km, jamais votre trajet.',
      'Notifications : un identifiant technique du téléphone, si vous les acceptez.',
      'Commerçants : informations du commerce (nom, adresse, SIRET, prix, promotions), IBAN pour les remboursements, factures.',
    ],
  },
  {
    title: '3. Pourquoi',
    body: [
      'Faire fonctionner le service : remises, bons, enregistrement des achats et leur confirmation, calcul des commissions des commerçants, factures, lutte contre la fraude, notifications utiles (achat à confirmer, offre proche…).',
      'Bases légales : l\'exécution du service que vous demandez, nos obligations comptables, et notre intérêt légitime à prévenir la fraude. La position et les notifications reposent sur votre accord, que vous pouvez retirer à tout moment dans les réglages du téléphone ou dans « Mon profil ».',
    ],
  },
  {
    title: '4. Qui voit vos données',
    body: [
      'Le commerçant ne voit que votre prénom et le code de votre bon, et les montants de vos achats chez lui.',
      'Nos prestataires techniques, liés par contrat : hébergement de la base de données en Europe (Supabase), envoi des e-mails et des notifications (Resend, Expo), paiement des commerçants (Stripe).',
      'Nous ne vendons jamais vos données et ne faisons pas de publicité ciblée.',
    ],
  },
  {
    title: '5. Durée de conservation',
    body: [
      'Votre compte est gardé tant que vous l\'utilisez. Les achats et les factures sont gardés 10 ans (obligation comptable), sans votre nom si vous supprimez votre compte.',
    ],
  },
  {
    title: '6. Vos droits',
    body: [
      'Vous pouvez consulter, corriger ou supprimer vos données. Supprimer votre compte : « Mon profil » > « Supprimer mon compte » dans l\'application, ou par e-mail à Demba.sacko20@gmail.com.',
      'Vous pouvez aussi vous opposer à un traitement, demander une copie de vos données, et déposer une réclamation auprès de la CNIL (www.cnil.fr).',
    ],
  },
  {
    title: '7. Sécurité',
    body: [
      'Les échanges sont chiffrés. L\'accès aux données est limité : chacun ne voit que ses propres informations, et seul le fondateur de Souki Deals a accès à l\'administration.',
    ],
  },
];
