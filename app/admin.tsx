// Administration (fondateur uniquement)
import { Stack, router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { ActivityIndicator, Alert, Linking, Pressable, RefreshControl, ScrollView, Text, View } from 'react-native';
import { euros, fullDate, Invoice, invoiceEmailLabel, kindLabel, shortDate, Zone } from '../src/lib/deals';
import { t, zoneLabel } from '../src/lib/i18n';
import { errorMessage, supabase, whoami } from '../src/lib/supabase';
import { Button, Chip, colors, ErrorText, Field, InfoText, Muted, SectionTitle, styles } from '../src/lib/theme';

type Tab = 'summary' | 'shops' | 'disputes' | 'charges' | 'invoices' | 'reports' | 'settings';
type Summary = Record<string, number> & { company_ready?: boolean };
type Company = {
  legal_name: string | null;
  legal_form: string | null;
  capital: string | null;
  address: string | null;
  siret: string | null;
  rcs: string | null;
  vat_number: string | null;
  email: string | null;
  vat_rate: number;
  invoice_prefix: string;
};
type CKey = keyof Company;
const COMPANY_FIELDS: { key: CKey; label: string; placeholder?: string }[] = [
  { key: 'legal_name', label: 'Raison sociale', placeholder: 'Souki Deals' },
  { key: 'legal_form', label: 'Forme juridique', placeholder: 'SAS, SASU, EURL, micro-entreprise…' },
  { key: 'capital', label: 'Capital social', placeholder: '1 000 €' },
  { key: 'address', label: 'Adresse du siège' },
  { key: 'siret', label: 'SIRET (14 chiffres)' },
  { key: 'rcs', label: 'RCS', placeholder: 'RCS Paris 123 456 789' },
  { key: 'vat_number', label: 'N° de TVA intracommunautaire', placeholder: 'FR12345678901' },
  { key: 'email', label: 'E-mail de réponse aux factures' },
  { key: 'vat_rate', label: 'TVA comprise dans la commission (%) — 0 si franchise' },
  { key: 'invoice_prefix', label: 'Préfixe des numéros de facture' },
];
type ShopRow = {
  id: string;
  owner_id: string;
  name: string;
  kind: string;
  status: 'pending' | 'active' | 'suspended';
  address: string;
  phone: string | null;
  siret: string | null;
  halal_cert: string | null;
  launch_offer: boolean;
  free_until: string | null;
  card_ok: boolean;
  discount_pct: number;
  created_at: string;
  zones: { name: string } | null;
};
type Dispute = { id: string; amount_cents: number; dispute_reason: string | null; created_at: string; shops: { name: string } | null };
type ChargeRow = { id: string; week_start: string; amount_cents: number; status: 'pending' | 'paid' | 'failed' | 'waived'; shops: { name: string } | null };
type AdminInvoice = Invoice & { charge_id: string | null };
type ReportRow = { id: number; kind: string; body: string; created_at: string; shops: { name: string } | null };
type Settings = {
  discount_min: number;
  commission_rate: number;
  voucher_hours: number;
  max_active_vouchers: number;
  cooldown_minutes: number;
  max_purchase_cents: number;
  confirm_hours: number;
  launch_slots: number;
  launch_free_months: number;
};
type SKey = keyof Settings;
const FIELDS: { key: SKey; label: string; decimal?: boolean }[] = [
  { key: 'discount_min', label: 'Remise client minimum (%)', decimal: true },
  { key: 'commission_rate', label: 'Commission Souki Deals (%)', decimal: true },
  { key: 'launch_slots', label: 'Places de l’offre de lancement' },
  { key: 'launch_free_months', label: 'Mois sans commission (lancement)' },
  { key: 'voucher_hours', label: 'Validité d’un bon (heures)' },
  { key: 'max_active_vouchers', label: 'Bons en cours par client' },
  { key: 'cooldown_minutes', label: 'Délai entre deux achats au même endroit (minutes)' },
  { key: 'max_purchase_cents', label: 'Montant maximum d’un achat (centimes)' },
  { key: 'confirm_hours', label: 'Confirmation automatique après (heures)' },
];

function statusLabel(s: ShopRow['status']) {
  if (s === 'pending') return t('En validation');
  if (s === 'suspended') return t('Suspendu');
  return t('Actif');
}

export default function Admin() {
  const [tab, setTab] = useState<Tab>('summary');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');
  const [summary, setSummary] = useState<Summary | null>(null);
  const [shops, setShops] = useState<ShopRow[]>([]);
  const [owners, setOwners] = useState<Record<string, { full_name: string | null; phone: string | null }>>({});
  const [disputes, setDisputes] = useState<Dispute[]>([]);
  const [charges, setCharges] = useState<ChargeRow[]>([]);
  const [reports, setReports] = useState<ReportRow[]>([]);
  const [zones, setZones] = useState<Zone[]>([]);
  const [form, setForm] = useState<Record<SKey, string> | null>(null);
  const [invoices, setInvoices] = useState<AdminInvoice[]>([]);
  const [company, setCompany] = useState<Record<CKey, string> | null>(null);

  const load = useCallback(async () => {
    setError('');
    try {
      const me = await whoami();
      if (!me.is_admin) {
        router.back();
        return;
      }
      const [s, sh, d, c, r, z, st, inv, co] = await Promise.all([
        supabase.rpc('admin_summary'),
        supabase
          .from('shops')
          .select('id, owner_id, name, kind, status, address, phone, siret, halal_cert, launch_offer, free_until, card_ok, discount_pct, created_at, zones(name)')
          .order('status')
          .order('created_at', { ascending: false }),
        supabase.from('purchases').select('id, amount_cents, dispute_reason, created_at, shops(name)').eq('status', 'disputed').order('created_at'),
        supabase.from('charges').select('id, week_start, amount_cents, status, shops(name)').order('week_start', { ascending: false }).limit(100),
        supabase.from('reports').select('id, kind, body, created_at, shops(name)').eq('status', 'open').order('created_at'),
        supabase.from('zones').select('id, name, name_en, name_ar, open, sort').order('sort'),
        supabase.from('settings').select('*').eq('id', 1).single(),
        supabase
          .from('invoices')
          .select('id, number, charge_id, issued_at, period_start, period_end, amount_ttc_cents, email_to, email_status, email_error, pdf_path, buyer')
          .order('seq', { ascending: false })
          .limit(100),
        supabase.from('company').select('*').eq('id', 1).maybeSingle(),
      ]);
      if (s.error) throw s.error;
      setSummary(s.data as Summary);
      const list = (sh.data ?? []) as unknown as ShopRow[];
      setShops(list);
      const ids = list.map((x) => x.owner_id);
      if (ids.length) {
        const { data: pr } = await supabase.from('profiles').select('id, full_name, phone').in('id', ids);
        const m: Record<string, { full_name: string | null; phone: string | null }> = {};
        for (const p of (pr ?? []) as { id: string; full_name: string | null; phone: string | null }[]) m[p.id] = p;
        setOwners(m);
      }
      setDisputes((d.data ?? []) as unknown as Dispute[]);
      setCharges((c.data ?? []) as unknown as ChargeRow[]);
      setReports((r.data ?? []) as unknown as ReportRow[]);
      setZones((z.data ?? []) as Zone[]);
      if (st.data) {
        const f = {} as Record<SKey, string>;
        for (const k of FIELDS) f[k.key] = String((st.data as Settings)[k.key]).replace('.', ',');
        setForm((prev) => prev ?? f);
      }
      setInvoices((inv.data ?? []) as AdminInvoice[]);
      if (co.data) {
        const f = {} as Record<CKey, string>;
        for (const k of COMPANY_FIELDS) {
          const v = (co.data as Company)[k.key];
          f[k.key] = v == null ? '' : String(v).replace('.', ',');
        }
        setCompany((prev) => prev ?? f);
      }
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load]),
  );

  async function rpc(name: string, args: Record<string, unknown>) {
    setBusy(true);
    setError('');
    setInfo('');
    const { error } = await supabase.rpc(name, args);
    setBusy(false);
    if (error) setError(errorMessage(error));
    await load();
  }

  function confirm(title: string, body: string, action: () => void) {
    Alert.alert(title, body, [
      { text: t('Annuler'), style: 'cancel' },
      { text: t('Confirmer'), onPress: action },
    ]);
  }

  async function saveSettings() {
    if (!form) return;
    const n = (k: SKey) => Number(form[k].replace(',', '.'));
    for (const f of FIELDS) {
      const v = n(f.key);
      if (form[f.key].trim() === '' || !Number.isFinite(v) || v < 0 || (!f.decimal && !Number.isInteger(v))) {
        return setError(t('Valeurs invalides : vérifiez les paramètres.'));
      }
    }
    confirm(t('Appliquer ces réglages ?'), t('Ils s’appliquent tout de suite aux nouveaux achats.'), async () => {
      setBusy(true);
      const { error } = await supabase.rpc('admin_update_settings', {
        p_discount_min: n('discount_min'),
        p_commission_rate: n('commission_rate'),
        p_voucher_hours: n('voucher_hours'),
        p_max_active_vouchers: n('max_active_vouchers'),
        p_cooldown_minutes: n('cooldown_minutes'),
        p_max_purchase_cents: n('max_purchase_cents'),
        p_confirm_hours: n('confirm_hours'),
        p_launch_slots: n('launch_slots'),
        p_launch_free_months: n('launch_free_months'),
      });
      setBusy(false);
      if (error) return setError(errorMessage(error));
      setInfo(t('Réglages enregistrés.'));
      setForm(null);
      await load();
    });
  }

  async function saveCompany() {
    if (!company) return;
    const rate = Number(company.vat_rate.replace(',', '.'));
    if (company.vat_rate.trim() === '' || !Number.isFinite(rate) || rate < 0 || rate > 30) return setError(t('Taux de TVA invalide.'));
    confirm(t('Enregistrer les informations de la société ?'), t('Elles figureront sur les prochaines factures. Les factures déjà émises ne changent pas.'), async () => {
      setBusy(true);
      setError('');
      setInfo('');
      const { data, error } = await supabase.rpc('admin_save_company', {
        p_legal_name: company.legal_name,
        p_legal_form: company.legal_form,
        p_capital: company.capital,
        p_address: company.address,
        p_siret: company.siret,
        p_rcs: company.rcs,
        p_vat_number: company.vat_number,
        p_email: company.email,
        p_vat_rate: rate,
        p_invoice_prefix: company.invoice_prefix,
      });
      setBusy(false);
      if (error) return setError(errorMessage(error));
      const issued = Number((data as { issued?: number } | null)?.issued ?? 0);
      setInfo(issued > 0 ? t('Informations enregistrées. {n} facture(s) en attente créée(s) et envoyée(s).', { n: issued }) : t('Informations enregistrées.'));
      setCompany(null);
      await load();
    });
  }

  async function openInvoice(i: Invoice) {
    setError('');
    if (!i.pdf_path) return setInfo(t('Le PDF de cette facture est en préparation. Réessayez dans quelques minutes.'));
    const { data, error } = await supabase.storage.from('factures').createSignedUrl(i.pdf_path, 600);
    if (error || !data?.signedUrl) return setError(t('Impossible d’ouvrir la facture.'));
    Linking.openURL(data.signedUrl);
  }

  if (loading) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;

  const pendingShops = shops.filter((s) => s.status === 'pending').length;
  const invoiceByCharge: Record<string, AdminInvoice> = {};
  for (const i of invoices) if (i.charge_id) invoiceByCharge[i.charge_id] = i;
  const invoiceAlerts = (summary?.invoices_missing ?? 0) + (summary?.invoices_failed ?? 0);

  return (
    <ScrollView
      style={{ backgroundColor: colors.background }}
      contentContainerStyle={{ padding: 16, paddingBottom: 40 }}
      refreshControl={
        <RefreshControl
          refreshing={refreshing}
          onRefresh={async () => {
            setRefreshing(true);
            await load();
            setRefreshing(false);
          }}
        />
      }
    >
      <Stack.Screen options={{ title: t('Administration') }} />
      <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
        <Chip label={t('Résumé')} selected={tab === 'summary'} onPress={() => setTab('summary')} />
        <Chip label={pendingShops ? t('Commerces ({n} à valider)', { n: pendingShops }) : t('Commerces')} selected={tab === 'shops'} onPress={() => setTab('shops')} />
        <Chip label={t('Contestations ({n})', { n: disputes.length })} selected={tab === 'disputes'} onPress={() => setTab('disputes')} />
        <Chip label={t('Prélèvements')} selected={tab === 'charges'} onPress={() => setTab('charges')} />
        <Chip label={invoiceAlerts ? t('Factures ({n} à traiter)', { n: invoiceAlerts }) : t('Factures')} selected={tab === 'invoices'} onPress={() => setTab('invoices')} />
        <Chip label={t('Signalements ({n})', { n: reports.length })} selected={tab === 'reports'} onPress={() => setTab('reports')} />
        <Chip label={t('Réglages')} selected={tab === 'settings'} onPress={() => setTab('settings')} />
      </View>
      <ErrorText>{error}</ErrorText>
      <InfoText>{info}</InfoText>

      {tab === 'summary' && summary ? (
        <View>
          {[
            [t('Achats aujourd’hui'), String(summary.today_count)],
            [t('Ventes amenées aujourd’hui'), euros(summary.today_cents)],
            [t('Commission aujourd’hui'), euros(summary.today_commission)],
            [t('Achats cette semaine'), String(summary.week_count)],
            [t('Commission cette semaine'), euros(summary.week_commission)],
            [t('Commission ce mois-ci'), euros(summary.month_commission)],
            [t('Commission offerte ce mois-ci (lancement)'), euros(summary.offered_month)],
            [t('Commerces actifs'), String(summary.shops_active)],
            [t('Commerces à valider'), String(summary.shops_pending)],
            [t('Places de lancement restantes'), String(summary.launch_slots_left)],
            [t('Bons en cours'), String(summary.vouchers_active)],
            [t('Utilisateurs'), String(summary.users_count)],
            [t('À prélever ou refusé'), euros(summary.charges_pending_cents)],
            [t('Factures émises ce mois-ci'), String(summary.invoices_month ?? 0)],
            [t('Paiements sans facture'), String(summary.invoices_missing ?? 0)],
            [t('Factures non envoyées'), String(summary.invoices_failed ?? 0)],
          ].map(([label, value]) => (
            <View key={label} style={[styles.card, { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 12 }]}>
              <Text style={{ color: colors.text, flex: 1 }}>{label}</Text>
              <Text style={{ fontWeight: '900', color: colors.prune }}>{value}</Text>
            </View>
          ))}
        </View>
      ) : null}

      {tab === 'shops' ? (
        <View>
          {shops.length === 0 ? <Muted>{t('Aucun commerce inscrit.')}</Muted> : null}
          {shops.map((s) => {
            const o = owners[s.owner_id];
            return (
              <View key={s.id} style={[styles.card, s.status === 'pending' && { borderColor: colors.saffron, borderWidth: 2 }]}>
                <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                  <Text style={{ fontSize: 16, fontWeight: '800', color: colors.text, flex: 1 }}>{s.name}</Text>
                  <Text style={{ fontWeight: '700', color: s.status === 'active' ? colors.success : s.status === 'pending' ? colors.saffronDark : colors.danger }}>
                    {statusLabel(s.status)}
                  </Text>
                </View>
                <Muted>{`${kindLabel(s.kind)} · ${s.zones?.name ?? ''} · -${s.discount_pct} %`}</Muted>
                <Muted>{s.address}</Muted>
                <Muted>{[s.siret ? `SIRET ${s.siret}` : t('SIRET non renseigné'), s.halal_cert].filter(Boolean).join(' · ')}</Muted>
                {o ? <Muted>{`${o.full_name ?? ''} ${o.phone ?? ''}`}</Muted> : null}
                <Muted>
                  {[
                    t('Inscrit le {date}', { date: shortDate(s.created_at) }),
                    s.launch_offer ? (s.free_until ? t('Gratuit jusqu’au {date}', { date: shortDate(s.free_until) }) : t('Offre de lancement')) : null,
                    s.card_ok ? t('Carte OK') : t('Carte à enregistrer'),
                  ]
                    .filter(Boolean)
                    .join(' · ')}
                </Muted>
                {s.phone ? (
                  <Pressable onPress={() => Linking.openURL(`tel:${s.phone}`)} accessibilityRole="button">
                    <Text style={{ color: colors.prune, fontWeight: '700', marginTop: 4 }}>{t('Appeler {phone}', { phone: s.phone })}</Text>
                  </Pressable>
                ) : null}
                {s.status !== 'active' ? (
                  <Button title={t('Valider ce commerce')} disabled={busy} onPress={() => confirm(t('Valider ce commerce ?'), s.name, () => rpc('admin_set_shop_status', { p_shop_id: s.id, p_status: 'active' }))} />
                ) : (
                  <Button title={t('Suspendre')} variant="secondary" disabled={busy} onPress={() => confirm(t('Suspendre ce commerce ?'), s.name, () => rpc('admin_set_shop_status', { p_shop_id: s.id, p_status: 'suspended' }))} />
                )}
                <Button
                  title={s.card_ok ? t('Retirer « carte OK »') : t('Marquer la carte comme enregistrée')}
                  variant="secondary"
                  disabled={busy}
                  onPress={() => rpc('admin_set_card_ok', { p_shop_id: s.id, p_ok: !s.card_ok })}
                />
              </View>
            );
          })}
        </View>
      ) : null}

      {tab === 'disputes' ? (
        <View>
          {disputes.length === 0 ? <Muted>{t('Aucune contestation.')}</Muted> : null}
          {disputes.map((d) => (
            <View key={d.id} style={styles.card}>
              <Text style={{ fontSize: 16, fontWeight: '800', color: colors.text }}>{`${d.shops?.name ?? ''} · ${euros(d.amount_cents)}`}</Text>
              <Muted>{shortDate(d.created_at)}</Muted>
              <Text style={{ color: colors.text, marginTop: 4 }}>{d.dispute_reason ?? ''}</Text>
              <Button title={t('Garder l’achat (confirmé)')} disabled={busy} onPress={() => rpc('admin_resolve_purchase', { p_id: d.id, p_status: 'confirmed' })} />
              <Button title={t('Annuler l’achat (pas de commission)')} variant="secondary" disabled={busy} onPress={() => rpc('admin_resolve_purchase', { p_id: d.id, p_status: 'cancelled' })} />
            </View>
          ))}
        </View>
      ) : null}

      {tab === 'charges' ? (
        <View>
          <Muted>{t('Prélèvements du lundi. En attendant le paiement par carte automatique, marquez-les à la main.')}</Muted>
          <View style={{ height: 8 }} />
          {charges.length === 0 ? <Muted>{t('Aucun prélèvement pour le moment.')}</Muted> : null}
          {charges.map((c) => (
            <View key={c.id} style={styles.card}>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 16, fontWeight: '800', color: colors.text, flex: 1 }}>{c.shops?.name ?? ''}</Text>
                <Text style={{ fontSize: 16, fontWeight: '900', color: colors.prune }}>{euros(c.amount_cents)}</Text>
              </View>
              <Muted>{`${t('Semaine du {date}', { date: shortDate(c.week_start) })} · ${
                c.status === 'paid' ? t('Payé') : c.status === 'failed' ? t('Refusé') : c.status === 'waived' ? t('Offert') : t('À prélever')
              }`}</Muted>
              {invoiceByCharge[c.id] ? (
                <Text style={{ color: colors.success, fontWeight: '700', marginTop: 6 }}>
                  {t('Facturé : {number}', { number: invoiceByCharge[c.id].number })}
                </Text>
              ) : (
              <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginTop: 6 }}>
                <Chip label={t('Payé')} selected={c.status === 'paid'} onPress={() => rpc('admin_set_charge_status', { p_id: c.id, p_status: 'paid' })} />
                <Chip label={t('Refusé')} selected={c.status === 'failed'} onPress={() => rpc('admin_set_charge_status', { p_id: c.id, p_status: 'failed' })} />
                <Chip label={t('Offert')} selected={c.status === 'waived'} onPress={() => rpc('admin_set_charge_status', { p_id: c.id, p_status: 'waived' })} />
              </View>
              )}
            </View>
          ))}
        </View>
      ) : null}

      {tab === 'invoices' ? (
        <View>
          {!summary?.company_ready ? (
            <View style={[styles.card, { backgroundColor: colors.saffronSoft, borderColor: colors.saffronSoft }]}>
              <Text style={{ fontWeight: '800', color: colors.text }}>{t('Remplissez les informations de la société')}</Text>
              <Muted>{t('Sans raison sociale, adresse et SIRET, aucune facture ne peut être émise. Les paiements déjà reçus seront facturés dès l’enregistrement.')}</Muted>
            </View>
          ) : null}
          {(summary?.invoices_missing ?? 0) > 0 ? (
            <Text style={{ color: colors.danger, fontWeight: '700', marginBottom: 6 }}>
              {t('{n} paiement(s) en attente de facture.', { n: summary?.invoices_missing ?? 0 })}
            </Text>
          ) : null}
          <SectionTitle>{t('Société qui facture')}</SectionTitle>
          {company
            ? COMPANY_FIELDS.map((f) => (
                <Field
                  key={f.key}
                  label={t(f.label)}
                  value={company[f.key]}
                  placeholder={f.placeholder ? t(f.placeholder) : undefined}
                  onChangeText={(v) => setCompany({ ...company, [f.key]: f.key === 'vat_rate' ? v.replace(/[^0-9.,]/g, '') : v })}
                  keyboardType={f.key === 'vat_rate' ? 'decimal-pad' : f.key === 'siret' ? 'number-pad' : f.key === 'email' ? 'email-address' : 'default'}
                  autoCapitalize={f.key === 'email' ? 'none' : f.key === 'vat_number' || f.key === 'invoice_prefix' ? 'characters' : 'sentences'}
                  maxLength={f.key === 'address' ? 200 : 80}
                />
              ))
            : null}
          <Button title={t('Enregistrer la société')} onPress={saveCompany} loading={busy} />

          <SectionTitle>{t('Factures émises')}</SectionTitle>
          {invoices.length === 0 ? <Muted>{t('Aucune facture pour le moment.')}</Muted> : null}
          {invoices.map((i) => (
            <View key={i.id} style={styles.card}>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 15, fontWeight: '800', color: colors.text, flex: 1 }}>{`${i.number} · ${i.buyer?.name ?? ''}`}</Text>
                <Text style={{ fontWeight: '900', color: colors.prune }}>{euros(i.amount_ttc_cents)}</Text>
              </View>
              <Muted>{t('Du {start} au {end} · émise le {date}', { start: shortDate(i.period_start), end: shortDate(i.period_end), date: fullDate(i.issued_at) })}</Muted>
              <Text style={{ color: i.email_status === 'failed' ? colors.danger : colors.muted, fontSize: 13 }}>{invoiceEmailLabel(i)}</Text>
              {i.email_status !== 'sent' && i.email_error ? <Muted>{i.email_error}</Muted> : null}
              <View style={{ flexDirection: 'row', gap: 16, marginTop: 6 }}>
                <Pressable onPress={() => openInvoice(i)} accessibilityRole="button" hitSlop={8}>
                  <Text style={{ color: colors.prune, fontWeight: '700' }}>{t('Voir le PDF')}</Text>
                </Pressable>
                <Pressable onPress={() => rpc('admin_resend_invoice', { p_id: i.id })} accessibilityRole="button" hitSlop={8}>
                  <Text style={{ color: colors.prune, fontWeight: '700' }}>{t('Renvoyer par e-mail')}</Text>
                </Pressable>
              </View>
            </View>
          ))}
        </View>
      ) : null}

      {tab === 'reports' ? (
        <View>
          {reports.length === 0 ? <Muted>{t('Aucun signalement en attente.')}</Muted> : null}
          {reports.map((r) => (
            <View key={r.id} style={styles.card}>
              <Text style={{ fontSize: 16, fontWeight: '800', color: colors.text }}>{r.shops?.name ?? ''}</Text>
              <Muted>{`${r.kind === 'prix' ? t('Prix faux') : r.kind === 'halal' ? t('Doute sur le halal') : r.kind === 'achat' ? t('Achat contesté') : t('Autre')} · ${shortDate(r.created_at)}`}</Muted>
              <Text style={{ color: colors.text, marginTop: 4 }}>{r.body}</Text>
              <Button title={t('Traité')} variant="secondary" disabled={busy} onPress={() => rpc('admin_close_report', { p_id: r.id })} />
            </View>
          ))}
        </View>
      ) : null}

      {tab === 'settings' ? (
        <View>
          <SectionTitle>{t('Réglages')}</SectionTitle>
          {form
            ? FIELDS.map((f) => (
                <Field
                  key={f.key}
                  label={t(f.label)}
                  value={form[f.key]}
                  onChangeText={(v) => setForm({ ...form, [f.key]: v.replace(f.decimal ? /[^0-9.,]/g : /[^0-9]/g, '') })}
                  keyboardType={f.decimal ? 'decimal-pad' : 'number-pad'}
                  maxLength={8}
                />
              ))
            : null}
          <Button title={t('Enregistrer les réglages')} onPress={saveSettings} loading={busy} />
          <SectionTitle>{t('Zones ouvertes aux clients')}</SectionTitle>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
            {zones.map((z) => (
              <Chip key={z.id} label={zoneLabel(z)} selected={z.open} onPress={() => rpc('admin_set_zone_open', { p_zone: z.id, p_open: !z.open })} />
            ))}
          </View>
        </View>
      ) : null}
    </ScrollView>
  );
}
