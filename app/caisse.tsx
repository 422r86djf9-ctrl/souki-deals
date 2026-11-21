// Espace caissier : clients présents, scanner un bon, sa caisse du jour.
// Le caissier ne voit ni l'argent du commerce, ni les factures, ni l'IBAN, ni les réglages.
import { router, Stack, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { ActivityIndicator, Alert, RefreshControl, ScrollView, Text, View } from 'react-native';
import { ClientsPresents } from '../src/components/ClientsPresents';
import { euros, timeLabel } from '../src/lib/deals';
import { t } from '../src/lib/i18n';
import { errorMessage, supabase, whoami, Whoami } from '../src/lib/supabase';
import { Button, colors, ErrorText, Muted, SectionTitle, styles } from '../src/lib/theme';

type Line = { id: string; first_name: string; amount_cents: number; created_at: string };

export default function Caisse() {
  const [me, setMe] = useState<Whoami | null>(null);
  const [lines, setLines] = useState<Line[]>([]);
  const [error, setError] = useState('');
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    setError('');
    try {
      const data = await whoami();
      if (!data.cashier) return router.replace('/accueil');
      setMe(data);
      const { data: today, error } = await supabase.rpc('cashier_today');
      if (error) throw error;
      setLines((today ?? []) as Line[]);
    } catch (e) {
      setError(errorMessage(e));
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load]),
  );

  function leave() {
    const k = me?.cashier;
    if (!k) return;
    Alert.alert(t('Quitter {shop} ?', { shop: k.shop_name }), t('Vous n’aurez plus accès à la caisse de ce commerce.'), [
      { text: t('Annuler'), style: 'cancel' },
      {
        text: t('Quitter'),
        style: 'destructive',
        onPress: async () => {
          const { error } = await supabase.rpc('cashier_leave', { p_id: k.id });
          if (error) return setError(errorMessage(error));
          router.replace('/accueil');
        },
      },
    ]);
  }

  if (!me && !error) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;
  const k = me?.cashier;
  const total = lines.reduce((s, l) => s + l.amount_cents, 0);

  return (
    <ScrollView
      style={{ backgroundColor: colors.background }}
      contentContainerStyle={{ padding: 16, paddingBottom: 40 }}
      keyboardShouldPersistTaps="handled"
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
      <Stack.Screen options={{ title: t('Ma caisse') }} />
      <ErrorText>{error}</ErrorText>
      {k ? (
        <>
          <View style={[styles.card, { backgroundColor: colors.prune, borderColor: colors.prune }]}>
            <Text style={{ color: colors.pruneSoft, fontSize: 13 }}>{t('Caissier : {name}', { name: k.display_name })}</Text>
            <Text style={{ color: '#FFFFFF', fontSize: 22, fontWeight: '900' }}>{k.shop_name}</Text>
            <Text style={{ color: '#FFFFFF', marginTop: 4 }}>
              {t('Remise Souki Deals à appliquer : {pct} %', { pct: String(k.discount_pct).replace('.', ',') })}
            </Text>
          </View>
          {k.shop_status !== 'active' ? (
            <Muted>{t('Le commerce n’est pas encore validé : la caisse s’ouvrira dès sa validation.')}</Muted>
          ) : null}
          <ClientsPresents active={k.shop_status === 'active'} discountPct={Number(k.discount_pct)} onPurchase={load} />
          <Button
            title={t('Scanner un bon client')}
            variant="secondary"
            disabled={k.shop_status !== 'active'}
            onPress={() => router.push('/commercant/scanner')}
          />
          <SectionTitle>{t('Ma caisse aujourd’hui')}</SectionTitle>
          <Muted>
            {lines.length
              ? t('{n} achat(s) saisi(s) · {amount}', { n: lines.length, amount: euros(total) })
              : t('Aucun achat saisi aujourd’hui.')}
          </Muted>
          {lines.map((l) => (
            <View key={l.id} style={[styles.card, { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 12 }]}>
              <Text style={{ color: colors.text, fontWeight: '700', flex: 1 }}>{`${timeLabel(l.created_at)} · ${l.first_name}`}</Text>
              <Text style={{ color: colors.text, fontWeight: '900' }}>{euros(l.amount_cents)}</Text>
            </View>
          ))}
          <View style={{ height: 16 }} />
          <Button title={t('Quitter ce commerce')} variant="secondary" onPress={leave} />
        </>
      ) : null}
    </ScrollView>
  );
}
