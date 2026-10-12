// Relevé annuel du commerçant pour son comptable : PDF récapitulatif et fichiers Excel (CSV)
import * as FileSystem from 'expo-file-system/legacy';
import * as Print from 'expo-print';
import * as Sharing from 'expo-sharing';
import { conditionsHtml, TermsParams } from './conditions';

export type StatementInvoice = {
  number: string;
  issued_at: string;
  paid_at: string | null;
  period_start: string;
  period_end: string;
  purchases_count: number;
  sales_cents: number;
  amount_ht_cents: number;
  vat_rate: number;
  vat_cents: number;
  amount_ttc_cents: number;
};
export type StatementPurchase = {
  date: string;
  amount_cents: number;
  discount_pct: number;
  discount_cents: number;
  commission_cents: number;
  free: boolean;
  status: 'pending' | 'confirmed' | 'disputed';
  invoice: string | null;
};
export type StatementMonth = {
  month: number;
  purchases_count: number;
  sales_cents: number;
  discount_cents: number;
  invoices_count: number;
  ht_cents: number;
  vat_cents: number;
  ttc_cents: number;
};
export type Statement = {
  year: number;
  generated_at: string;
  shop: { name: string; address: string; zone: string | null; siret: string | null; email: string | null; discount_pct: number };
  terms: {
    version: string | null;
    accepted_at: string | null;
    commission_rate: number | null;
    discount_min: number | null;
    current_version: string;
  };
  seller: { legal_name: string; legal_form: string | null; address: string | null; siret: string | null; vat_number: string | null };
  invoices: StatementInvoice[];
  purchases: StatementPurchase[];
  months: StatementMonth[];
  unbilled_cents: number;
  offered_cents: number;
};

const MONTHS = ['Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin', 'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'];

const esc = (s: string | null | undefined) =>
  String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] as string);

// 184250 -> « 1 842,50 € » ; pour Excel : « 1842,50 »
export function eur(cents: number): string {
  const v = Math.round(cents);
  const abs = Math.abs(v);
  const ent = Math.floor(abs / 100)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  return `${v < 0 ? '-' : ''}${ent},${String(abs % 100).padStart(2, '0')} €`;
}
function num(cents: number): string {
  const v = Math.round(cents);
  const abs = Math.abs(v);
  return `${v < 0 ? '-' : ''}${Math.floor(abs / 100)},${String(abs % 100).padStart(2, '0')}`;
}
function d(iso: string | null | undefined): string {
  if (!iso) return '';
  const x = /^\d{4}-\d{2}-\d{2}$/.test(iso) ? new Date(`${iso}T12:00:00`) : new Date(iso);
  return `${String(x.getDate()).padStart(2, '0')}/${String(x.getMonth() + 1).padStart(2, '0')}/${x.getFullYear()}`;
}
function hm(iso: string): string {
  const x = new Date(iso);
  return `${String(x.getHours()).padStart(2, '0')}:${String(x.getMinutes()).padStart(2, '0')}`;
}
const pct = (x: number | null | undefined) => `${String(Number(x ?? 0)).replace('.', ',')} %`;

export function totals(s: Statement) {
  const sum = <T,>(a: T[], f: (x: T) => number) => a.reduce((acc, x) => acc + f(x), 0);
  return {
    invoices: s.invoices.length,
    ht: sum(s.invoices, (i) => i.amount_ht_cents),
    vat: sum(s.invoices, (i) => i.vat_cents),
    ttc: sum(s.invoices, (i) => i.amount_ttc_cents),
    purchases: s.purchases.length,
    sales: sum(s.purchases, (p) => p.amount_cents),
    discounts: sum(s.purchases, (p) => p.discount_cents),
  };
}

