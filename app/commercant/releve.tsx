// Relevé annuel pour le comptable + conditions acceptées (PDF et fichiers Excel)
import { Stack } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Alert, ScrollView, Text, View } from 'react-native';
import { TERMS_VERSION, TermsParams, versionLabel } from '../../src/lib/conditions';
import { fullDate } from '../../src/lib/deals';
import { t } from '../../src/lib/i18n';
import { eur, shareConditionsPdf, shareInvoicesCsv, sharePurchasesCsv, shareStatementPdf, Statement, totals } from '../../src/lib/releve';
import { errorMessage, supabase } from '../../src/lib/supabase';
import { Button, Chip, colors, ErrorText, InfoText, Muted, SectionTitle, styles } from '../../src/lib/theme';

const FIRST_YEAR = 2026;
type Cfg = { discount_min: number; commission_rate: number; launch_slots: number; launch_free_months: number; welcome_amount_cents?: number; welcome_min_cents?: number };

export default function Releve() {
  const thisYear = new Date().getFullYear();
  const years: number[] = [];
  for (let y = thisYear; y >= FIRST_YEAR; y--) years.push(y);
  // En janvier, on prépare souvent l'année qui vient de finir
  const [year, setYear] = useState(new Date().getMonth() === 0 && thisYear > FIRST_YEAR ? thisYear - 1 : thisYear);
  const [st, setSt] = useState<Statement | null>(null);
  const [settings, setSettings] = useState<Cfg | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');

  const load = useCallback(async (y: number) => {
    setLoading(true);
    setError('');
    const [s, cfg] = await Promise.all([
      supabase.rpc('merchant_year_statement', { p_year: y }),
      supabase.from('settings').select('discount_min, commission_rate, launch_slots, launch_free_months, welcome_amount_cents, welcome_min_cents').eq('id', 1).single(),
    ]);
    if (s.error) setError(errorMessage(s.error));
    else setSt(s.data as Statement);
    if (cfg.data) setSettings(cfg.data as Cfg);
    setLoading(false);
  }, []);

  useEffect(() => {
    load(year);
  }, [year, load]);

  async function run(key: string, action: () => Promise<void>) {
    setBusy(key);
    setError('');
    setInfo('');
    try {
      await action();
    } catch (e) {
      setError(t('Impossible de préparer le fichier.') + (e instanceof Error && e.message ? ` (${e.message})` : ''));
    } finally {
      setBusy('');
    }
  }

  function termsParams(): TermsParams {
    return {
      discountMin: Number(settings?.discount_min ?? 5),
      commission: Number(settings?.commission_rate ?? 5),
      launchSlots: Number(settings?.launch_slots ?? 150),
      launchMonths: Number(settings?.launch_free_months ?? 3),
      welcomeCents: settings?.welcome_amount_cents,
      welcomeMinCents: settings?.welcome_min_cents,
      seller: st?.seller ?? null,
      shop: st ? { name: st.shop.name, address: st.shop.address, siret: st.shop.siret } : null,
      acceptedAt: st?.terms.accepted_at ?? null,
      acceptedVersion: st?.terms.version ?? null,
      acceptedCommission: st?.terms.commission_rate ?? null,
      acceptedDiscountMin: st?.terms.discount_min ?? null,
    };
  }

  function acceptNewTerms() {
    Alert.alert(t('Accepter les nouvelles conditions ?'), t('Lisez-les d’abord avec le bouton « Conditions en PDF ».'), [
      { text: t('Annuler'), style: 'cancel' },
      {
        text: t('J’accepte'),
        onPress: async () => {
          const { error } = await supabase.rpc('merchant_accept_terms');
          if (error) return setError(errorMessage(error));
          setInfo(t('Nouvelles conditions acceptées.'));
          await load(year);
        },
      },
    ]);
  }

  const tot = st ? totals(st) : null;
  const outdated = st?.terms.version && st.terms.version !== TERMS_VERSION;

  return (
    <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 16, paddingBottom: 40 }}>
      <Stack.Screen options={{ title: t('Relevé annuel') }} />
      <Muted>{t('Tout ce que votre comptable demande pour le bilan : factures, commissions et ventes amenées par Souki Deals.')}</Muted>
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginTop: 10 }}>
        {years.map((y) => (
          <Chip key={y} label={String(y)} selected={y === year} onPress={() => setYear(y)} />
        ))}
      </View>
      <ErrorText>{error}</ErrorText>
      <InfoText>{info}</InfoText>

      {loading ? <ActivityIndicator style={{ marginTop: 30 }} color={colors.prune} /> : null}

      {!loading && st && tot ? (
        <>
          <View style={styles.card}>
            {[
              [t('Commissions HT'), eur(tot.ht)],
              [t('TVA sur commissions'), eur(tot.vat)],
              [t('Commissions TTC payées'), eur(tot.ttc)],
              [t('Factures'), String(tot.invoices)],
              [t('Ventes amenées ({n} achats)', { n: tot.purchases }), eur(tot.sales)],
              [t('Remises accordées aux clients'), eur(tot.discounts)],
            ].map(([label, value]) => (
              <View key={label} style={{ flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 5 }}>
                <Text style={{ color: colors.text, flex: 1 }}>{label}</Text>
                <Text style={{ fontWeight: '800', color: colors.prune }}>{value}</Text>
              </View>
            ))}
            {st.welcome_cents ? <Muted>{t('Bienvenue remboursée par Souki Deals : {amount}', { amount: eur(st.welcome_cents) })}</Muted> : null}
            {st.offered_cents > 0 ? <Muted>{t('Commission offerte (lancement) : {amount}', { amount: eur(st.offered_cents) })}</Muted> : null}
            {st.unbilled_cents > 0 ? <Muted>{t('Pas encore prélevé : {amount} (prochaine facture)', { amount: eur(st.unbilled_cents) })}</Muted> : null}
          </View>

          <SectionTitle>{t('Pour votre comptable')}</SectionTitle>
          <Button title={t('Relevé {year} en PDF', { year: st.year })} onPress={() => run('pdf', () => shareStatementPdf(st))} loading={busy === 'pdf'} disabled={!!busy} />
          <Button
            title={t('Factures {year} (Excel)', { year: st.year })}
            variant="secondary"
            onPress={() => run('inv', () => shareInvoicesCsv(st))}
            loading={busy === 'inv'}
            disabled={!!busy}
          />
          <Button
            title={t('Achats {year} (Excel)', { year: st.year })}
            variant="secondary"
            onPress={() => run('pur', () => sharePurchasesCsv(st))}
            loading={busy === 'pur'}
            disabled={!!busy}
          />
          <Muted>{t('Envoyez-les par e-mail à votre comptable ou enregistrez-les dans vos fichiers. Les PDF de chaque facture sont dans « Mes factures ».')}</Muted>

          <SectionTitle>{t('Conditions acceptées')}</SectionTitle>
          <View style={styles.card}>
            <Text style={{ color: colors.text }}>
              {st.terms.accepted_at
                ? t('Version du {version}, acceptée le {date}', { version: versionLabel(st.terms.version ?? ''), date: fullDate(st.terms.accepted_at) })
                : t('Aucune acceptation enregistrée.')}
            </Text>
            {st.terms.accepted_at ? (
              <Muted>
                {t('Remise minimum {d} %, commission {c} % du montant payé', {
                  d: String(st.terms.discount_min ?? '').replace('.', ','),
                  c: String(st.terms.commission_rate ?? '').replace('.', ','),
                })}
              </Muted>
            ) : null}
          </View>
          {outdated ? (
            <View style={[styles.card, { backgroundColor: colors.saffronSoft, borderColor: colors.saffronSoft }]}>
              <Text style={{ fontWeight: '800', color: colors.text }}>{t('Nouvelle version des conditions')}</Text>
              <Muted>{t('Lisez-la en PDF puis acceptez-la pour continuer à utiliser Souki Deals.')}</Muted>
              <Button title={t('J’accepte la nouvelle version')} onPress={acceptNewTerms} />
            </View>
          ) : null}
          <Button
            title={t('Conditions en PDF')}
            variant="secondary"
            onPress={() => run('cgu', () => shareConditionsPdf(termsParams()))}
            loading={busy === 'cgu'}
            disabled={!!busy}
          />
        </>
      ) : null}
    </ScrollView>
  );
}
