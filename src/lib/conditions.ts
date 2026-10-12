// Conditions commerçant Souki Deals (texte de référence en français)
// La version doit correspondre à public.current_terms_version() côté serveur (migration 006).
// Toute modification du texte = nouvelle version, à changer ici ET dans la base.

export const TERMS_VERSION = '2026-10-12';

export type TermsParams = {
  discountMin: number;
  commission: number;
  launchSlots: number;
  launchMonths: number;
  seller?: { legal_name?: string | null; legal_form?: string | null; address?: string | null; siret?: string | null } | null;
  // Acceptation (pour le PDF du commerçant)
  shop?: { name: string; address?: string | null; siret?: string | null } | null;
  acceptedAt?: string | null;
  acceptedVersion?: string | null;
  acceptedCommission?: number | null;
  acceptedDiscountMin?: number | null;
};

const n = (x: number) => String(x).replace('.', ',');

export function versionLabel(v: string): string {
  const m = v.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : v;
}

export const TERMS_ARTICLES = (p: TermsParams): { title: string; body: string[] }[] => {
  const editor = [p.seller?.legal_name || 'Souki Deals', p.seller?.legal_form].filter(Boolean).join(' ');
  return [
    {
      title: '1. Objet',
      body: [
        `${editor}${p.seller?.address ? `, ${p.seller.address}` : ''}${p.seller?.siret ? ` (SIRET ${p.seller.siret})` : ''}, ci-après « Souki Deals », édite l'application Souki Deals qui fait connaître aux clients les commerces halal proches de chez eux et leur remet des bons de réduction.`,
        'Les présentes conditions fixent les règles entre Souki Deals et le commerce inscrit (le « Commerçant »). Souki Deals est un intermédiaire : il ne vend aucun produit et n\'intervient pas dans la vente.',
      ],
    },
    {
      title: '2. Inscription et validation',
      body: [
        'Le Commerçant donne des informations exactes et à jour (nom, adresse, SIRET, téléphone, prix). Son commerce n\'est visible des clients qu\'après validation par Souki Deals.',
        'L\'organisme de certification halal éventuellement indiqué est déclaré par le Commerçant, sous sa seule responsabilité. Souki Deals ne certifie aucun produit.',
      ],
    },
    {
      title: '3. Remise accordée aux clients',
      body: [
        `Le Commerçant accorde une remise d'au moins ${n(p.discountMin)} % aux clients qui présentent un bon Souki Deals valide. Il peut choisir une remise plus forte, pour tout le commerce ou par produit.`,
        'Les prix affichés dans l\'application sont ceux du Commerçant, qui les tient à jour. La remise est déduite directement en caisse.',
      ],
    },
    {
      title: '4. Enregistrement des achats',
      body: [
        'En caisse, le Commerçant scanne le bon du client (ou saisit son code) et indique le montant réellement payé, remise déduite. Un bon ne sert qu\'une fois.',
        'Le client confirme l\'achat sur son téléphone ou le conteste. Sans réponse sous 24 heures, l\'achat est confirmé. En cas de contestation, Souki Deals tranche ; un achat annulé ne donne lieu à aucune commission.',
      ],
    },
    {
      title: '5. Commission',
      body: [
        `Pour chaque achat confirmé, le Commerçant doit à Souki Deals une commission de ${n(p.commission)} % du montant payé par le client, toutes taxes comprises.`,
        'Aucune somme n\'est due si l\'application n\'amène aucun achat : il n\'y a ni abonnement ni frais d\'inscription.',
        `Offre de lancement : les ${p.launchSlots} premiers commerces validés ne paient aucune commission pendant ${p.launchMonths} mois à compter de leur validation.`,
      ],
    },
    {
      title: '6. Paiement et factures',
      body: [
        'Chaque lundi, les commissions des achats confirmés de la semaine précédente sont prélevées sur la carte bancaire enregistrée par le Commerçant.',
        'Chaque paiement donne lieu à une facture envoyée par e-mail et disponible dans l\'application (Mon commerce > Mes factures), avec un relevé annuel pour le comptable.',
        'Si un prélèvement est refusé, ou reste impayé 7 jours, le commerce est masqué aux clients jusqu\'au paiement. Tout retard entraîne des pénalités au taux de 3 fois le taux d\'intérêt légal et une indemnité forfaitaire de 40 € pour frais de recouvrement (art. L441-10 du Code de commerce).',
      ],
    },
    {
      title: '7. Engagements et responsabilité',
      body: [
        'Le Commerçant reste seul responsable de ses produits, de leur conformité (hygiène, étiquetage, halal), de ses prix et de l\'accueil des clients.',
        'Souki Deals peut suspendre un commerce en cas de fraude (achats fictifs, montants faux), de prix trompeurs ou de signalements graves et répétés des clients.',
      ],
    },
    {
      title: '8. Données personnelles',
      body: [
        'Le Commerçant ne reçoit des clients que le code de leur bon. Souki Deals traite les données nécessaires au service (compte, achats, factures) conformément au RGPD ; le Commerçant peut demander l\'accès, la rectification ou la suppression de ses données.',
      ],
    },
    {
      title: '9. Durée, résiliation et modification',
      body: [
        'Les conditions s\'appliquent sans durée minimale. Chaque partie peut y mettre fin à tout moment ; les commissions des achats déjà confirmés restent dues.',
        'Toute nouvelle version des conditions est présentée dans l\'application et doit être acceptée par le Commerçant. Souki Deals informe le Commerçant avant toute hausse de la commission ou de la remise minimum.',
      ],
    },
    {
      title: '10. Droit applicable',
      body: [
        'Les présentes conditions sont soumises au droit français. À défaut d\'accord amiable, tout litige relève des tribunaux compétents du siège de Souki Deals.',
      ],
    },
  ];
};

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] as string);

