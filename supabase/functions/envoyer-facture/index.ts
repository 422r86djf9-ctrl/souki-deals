// SOUKI DEALS — Edge Function « envoyer-facture »
// Appelée par la base dès qu'une facture de commission est créée (et pour les nouveaux essais).
// 1. lit la facture, 2. fabrique le PDF, 3. le range dans le stockage privé « factures »,
// 4. l'envoie au commerçant par e-mail (Resend), 5. note le résultat sur la facture.
//
// Secrets à créer dans Supabase > Edge Functions > Secrets :
//   RESEND_API_KEY        clé de l'API Resend (resend.com)
//   FACTURES_EXPEDITEUR   ex. « Souki Deals <factures@soukideals.fr> » (domaine vérifié chez Resend)
// SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournis automatiquement par Supabase.
// Réglage de la fonction : « Verify JWT » désactivé (la base l'appelle sans jeton).

import { createClient } from 'npm:@supabase/supabase-js@2';
import { PDFDocument, PDFFont, PDFPage, rgb, StandardFonts } from 'npm:pdf-lib@1.17.1';

type Party = {
  legal_name?: string | null;
  legal_form?: string | null;
  capital?: string | null;
  address?: string | null;
  siret?: string | null;
  rcs?: string | null;
  vat_number?: string | null;
  email?: string | null;
  name?: string | null;
  zone?: string | null;
};

type Invoice = {
  id: string;
  number: string;
  shop_id: string | null;
  issued_at: string;
  paid_at: string | null;
  period_start: string;
  period_end: string;
  purchases_count: number;
  sales_cents: number;
  commission_rate: number | null;
  amount_ht_cents: number;
  vat_rate: number;
  vat_cents: number;
  amount_ttc_cents: number;
  welcome_cents?: number | null;
  net_cents?: number | null;
  seller: Party;
  buyer: Party;
  email_to: string | null;
  email_status: 'pending' | 'sent' | 'failed';
  pdf_path: string | null;
};

const PRUNE = rgb(0x4a / 255, 0x16 / 255, 0x50 / 255);
const SAFRAN = rgb(0xe8 / 255, 0x9f / 255, 0x1c / 255);
const GRIS = rgb(0.4, 0.4, 0.42);
const NOIR = rgb(0.1, 0.1, 0.12);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

// 1900 -> « 19,00 € »
function euros(cents: number): string {
  const neg = cents < 0;
  const abs = Math.abs(Math.round(cents));
  const ent = Math.floor(abs / 100)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  return `${neg ? '-' : ''}${ent},${String(abs % 100).padStart(2, '0')} €`;
}

// « 2026-10-05 » ou horodatage -> « 05/10/2026 » (heure de Paris)
function dateFr(iso: string): string {
  const d = /^\d{4}-\d{2}-\d{2}$/.test(iso) ? new Date(`${iso}T12:00:00Z`) : new Date(iso);
  return new Intl.DateTimeFormat('fr-FR', { timeZone: 'Europe/Paris', day: '2-digit', month: '2-digit', year: 'numeric' }).format(d);
}

function pct(n: number | null | undefined): string {
  return `${String(Number(n ?? 0)).replace('.', ',')} %`;
}

// Les polices standard du PDF ne connaissent que l'alphabet latin : le reste (arabe…) est retiré
const EXTRA = '€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ';
function clean(s: string | null | undefined): string {
  return Array.from(String(s ?? ''))
    .map((ch) => {
      if (ch === '\n') return ch;
      if (ch === '\u202f' || ch === '\u00a0' || ch === '\t') return ' ';
      const c = ch.charCodeAt(0);
      if ((c >= 0x20 && c <= 0x7e) || (c >= 0xa1 && c <= 0xff) || EXTRA.includes(ch)) return ch;
      return '';
    })
    .join('')
    .replace(/ {2,}/g, ' ')
    .replace(/ +\n/g, '\n')
    .trim();
}

function wrap(text: string, font: PDFFont, size: number, width: number): string[] {
  const lines: string[] = [];
  for (const para of clean(text).split('\n')) {
    let line = '';
    for (const word of para.split(' ')) {
      const next = line ? `${line} ${word}` : word;
      if (font.widthOfTextAtSize(next, size) <= width) line = next;
      else {
        if (line) lines.push(line);
        line = word;
      }
    }
    lines.push(line);
  }
  return lines;
}