export function statementHtml(s: Statement): string {
  const t = totals(s);
  const rows = s.months
    .map(
      (m) => `<tr><td>${MONTHS[m.month - 1]}</td><td class="r">${m.purchases_count}</td><td class="r">${eur(m.sales_cents)}</td>
        <td class="r">${eur(m.discount_cents)}</td><td class="r">${m.invoices_count}</td><td class="r">${eur(m.ht_cents)}</td>
        <td class="r">${eur(m.vat_cents)}</td><td class="r">${eur(m.ttc_cents)}</td></tr>`,
    )
    .join('');
  const inv = s.invoices.length
    ? s.invoices
        .map(
          (i) => `<tr><td>${esc(i.number)}</td><td>${d(i.issued_at)}</td><td>${d(i.period_start)} – ${d(i.period_end)}</td>
            <td class="r">${eur(i.amount_ht_cents)}</td><td class="r">${pct(i.vat_rate)}</td><td class="r">${eur(i.vat_cents)}</td>
            <td class="r">${eur(i.amount_ttc_cents)}</td><td>${d(i.paid_at)}</td></tr>`,
        )
        .join('')
    : `<tr><td colspan="8" class="muted">Aucune facture sur l'année.</td></tr>`;
  return `<!doctype html><html><head><meta charset="utf-8"><style>
  * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  @page { margin: 14mm 12mm; }
  body { font-family: Helvetica, Arial, sans-serif; color: #1a1a1f; font-size: 9.5pt; }
  .band { background: #4A1650; color: #fff; padding: 9px 12px; font-weight: bold; font-size: 13pt; }
  h1 { color: #4A1650; font-size: 17pt; margin: 14px 0 2px; }
  h2 { color: #4A1650; font-size: 11pt; margin: 16px 0 6px; }
  .muted { color: #666; font-size: 8.5pt; }
  .cols { display: flex; gap: 16px; margin-top: 10px; }
  .cols > div { flex: 1; border: 1px solid #ddd; padding: 8px 10px; }
  .kpis { display: flex; flex-wrap: wrap; gap: 8px; }
  .kpi { flex: 1 1 30%; background: #F5EEF6; padding: 8px 10px; }
  .kpi b { display: block; font-size: 12.5pt; color: #4A1650; }
  table { width: 100%; border-collapse: collapse; }
  th { background: #4A1650; color: #fff; text-align: left; padding: 5px 6px; font-size: 8.5pt; }
  td { border-bottom: 1px solid #e5e5e5; padding: 4px 6px; }
  .r { text-align: right; }
  tfoot td { font-weight: bold; border-top: 1.5px solid #4A1650; }
  .note { border-left: 3px solid #E89F1C; padding: 6px 10px; background: #FDF6EA; margin-top: 12px; }
</style></head><body>
  <div class="band">Souki Deals</div>
  <h1>Relevé annuel ${s.year}</h1>
  <div class="muted">Commissions et ventes amenées par Souki Deals · édité le ${d(s.generated_at)}</div>
  <div class="cols">
    <div><b>${esc(s.shop.name)}</b><br>${esc(s.shop.address)}${s.shop.zone ? `, ${esc(s.shop.zone)}` : ''}<br>
      ${s.shop.siret ? `SIRET ${esc(s.shop.siret)}<br>` : ''}${esc(s.shop.email)}</div>
    <div><b>Fournisseur : ${esc([s.seller.legal_name, s.seller.legal_form].filter(Boolean).join(' '))}</b><br>
      ${esc(s.seller.address)}<br>${s.seller.siret ? `SIRET ${esc(s.seller.siret)}<br>` : ''}${s.seller.vat_number ? `TVA ${esc(s.seller.vat_number)}` : ''}</div>
  </div>

  <h2>Récapitulatif de l'année</h2>
  <div class="kpis">
    <div class="kpi">Commissions HT<b>${eur(t.ht)}</b></div>
    <div class="kpi">TVA sur commissions<b>${eur(t.vat)}</b></div>
    <div class="kpi">Commissions TTC payées<b>${eur(t.ttc)}</b></div>
    <div class="kpi">Factures<b>${t.invoices}</b></div>
    <div class="kpi">Ventes amenées (${t.purchases} achats)<b>${eur(t.sales)}</b></div>
    <div class="kpi">Remises accordées aux clients<b>${eur(t.discounts)}</b></div>
  </div>
  ${s.offered_cents > 0 ? `<p class="muted">Commission offerte (offre de lancement) : ${eur(s.offered_cents)} — non facturée.</p>` : ''}
  ${s.unbilled_cents > 0 ? `<p class="muted">Commission de ${s.year} pas encore prélevée à la date du relevé : ${eur(s.unbilled_cents)} (facturée au prochain prélèvement).</p>` : ''}

  <h2>Mois par mois</h2>
  <table><thead><tr><th>Mois</th><th class="r">Achats</th><th class="r">Ventes amenées</th><th class="r">Remises</th>
    <th class="r">Factures</th><th class="r">HT</th><th class="r">TVA</th><th class="r">TTC</th></tr></thead>
    <tbody>${rows}</tbody>
    <tfoot><tr><td>Total</td><td class="r">${t.purchases}</td><td class="r">${eur(t.sales)}</td><td class="r">${eur(t.discounts)}</td>
      <td class="r">${t.invoices}</td><td class="r">${eur(t.ht)}</td><td class="r">${eur(t.vat)}</td><td class="r">${eur(t.ttc)}</td></tr></tfoot>
  </table>
  <p class="muted">Achats classés selon leur date ; factures selon leur date d'émission (une facture du début janvier peut couvrir la fin de l'année précédente).</p>

  <h2>Factures de l'année</h2>
  <table><thead><tr><th>N°</th><th>Émise le</th><th>Période</th><th class="r">HT</th><th class="r">Taux</th><th class="r">TVA</th><th class="r">TTC</th><th>Payée le</th></tr></thead>
    <tbody>${inv}</tbody></table>

  <div class="note"><b>Pour le comptable</b><br>
    Les commissions Souki Deals sont des charges (compte 622 « Rémunérations d'intermédiaires », par exemple 6222 « Commissions et courtages »), justifiées par les factures ci-dessus, payées par carte bancaire.
    Les remises clients sont déjà déduites des montants encaissés : elles ne demandent pas d'écriture supplémentaire.
    Le détail des achats et des factures est fourni en fichiers Excel (CSV).</div>
</body></html>`;
}

