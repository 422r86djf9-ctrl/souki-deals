// Le bon de réduction : QR code à montrer en caisse
import { Stack, router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Alert, ScrollView, Text, View } from 'react-native';
import { PurchaseAnswer } from '../../src/components/PurchaseAnswer';
import { QrCode } from '../../src/components/QrCode';
import { euros, timeLabel } from '../../src/lib/deals';
import { t } from '../../src/lib/i18n';
import { errorMessage, supabase } from '../../src/lib/supabase';
import { Button, colors, DiscountTag, ErrorText, InfoText, Muted, styles } from '../../src/lib/theme';

type Voucher = {
  id: string;
  code: string;
  status: 'active' | 'used' | 'expired' | 'cancelled';
  expires_at: string;
  shops: { name: string; discount_pct: number; address: string } | null;
};
type Purchase = { id: string; amount_cents: number; status: 'pending' | 'confirmed' | 'disputed' | 'cancelled' };

export default function Bon() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [v, setV] = useState<Voucher | null>(null);
  const [purchase, setPurchase] = useState<Purchase | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    const { data, error } = await supabase
      .from('vouchers')
      .select('id, code, status, expires_at, shops(name, discount_pct, address)')
      .eq('id', id)
      .maybeSingle();
    if (error) setError(errorMessage(error));
    const vv = data as unknown as Voucher | null;
    setV(vv);
    if (vv?.status === 'used') {
      const { data: p } = await supabase.from('purchases').select('id, amount_cents, status').eq('voucher_id', id).maybeSingle();
      setPurchase(p as Purchase | null);
    }
    setLoading(false);
  }, [id]);

  useEffect(() => {
    load();
  }, [load]);

  // Tant que le bon n'est pas scanné, on vérifie toutes les 4 secondes
  useFocusEffect(
    useCallback(() => {
      if (!v || v.status !== 'active') return undefined;
      const timer = setInterval(load, 4000);
      return () => clearInterval(timer);
    }, [load, v]),
  );

  function cancel() {
    Alert.alert(t('Annuler ce bon ?'), '', [
      { text: t('Non'), style: 'cancel' },
      {
        text: t('Oui, annuler'),
        style: 'destructive',
        onPress: async () => {
          const { error } = await supabase.rpc('cancel_voucher', { p_id: id });
          if (error) return setError(errorMessage(error));
          router.back();
        },
      },
    ]);
  }

  if (loading) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;
  if (!v) return <ErrorText>{error || t('Bon introuvable.')}</ErrorText>;

  const expired = v.status === 'expired' || (v.status === 'active' && new Date(v.expires_at).getTime() < Date.now());

  return (
    <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 20, paddingBottom: 40 }}>
      <Stack.Screen options={{ title: t('Mon bon de réduction') }} />
      <View style={[styles.card, { alignItems: 'center' }]}>
        <Text style={{ fontSize: 20, fontWeight: '900', color: colors.prune, textAlign: 'center' }}>{v.shops?.name ?? ''}</Text>
        <Text style={{ color: colors.muted, textAlign: 'center', marginBottom: 10 }}>{v.shops?.address ?? ''}</Text>
        {v.shops ? <DiscountTag pct={v.shops.discount_pct} big /> : null}
        <View style={{ height: 16 }} />
        {v.status === 'active' && !expired ? (
          <>
            <QrCode value={`SOUKIDEALS:${v.code}`} size={260} />
            <Text style={{ fontSize: 30, fontWeight: '900', letterSpacing: 4, color: colors.text, marginTop: 14 }} selectable>
              {v.code}
            </Text>
            <Muted>{t('Montrez ce QR code en caisse. Si le scan ne marche pas, le commerçant tape ce code.')}</Muted>
            <Text style={{ color: colors.muted, marginTop: 6 }}>{t('Valable jusqu’à {time}', { time: timeLabel(v.expires_at) })}</Text>
          </>
        ) : v.status === 'used' ? (
          <InfoText>{t('Bon utilisé en caisse.')}</InfoText>
        ) : (
          <Text style={{ color: colors.danger, fontWeight: '700' }}>{v.status === 'cancelled' ? t('Bon annulé.') : t('Bon expiré.')}</Text>
        )}
      </View>

      {purchase && purchase.status === 'pending' ? (
        <PurchaseAnswer id={purchase.id} amountCents={purchase.amount_cents} shopName={v.shops?.name ?? ''} onDone={load} />
      ) : null}
      {purchase && purchase.status !== 'pending' ? (
        <View style={styles.card}>
          <Text style={{ fontWeight: '700', color: colors.text }}>{t('Montant payé : {amount}', { amount: euros(purchase.amount_cents) })}</Text>
          <Muted>{purchase.status === 'disputed' ? t('Contestation envoyée : Souki Deals va vérifier.') : t('Achat confirmé. Merci !')}</Muted>
        </View>
      ) : null}

      <ErrorText>{error}</ErrorText>
      {v.status === 'active' && !expired ? <Button title={t('Annuler ce bon')} variant="secondary" onPress={cancel} /> : null}
    </ScrollView>
  );
}