async function buildPdf(inv: Invoice): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  doc.setTitle(`Facture ${inv.number}`);
  doc.setAuthor(clean(inv.seller.legal_name ?? 'Souki Deals'));
  const page: PDFPage = doc.addPage([595.28, 841.89]); // A4
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const L = 50;
  const R = 545;
  let y = 790;

  const text = (s: string, x: number, yy: number, o: { size?: number; f?: PDFFont; color?: ReturnType<typeof rgb> } = {}) =>
    page.drawText(clean(s), { x, y: yy, size: o.size ?? 10, font: o.f ?? font, color: o.color ?? NOIR });
  const right = (s: string, xr: number, yy: number, o: { size?: number; f?: PDFFont; color?: ReturnType<typeof rgb> } = {}) => {
    const f = o.f ?? font;
    const size = o.size ?? 10;
    text(s, xr - f.widthOfTextAtSize(clean(s), size), yy, o);
  };
  const block = (s: string, x: number, yy: number, width: number, size = 10, f: PDFFont = font, color = NOIR) => {
    let cy = yy;
    for (const line of wrap(s, f, size, width)) {
      text(line, x, cy, { size, f, color });
      cy -= size + 3;
    }
    return cy;
  };

  // En-tête
  page.drawRectangle({ x: 0, y: 812, width: 595.28, height: 30, color: PRUNE });
  text('Souki Deals', L, 822, { size: 13, f: bold, color: rgb(1, 1, 1) });
  right('Le halal au meilleur prix', R, 822, { size: 10, color: rgb(1, 1, 1) });

  y = 775;
  text('FACTURE', L, y, { size: 22, f: bold, color: PRUNE });
  right(`N° ${inv.number}`, R, y + 4, { size: 12, f: bold });
  right(`Date d'émission : ${dateFr(inv.issued_at)}`, R, y - 12, { size: 10, color: GRIS });

  // Vendeur
  y = 735;
  const s = inv.seller;
  text('Émetteur', L, y, { size: 9, f: bold, color: GRIS });
  let ys = y - 14;
  ys = block([s.legal_name, s.legal_form].filter(Boolean).join(' '), L, ys, 230, 11, bold);
  ys = block(s.address ?? '', L, ys, 230);
  if (s.siret) ys = block(`SIRET ${s.siret}`, L, ys, 230);
  if (s.vat_number) ys = block(`TVA intracommunautaire ${s.vat_number}`, L, ys, 230);
  if (s.email) ys = block(s.email, L, ys, 230);

  // Client
  const b = inv.buyer;
  const X2 = 320;
  text('Client', X2, y, { size: 9, f: bold, color: GRIS });
  page.drawRectangle({ x: X2 - 8, y: y - 92, width: R - X2 + 8, height: 86, borderColor: PRUNE, borderWidth: 0.8 });
  let yb = y - 18;
  yb = block(b.name ?? '', X2, yb, R - X2 - 6, 11, bold);
  yb = block([b.address, b.zone].filter(Boolean).join(', '), X2, yb, R - X2 - 6);
  if (b.siret) yb = block(`SIRET ${b.siret}`, X2, yb, R - X2 - 6);
  if (b.email) block(b.email, X2, yb, R - X2 - 6, 9, font, GRIS);

  // Période et paiement
  y = Math.min(ys, y - 100) - 14;
  text(`Période : du ${dateFr(inv.period_start)} au ${dateFr(inv.period_end)}`, L, y);
  text(`Payée le : ${dateFr(inv.paid_at ?? inv.issued_at)} (carte bancaire)`, X2, y);

  // Tableau
  y -= 28;
  page.drawRectangle({ x: L, y: y - 6, width: R - L, height: 22, color: PRUNE });
  text('Désignation', L + 8, y, { f: bold, color: rgb(1, 1, 1) });
  right('Montant HT', R - 8, y, { f: bold, color: rgb(1, 1, 1) });
  y -= 26;
  const designation =
    `Commission Souki Deals : mise en relation de clients par l'application` +
    (inv.commission_rate != null ? ` (${pct(inv.commission_rate)} des ventes confirmées)` : '') +
    `.\n${inv.purchases_count} achat${inv.purchases_count > 1 ? 's' : ''} pour ${euros(inv.sales_cents)} de ventes, du ${dateFr(inv.period_start)} au ${dateFr(inv.period_end)}.`;
  const yEnd = block(designation, L + 8, y, 360);
  right(euros(inv.amount_ht_cents), R - 8, y, { f: bold });
  y = yEnd - 6;
  page.drawLine({ start: { x: L, y }, end: { x: R, y }, thickness: 0.6, color: GRIS });

  // Totaux
  y -= 22;
  const row = (label: string, value: string, strong = false) => {
    text(label, 340, y, { f: strong ? bold : font, size: strong ? 12 : 10 });
    right(value, R - 8, y, { f: strong ? bold : font, size: strong ? 12 : 10 });
    y -= strong ? 22 : 16;
  };
  row('Total HT', euros(inv.amount_ht_cents));
  if (Number(inv.vat_rate) > 0) row(`TVA ${pct(inv.vat_rate)}`, euros(inv.vat_cents));
  else row('TVA', '0,00 €');
  y -= 6;
  page.drawRectangle({ x: 330, y: y - 6, width: R - 330, height: 24, color: rgb(0.96, 0.93, 0.97) });
  row('Total TTC', euros(inv.amount_ttc_cents), true);
  if (Number(inv.vat_rate) === 0) {
    text('TVA non applicable, art. 293 B du CGI', 340, y, { size: 9, color: GRIS });
    y -= 16;
  }

  // Offres de bienvenue Souki Deals remboursées au commerçant, déduites du paiement
  const welcome = Number(inv.welcome_cents ?? 0);
  if (welcome > 0) {
    const net = Number(inv.net_cents ?? inv.amount_ttc_cents - welcome);
    y -= 4;
    text('Bienvenues remboursées', 340, y, { size: 9 });
    right(`-${euros(welcome)}`, R - 8, y, { size: 9 });
    y -= 14;
    text(net >= 0 ? 'Montant prélevé' : 'Montant versé au client', 340, y, { size: 9, f: bold });
    right(euros(Math.abs(net)), R - 8, y, { size: 9, f: bold });
    y -= 16;
  }

  // Tampon « acquittée »
  y -= 8;
  page.drawRectangle({ x: L, y: y - 8, width: 150, height: 26, borderColor: SAFRAN, borderWidth: 1.5 });
  text('FACTURE ACQUITTÉE', L + 14, y, { f: bold, size: 11, color: SAFRAN });
  text('Net à payer : 0,00 €', L + 170, y, { f: bold, size: 10 });

  // Mentions obligatoires
  let yf = 140;
  const legal = [
    'Nature de l\'opération : prestation de services. Facture réglée par prélèvement sur carte bancaire à la date indiquée ; aucun escompte pour paiement anticipé.',
    'En cas de retard de paiement : pénalités au taux de 3 fois le taux d\'intérêt légal et indemnité forfaitaire de 40 € pour frais de recouvrement (art. L441-10 et D441-5 du Code de commerce).',
    [
      s.legal_name,
      s.legal_form,
      s.capital ? `au capital de ${s.capital}` : null,
      s.siret ? `SIRET ${s.siret}` : null,
      s.rcs,
      s.vat_number ? `TVA ${s.vat_number}` : null,
      s.address,
    ]
      .filter(Boolean)
      .join(' · '),
  ];
  page.drawLine({ start: { x: L, y: yf + 14 }, end: { x: R, y: yf + 14 }, thickness: 0.5, color: GRIS });
  for (const p of legal) yf = block(p, L, yf, R - L, 8, font, GRIS) - 4;

  return await doc.save();
}

