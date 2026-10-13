// Mes bons en cours et mes achats (avec ce que j'ai économisé)
import { Stack, router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, RefreshControl, ScrollView, Text, View } from 'react-native';
import { PurchaseAnswer } from '../src/components/PurchaseAnswer';
import { euros, shortDate, timeLabel } from '../src/lib/deals';
import { t } from '../src/lib/i18n';
import { errorMessage, supabase } from '../src/lib/supabase';
import { Button, colors, ErrorText, Muted, SectionTitle, styles } from '../src/lib/theme';

type Visit = { id: string; created_at: string; shops: { name: string } | null };
type V = { id: string; code: string; expires_at: string; shops: { name: string } | null };
type P = {
  id: string;
  amount_cents: number;
  welcome_cents: number;
  discount_pct: number;
  status: 'pending' | 'confirmed' | 'disputed' | 'cancelled';
  created_at: string;
  shops: { name: string } | null;
};

function statusLabel(s: P['status']) {
  if (s === 'pending') return t('À confirmer');
  if (s === 'confirmed') return t('Confirmé');
  if (s === 'disputed') return t('Contesté');
  return t('Annulé');
}

export default function Achats() {
  const [vouchers, setVouchers] = useState<V[]>([]);
  const [purchases, setPurchases] = useState<P[]>([]);
  const [visits, setVisits] = useState<Visit[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    setError('');
    const { data: u } = await supabase.auth.getUser();
    const uid = u.user?.id;
    if (!uid) return;
    const [v, p, ck] = await Promise.all([
      supabase
        .from('vouchers')
        .select('id, code, expires_at, shops(name)')
        .eq('client_id', uid)
        .eq('status', 'active')
        .gt('expires_at', new Date().toISOString())
        .order('created_at', { ascending: false }),
      supabase
        .from('purchases')
        .select('id, amount_cents, welcome_cents, discount_pct, status, created_at, shops(name)')
        .eq('client_id', uid)
        .order('created_at', { ascending: false })
        .limit(100),
      supabase
        .from('checkins')
        .select('id, created_at, shops(name)')
        .eq('client_id', uid)
        .in('status', ['expired', 'dismissed'])
        .is('client_answer', null)
        .gt('created_at', new Date(Date.now() - 7 * 86400000).toISOString())
        .order('created_at', { ascending: false }),
    ]);
    if (v.error || p.error) setError(errorMessage(v.error ?? p.error));
    setVouchers((v.data ?? []) as unknown as V[]);
    setPurchases((p.data ?? []) as unknown as P[]);
    setVisits((ck.data ?? []) as unknown as Visit[]);
    setLoading(false);
  }, []);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load]),
  );

  async function answerVisit(id: string, bought: boolean) {
    setError('');
    const { error } = await supabase.rpc('client_answer_checkin', { p_id: id, p_bought: bought });
    if (error) return setError(errorMessage(error));
    if (bought) Alert.alert(t('Merci'), t('Souki Deals va vérifier ce commerce.'));
    await load();
  }

  if (loading) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;

  // Économie estimée : le montant payé est après remise
  const saved = purchases
    .filter((p) => p.status === 'confirmed' || p.status === 'pending')
    .reduce((s, p) => s + (p.amount_cents * p.discount_pct) / (100 - p.discount_pct) + (p.welcome_cents ?? 0), 0);

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
      <Stack.Screen options={{ title: t('Mes bons et achats') }} />
      <ErrorText>{error}</ErrorText>
      <View style={[styles.card, { backgroundColor: colors.saffronSoft, borderColor: colors.saffronSoft }]}>
        <Text style={{ fontSize: 15, color: colors.text }}>{t('Vous avez économisé environ')}</Text>
        <Text style={{ fontSize: 28, fontWeight: '900', color: colors.prune }}>{euros(saved)}</Text>
      </View>

      {visits.map((c) => (
        <View key={c.id} style={[styles.card, { borderColor: colors.saffron, borderWidth: 2 }]}>
          <Text style={{ fontSize: 17, fontWeight: '800', color: colors.text }}>
            {t('Avez-vous acheté chez {shop} le {date} ?', { shop: c.shops?.name ?? '', date: shortDate(c.created_at) })}
          </Text>
          <Muted>{t('Vous avez scanné le QR code du magasin, mais aucun montant n’a été saisi.')}</Muted>
          <View style={{ flexDirection: 'row', gap: 8 }}>
            <View style={{ flex: 1 }}>
              <Button title={t('Oui, j’ai acheté')} onPress={() => answerVisit(c.id, true)} />
            </View>
            <View style={{ flex: 1 }}>
              <Button title={t('Non')} variant="secondary" onPress={() => answerVisit(c.id, false)} />
            </View>
          </View>
        </View>
      ))}

      {purchases
        .filter((p) => p.status === 'pending')
        .map((p) => (
          <PurchaseAnswer key={p.id} id={p.id} amountCents={p.amount_cents} welcomeCents={p.welcome_cents} shopName={p.shops?.name ?? ''} onDone={load} />
        ))}

      <SectionTitle>{t('Bons en cours')}</SectionTitle>
      {vouchers.length === 0 ? <Muted>{t('Aucun bon en cours. Choisissez un commerce pour en obtenir un.')}</Muted> : null}
      {vouchers.map((v) => (
        <Pressable
          key={v.id}
          onPress={() => router.push({ pathname: '/bon/[id]', params: { id: v.id } })}
          accessibilityRole="button"
          style={({ pressed }) => [styles.card, pressed && { opacity: 0.85 }]}
        >
          <Text style={{ fontSize: 16, fontWeight: '800', color: colors.text }}>{v.shops?.name ?? ''}</Text>
          <Muted>{t('Code {code} · valable jusqu’à {time}', { code: v.code, time: timeLabel(v.expires_at) })}</Muted>
        </Pressable>
      ))}

      <SectionTitle>{t('Mes achats')}</SectionTitle>
      {purchases.length === 0 ? <Muted>{t('Aucun achat pour le moment.')}</Muted> : null}
      {purchases.map((p) => (
        <View key={p.id} style={[styles.card, { flexDirection: 'row', justifyContent: 'space-between' }]}>
          <View style={{ flex: 1, paddingRight: 8 }}>
            <Text style={{ fontSize: 16, fontWeight: '700', color: colors.text }}>{p.shops?.name ?? ''}</Text>
            <Muted>{`${shortDate(p.created_at)} · ${statusLabel(p.status)}`}</Muted>
          </View>
          <Text style={{ fontSize: 16, fontWeight: '800', color: colors.prune }}>{euros(p.amount_cents)}</Text>
        </View>
      ))}
    </ScrollView>
  );
}
