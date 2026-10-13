// Espace commerçant : compte du jour et de la semaine, scanner, produits
import { Stack, router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { ActivityIndicator, Linking, Pressable, RefreshControl, ScrollView, Text, View } from 'react-native';
import { ClientsPresents } from '../../src/components/ClientsPresents';
import { TERMS_VERSION } from '../../src/lib/conditions';
import { euros, fullDate, Invoice, invoiceEmailLabel, shortDate, timeLabel } from '../../src/lib/deals';
import { t } from '../../src/lib/i18n';
import { errorMessage, supabase } from '../../src/lib/supabase';
import { Button, colors, ErrorText, InfoText, Muted, SectionTitle, styles } from '../../src/lib/theme';

type Stats = {
  today_cents: number;
  today_count: number;
  week_cents: number;
  week_count: number;
  month_cents: number;
  month_count: number;
  commission_due_cents: number;
  commission_offered_cents: number;
  clients_count: number;
  status: 'pending' | 'active' | 'suspended';
  launch_offer: boolean;
  free_until: string | null;
  card_ok: boolean;
  blocked: boolean;
  discount_pct: number;
  welcome_credit_cents?: number;
};
type Purchase = { id: string; amount_cents: number; commission_cents: number; free: boolean; status: string; created_at: string };
type Charge = { id: string; week_start: string; amount_cents: number; status: 'pending' | 'paid' | 'failed' | 'waived' };

function chargeLabel(s: Charge['status']) {
  if (s === 'paid') return t('Payé');
  if (s === 'failed') return t('Refusé');
  if (s === 'waived') return t('Offert');
  return t('À prélever');
}

function Tile({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <View style={[styles.card, { width: '48%', paddingVertical: 12 }]}>
      <Text style={{ fontSize: 20, fontWeight: '900', color: colors.prune }}>{value}</Text>
      <Text style={{ color: colors.muted, fontSize: 13 }}>{label}</Text>
      {sub ? <Text style={{ color: colors.muted, fontSize: 12 }}>{sub}</Text> : null}
    </View>
  );
}

export default function Commercant() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [purchases, setPurchases] = useState<Purchase[]>([]);
  const [charges, setCharges] = useState<Charge[]>([]);
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [termsOutdated, setTermsOutdated] = useState(false);
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    setError('');
    const { data: shop } = await supabase.rpc('my_shop_id');
    if (!shop) {
      router.replace('/commercant/inscription');
      return;
    }
    const [s, p, c, f, tv] = await Promise.all([
      supabase.rpc('merchant_stats'),
      supabase.from('purchases').select('id, amount_cents, commission_cents, free, status, created_at').eq('shop_id', shop).order('created_at', { ascending: false }).limit(30),
      supabase.from('charges').select('id, week_start, amount_cents, status').eq('shop_id', shop).order('week_start', { ascending: false }).limit(12),
      supabase
        .from('invoices')
        .select('id, number, issued_at, period_start, period_end, amount_ttc_cents, email_to, email_status, pdf_path')
        .eq('shop_id', shop)
        .order('seq', { ascending: false })
        .limit(24),
      supabase.from('shops').select('terms_version').eq('id', shop).maybeSingle(),
    ]);
    if (s.error) setError(errorMessage(s.error));
    else setStats(s.data as Stats);
    setPurchases((p.data ?? []) as Purchase[]);
    setCharges((c.data ?? []) as Charge[]);
    setInvoices((f.data ?? []) as Invoice[]);
    const v = (tv.data as { terms_version?: string | null } | null)?.terms_version;
    setTermsOutdated(!!v && v !== TERMS_VERSION);
  }, []);

  // PDF de la facture : lien privé valable 10 minutes
  async function openInvoice(i: Invoice) {
    setError('');
    setInfo('');
    if (!i.pdf_path) return setInfo(t('Le PDF de cette facture est en préparation. Réessayez dans quelques minutes.'));
    const { data, error } = await supabase.storage.from('factures').createSignedUrl(i.pdf_path, 600);
    if (error || !data?.signedUrl) return setError(t('Impossible d’ouvrir la facture.'));
    Linking.openURL(data.signedUrl);
  }

  async function resendInvoice(i: Invoice) {
    setError('');
    setInfo('');
    const { error } = await supabase.rpc('merchant_resend_invoice', { p_id: i.id });
    if (error) return setError(errorMessage(error));
    setInfo(t('Facture {number} renvoyée sur votre adresse e-mail.', { number: i.number }));
    await load();
  }

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load]),
  );

  if (!stats && !error) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;

  const free = stats?.free_until && new Date(stats.free_until).getTime() >= Date.now() - 86400000;

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
      <Stack.Screen options={{ title: t('Mon commerce') }} />
      <ErrorText>{error}</ErrorText>
      <InfoText>{info}</InfoText>
      {stats ? (
        <>
          {stats.status === 'pending' ? (
            <View style={[styles.card, { backgroundColor: colors.saffronSoft, borderColor: colors.saffronSoft }]}>
              <Text style={{ fontWeight: '800', color: colors.text }}>{t('Commerce en cours de validation')}</Text>
              <Muted>{t('Souki Deals vérifie vos informations. Vous pourrez scanner les bons dès la validation.')}</Muted>
              <Muted>{t('Offre de lancement : 3 mois sans commission pour les 150 premiers commerces validés.')}</Muted>
            </View>
          ) : null}
          {stats.status === 'suspended' ? (
            <Text style={{ color: colors.danger, fontWeight: '700', marginBottom: 8 }}>{t('Commerce suspendu : contactez Souki Deals.')}</Text>
          ) : null}
          {stats.blocked ? (
            <Text style={{ color: colors.danger, fontWeight: '700', marginBottom: 8 }}>
              {t('Commerce masqué aux clients : un prélèvement de commission n’a pas abouti.')}
            </Text>
          ) : null}
          {termsOutdated ? (
            <Pressable onPress={() => router.push('/commercant/releve')} accessibilityRole="button">
              <View style={[styles.card, { backgroundColor: colors.saffronSoft, borderColor: colors.saffronSoft }]}>
                <Text style={{ fontWeight: '800', color: colors.text }}>{t('Nouvelle version des conditions')}</Text>
                <Muted>{t('Touchez ici pour la lire et l’accepter.')}</Muted>
              </View>
            </Pressable>
          ) : null}
          {free ? (
            <View style={[styles.card, { backgroundColor: colors.pruneSoft, borderColor: colors.pruneSoft }]}>
              <Text style={{ fontWeight: '800', color: colors.prune }}>{t('Offre de lancement : aucune commission jusqu’au {date}', { date: shortDate(stats.free_until as string) })}</Text>
              <Muted>{t('Commission offerte jusqu’ici : {amount}', { amount: euros(stats.commission_offered_cents) })}</Muted>
            </View>
          ) : null}

          <ClientsPresents active={stats.status === 'active'} discountPct={Number(stats.discount_pct)} onPurchase={load} />
          <View style={{ flexDirection: 'row', gap: 8 }}>
            <View style={{ flex: 1 }}>
              <Button title={t('QR code du magasin')} variant="accent" onPress={() => router.push('/commercant/qr')} />
            </View>
            <View style={{ flex: 1 }}>
              <Button title={t('Scanner un bon client')} variant="secondary" onPress={() => router.push('/commercant/scanner')} disabled={stats.status !== 'active'} />
            </View>
          </View>

          <SectionTitle>{t('Ce que Souki Deals vous a amené')}</SectionTitle>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between' }}>
            <Tile label={t("Aujourd'hui")} value={euros(stats.today_cents)} sub={t('{n} achats', { n: stats.today_count })} />
            <Tile label={t('Cette semaine')} value={euros(stats.week_cents)} sub={t('{n} achats', { n: stats.week_count })} />
            <Tile label={t('Ce mois-ci')} value={euros(stats.month_cents)} sub={t('{n} achats', { n: stats.month_count })} />
            <Tile label={t('Clients différents')} value={String(stats.clients_count)} />
          </View>
          <View style={styles.card}>
            <Text style={{ fontWeight: '800', color: colors.text }}>
              {stats.commission_due_cents >= 0
                ? t('Commission à prélever lundi : {amount}', { amount: euros(stats.commission_due_cents) })
                : t('Souki Deals vous doit {amount} (offres de bienvenue)', { amount: euros(-stats.commission_due_cents) })}
            </Text>
            {stats.welcome_credit_cents ? (
              <Muted>{t('Dont {amount} d’offres de bienvenue remboursées par Souki Deals.', { amount: euros(stats.welcome_credit_cents) })}</Muted>
            ) : null}
            <Muted>
              {stats.card_ok
                ? t('Prélevée automatiquement sur votre carte chaque lundi.')
                : t('Le paiement par carte sera activé avant votre premier prélèvement. Souki Deals vous contactera.')}
            </Muted>
          </View>

          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
            <View style={{ flexGrow: 1, flexBasis: '45%' }}>
              <Button title={t('Mes produits')} variant="secondary" onPress={() => router.push('/commercant/produits')} />
            </View>
            <View style={{ flexGrow: 1, flexBasis: '45%' }}>
              <Button title={t('Mes promos')} variant="secondary" onPress={() => router.push('/commercant/promos')} />
            </View>
            <View style={{ flexGrow: 1, flexBasis: '45%' }}>
              <Button title={t('Mes informations')} variant="secondary" onPress={() => router.push('/commercant/inscription')} />
            </View>
          </View>

          <SectionTitle>{t('Derniers achats')}</SectionTitle>
          {purchases.length === 0 ? <Muted>{t('Aucun achat scanné pour le moment.')}</Muted> : null}
          {purchases.map((p) => (
            <View key={p.id} style={[styles.card, { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 10 }]}>
              <View>
                <Text style={{ fontWeight: '700', color: colors.text }}>{euros(p.amount_cents)}</Text>
                <Muted>{`${shortDate(p.created_at)} ${timeLabel(p.created_at)}`}</Muted>
              </View>
              <View style={{ alignItems: 'flex-end' }}>
                <Text style={{ color: p.free ? colors.success : colors.text, fontWeight: '600' }}>
                  {p.free ? t('Commission offerte') : t('Commission {amount}', { amount: euros(p.commission_cents) })}
                </Text>
                <Muted>{p.status === 'pending' ? t('Le client doit confirmer') : p.status === 'disputed' ? t('Contesté par le client') : p.status === 'cancelled' ? t('Annulé') : t('Confirmé')}</Muted>
              </View>
            </View>
          ))}

          {charges.length > 0 ? (
            <>
              <SectionTitle>{t('Prélèvements')}</SectionTitle>
              {charges.map((c) => (
                <View key={c.id} style={[styles.card, { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 10 }]}>
                  <Text style={{ color: colors.text }}>{t('Semaine du {date}', { date: shortDate(c.week_start) })}</Text>
                  <Text style={{ fontWeight: '700', color: c.status === 'failed' ? colors.danger : c.amount_cents < 0 ? colors.success : colors.text }}>
                    {c.amount_cents < 0
                      ? `${t('Remboursement {amount}', { amount: euros(-c.amount_cents) })} · ${c.status === 'paid' ? t('Reçu') : t('À recevoir')}`
                      : `${euros(c.amount_cents)} · ${chargeLabel(c.status)}`}
                  </Text>
                </View>
              ))}
            </>
          ) : null}

          <SectionTitle>{t('Mes factures')}</SectionTitle>
          <Muted>{t('Une facture est créée à chaque commission payée et envoyée sur l’adresse e-mail de votre compte.')}</Muted>
          <View style={{ height: 6 }} />
          <Button title={t('Relevé annuel pour le comptable')} variant="secondary" onPress={() => router.push('/commercant/releve')} />
          {invoices.length === 0 ? <Muted>{t('Aucune facture pour le moment.')}</Muted> : null}
          {invoices.map((i) => (
            <View key={i.id} style={[styles.card, { paddingVertical: 10 }]}>
              <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
                <Text style={{ fontWeight: '800', color: colors.text }}>{i.number}</Text>
                <Text style={{ fontWeight: '800', color: colors.prune }}>{euros(i.amount_ttc_cents)}</Text>
              </View>
              <Muted>{t('Du {start} au {end} · émise le {date}', { start: shortDate(i.period_start), end: shortDate(i.period_end), date: fullDate(i.issued_at) })}</Muted>
              <Text style={{ color: i.email_status === 'failed' ? colors.danger : colors.muted, fontSize: 13 }}>{invoiceEmailLabel(i)}</Text>
              <View style={{ flexDirection: 'row', gap: 16, marginTop: 6 }}>
                <Pressable onPress={() => openInvoice(i)} accessibilityRole="button" hitSlop={8}>
                  <Text style={{ color: colors.prune, fontWeight: '700' }}>{t('Voir le PDF')}</Text>
                </Pressable>
                <Pressable onPress={() => resendInvoice(i)} accessibilityRole="button" hitSlop={8}>
                  <Text style={{ color: colors.prune, fontWeight: '700' }}>{t('Renvoyer par e-mail')}</Text>
                </Pressable>
              </View>
            </View>
          ))}
        </>
      ) : null}
    </ScrollView>
  );
}