function toBase64(bytes: Uint8Array): string {
  let bin = '';
  const step = 0x8000;
  for (let i = 0; i < bytes.length; i += step) bin += String.fromCharCode(...bytes.subarray(i, i + step));
  return btoa(bin);
}

function emailHtml(inv: Invoice): string {
  const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] as string);
  return `<div style="font-family:Arial,sans-serif;color:#1a1a1f;max-width:560px">
  <div style="background:#4A1650;color:#fff;padding:14px 18px;font-weight:bold;font-size:18px">Souki Deals</div>
  <div style="padding:18px">
    <p>Bonjour ${esc(inv.buyer.name ?? '')},</p>
    <p>Merci pour votre paiement. Vous trouverez ci-joint la facture <b>${esc(inv.number)}</b> de votre commission Souki Deals.</p>
    <table style="border-collapse:collapse;width:100%;margin:12px 0">
      <tr><td style="padding:6px 0;color:#666">Période</td><td style="text-align:right">du ${dateFr(inv.period_start)} au ${dateFr(inv.period_end)}</td></tr>
      <tr><td style="padding:6px 0;color:#666">Ventes amenées</td><td style="text-align:right">${inv.purchases_count} achat(s) · ${euros(inv.sales_cents)}</td></tr>
      <tr><td style="padding:6px 0;color:#666">Commission (TTC)</td><td style="text-align:right;font-weight:bold">${euros(inv.amount_ttc_cents)}</td></tr>
      ${Number(inv.welcome_cents ?? 0) > 0 ? `<tr><td style="padding:6px 0;color:#666">Offres de bienvenue remboursées</td><td style="text-align:right">-${euros(Number(inv.welcome_cents))}</td></tr>` : ''}
    </table>
    <p>Vos factures restent disponibles dans l'application : <b>Mon commerce &gt; Mes factures</b>.</p>
    <p style="color:#666;font-size:12px">${esc([inv.seller.legal_name, inv.seller.address].filter(Boolean).join(' · '))}</p>
  </div>
</div>`;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'POST attendu' }, 405);
  let id = '';
  try {
    id = String(((await req.json()) as { invoice_id?: string }).invoice_id ?? '');
  } catch {
    return json({ error: 'Corps JSON invalide' }, 400);
  }
  if (!/^[0-9a-f-]{36}$/i.test(id)) return json({ error: 'invoice_id invalide' }, 400);

  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false },
  });
  const { data, error } = await sb.from('invoices').select('*').eq('id', id).maybeSingle();
  if (error) return json({ error: error.message }, 500);
  const inv = data as Invoice | null;
  // Seules les factures « à envoyer » sont traitées : un appel en double ne renvoie rien
  if (!inv || inv.email_status !== 'pending') return json({ ok: true, skipped: true });

  const fail = async (message: string) => {
    await sb.from('invoices').update({ email_error: message.slice(0, 500) }).eq('id', id);
    return json({ ok: false, error: message }, 200);
  };

  try {
    // PDF, rangé dans le stockage privé (le commerçant le retrouve dans l'appli)
    const pdf = await buildPdf(inv);
    const path = `${inv.shop_id ?? 'sans-commerce'}/${inv.number}.pdf`;
    const up = await sb.storage.from('factures').upload(path, pdf, { contentType: 'application/pdf', upsert: true });
    if (up.error) return await fail(`Stockage du PDF : ${up.error.message}`);
    await sb.from('invoices').update({ pdf_path: path }).eq('id', id);

    const key = Deno.env.get('RESEND_API_KEY');
    const from = Deno.env.get('FACTURES_EXPEDITEUR');
    if (!key || !from) return await fail('Envoi d’e-mail non configuré (secrets RESEND_API_KEY et FACTURES_EXPEDITEUR).');
    if (!inv.email_to) return await fail('Aucune adresse e-mail pour ce commerce.');

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from,
        to: [inv.email_to],
        reply_to: inv.seller.email || undefined,
        subject: `Votre facture Souki Deals ${inv.number}`,
        html: emailHtml(inv),
        text:
          `Bonjour,\n\nMerci pour votre paiement. Votre facture ${inv.number} (commission de ${euros(inv.amount_ttc_cents)} TTC, ` +
          `du ${dateFr(inv.period_start)} au ${dateFr(inv.period_end)}) est jointe à ce message.\n` +
          `Elle reste disponible dans l'application : Mon commerce > Mes factures.\n\nSouki Deals`,
        attachments: [{ filename: `Facture-${inv.number}.pdf`, content: toBase64(pdf) }],
      }),
    });
    if (!res.ok) return await fail(`E-mail refusé (${res.status}) : ${(await res.text()).slice(0, 300)}`);

    await sb.from('invoices').update({ email_status: 'sent', email_sent_at: new Date().toISOString(), email_error: null }).eq('id', id);
    return json({ ok: true, sent: inv.email_to });
  } catch (e) {
    return await fail(`Erreur : ${e instanceof Error ? e.message : String(e)}`);
  }
});