// Page HTML imprimée en PDF par expo-print
export function conditionsHtml(p: TermsParams): string {
  const accepted =
    p.shop && p.acceptedAt
      ? `<div class="box"><b>Acceptation</b><br>
          Commerce : ${esc(p.shop.name)}${p.shop.siret ? ` · SIRET ${esc(p.shop.siret)}` : ''}<br>
          ${p.shop.address ? `${esc(p.shop.address)}<br>` : ''}
          Version acceptée : ${esc(versionLabel(p.acceptedVersion ?? ''))} · le ${esc(new Date(p.acceptedAt).toLocaleDateString('fr-FR'))} à ${esc(
            new Date(p.acceptedAt).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }),
          )}<br>
          Taux acceptés : remise minimum ${n(p.acceptedDiscountMin ?? p.discountMin)} %, commission ${n(p.acceptedCommission ?? p.commission)} % TTC du montant payé
        </div>`
      : '';
  const articles = TERMS_ARTICLES(p)
    .map((a) => `<h2>${esc(a.title)}</h2>${a.body.map((b) => `<p>${esc(b)}</p>`).join('')}`)
    .join('');
  return `<!doctype html><html><head><meta charset="utf-8"><style>
  * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  @page { margin: 18mm 16mm; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1f; font-size: 10.5pt; line-height: 1.45; }
  .band { background: #4A1650; color: #fff; padding: 10px 14px; font-weight: bold; font-size: 14pt; }
  h1 { color: #4A1650; font-size: 18pt; margin: 18px 0 2px; }
  .muted { color: #666; font-size: 9pt; }
  h2 { color: #4A1650; font-size: 11.5pt; margin: 14px 0 4px; }
  p { margin: 0 0 6px; }
  .box { border: 1.5px solid #E89F1C; padding: 10px 12px; margin: 14px 0; font-size: 10pt; }
</style></head><body>
  <div class="band">Souki Deals</div>
  <h1>Conditions commerçant</h1>
  <div class="muted">Version du ${esc(versionLabel(TERMS_VERSION))}</div>
  ${accepted}
  ${articles}
</body></html>`;
}