// CSV pour Excel en français : séparateur « ; », virgule décimale, BOM pour les accents
function csv(rows: (string | number)[][]): string {
  const cell = (v: string | number) => {
    const s = String(v);
    return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return '\ufeff' + rows.map((r) => r.map(cell).join(';')).join('\r\n') + '\r\n';
}

export function invoicesCsv(s: Statement): string {
  return csv([
    ['Numéro', "Date d'émission", 'Date de paiement', 'Période du', 'Période au', 'Nombre d’achats', 'Ventes amenées (€)', 'Montant HT (€)', 'Taux TVA (%)', 'TVA (€)', 'Montant TTC (€)'],
    ...s.invoices.map((i) => [
      i.number,
      d(i.issued_at),
      d(i.paid_at),
      d(i.period_start),
      d(i.period_end),
      i.purchases_count,
      num(i.sales_cents),
      num(i.amount_ht_cents),
      String(Number(i.vat_rate)).replace('.', ','),
      num(i.vat_cents),
      num(i.amount_ttc_cents),
    ]),
  ]);
}

export function purchasesCsv(s: Statement): string {
  const status = (x: StatementPurchase['status']) => (x === 'confirmed' ? 'Confirmé' : x === 'disputed' ? 'Contesté' : 'En attente du client');
  return csv([
    ['Date', 'Heure', 'Montant payé (€)', 'Remise (%)', 'Remise accordée (€)', 'Commission (€)', 'Commission offerte', 'Statut', 'Facture'],
    ...s.purchases.map((p) => [
      d(p.date),
      hm(p.date),
      num(p.amount_cents),
      String(Number(p.discount_pct)).replace('.', ','),
      num(p.discount_cents),
      num(p.commission_cents),
      p.free ? 'Oui' : 'Non',
      status(p.status),
      p.invoice ?? '',
    ]),
  ]);
}

function slug(s: string): string {
  return (
    s
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .replace(/[^A-Za-z0-9]+/g, '-')
      .replace(/^-|-$/g, '')
      .slice(0, 40) || 'commerce'
  );
}

// Fabrique un PDF et ouvre le partage (e-mail au comptable, Fichiers, WhatsApp…)
async function sharePdf(html: string, name: string) {
  const { uri } = await Print.printToFileAsync({ html });
  const dest = `${FileSystem.cacheDirectory}${name}.pdf`;
  await FileSystem.deleteAsync(dest, { idempotent: true });
  await FileSystem.moveAsync({ from: uri, to: dest });
  await Sharing.shareAsync(dest, { mimeType: 'application/pdf', UTI: 'com.adobe.pdf', dialogTitle: name });
}

async function shareCsv(text: string, name: string) {
  const dest = `${FileSystem.cacheDirectory}${name}.csv`;
  await FileSystem.writeAsStringAsync(dest, text, { encoding: FileSystem.EncodingType.UTF8 });
  await Sharing.shareAsync(dest, { mimeType: 'text/csv', UTI: 'public.comma-separated-values-text', dialogTitle: name });
}

export const shareStatementPdf = (s: Statement) => sharePdf(statementHtml(s), `Souki-Deals-releve-${s.year}-${slug(s.shop.name)}`);
export const shareInvoicesCsv = (s: Statement) => shareCsv(invoicesCsv(s), `Souki-Deals-factures-${s.year}-${slug(s.shop.name)}`);
export const sharePurchasesCsv = (s: Statement) => shareCsv(purchasesCsv(s), `Souki-Deals-achats-${s.year}-${slug(s.shop.name)}`);
export const shareConditionsPdf = (p: TermsParams) => sharePdf(conditionsHtml(p), `Souki-Deals-conditions${p.shop ? `-${slug(p.shop.name)}` : ''}`);

// PDF libre (autocollant du QR code du magasin…)
export const shareHtmlAsPdf = (html: string, name: string) => sharePdf(html, name);
