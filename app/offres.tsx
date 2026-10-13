// Client : offres flash et cadeaux des commerces autour de lui
import { Stack, router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { ActivityIndicator, Pressable, RefreshControl, ScrollView, Text, View } from 'react-native';
import { currentPosition, distanceLabel } from '../src/lib/deals';
import { t } from '../src/lib/i18n';
import { Promo, promoLabel, promoUntil } from '../src/lib/promos';
import { errorMessage, supabase } from '../src/lib/supabase';
import { colors, ErrorText, Muted, styles } from '../src/lib/theme';

export default function Offres() {
  const [promos, setPromos] = useState<Promo[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const [located, setLocated] = useState(false);

  const load = useCallback(async () => {
    setError('');
    const pos = await currentPosition();
    setLocated(!!pos);
    const { data, error } = await supabase.rpc('active_promos', { p_lat: pos?.lat ?? null, p_lng: pos?.lng ?? null, p_radius_km: 15 });
    if (error) setError(errorMessage(error));
    setPromos((data ?? []) as Promo[]);
    setLoading(false);
  }, []);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load]),
  );

  if (loading) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;

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
      <Stack.Screen options={{ title: t('Offres du moment') }} />
      <Muted>{located ? t('Dans un rayon de 15 km, les offres flash en premier.') : t('Activez la position pour voir les offres les plus proches.')}</Muted>
      <ErrorText>{error}</ErrorText>
      {promos.length === 0 ? <Muted>{t('Aucune offre en ce moment. Revenez bientôt !')}</Muted> : null}
      {promos.map((p) => (
        <Pressable
          key={p.id}
          onPress={() => router.push({ pathname: '/commerce/[id]', params: { id: p.shop_id } })}
          accessibilityRole="button"
          style={({ pressed }) => [styles.card, p.kind === 'flash' && { borderColor: colors.saffron, borderWidth: 2 }, pressed && { opacity: 0.85 }]}
        >
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
            <Text style={{ fontSize: 13, fontWeight: '800', color: p.kind === 'flash' ? colors.saffronDark : colors.prune }}>
              {p.kind === 'flash' ? t('OFFRE FLASH') : t('CADEAU')}
            </Text>
            <Text style={{ color: colors.muted, fontSize: 13 }}>{promoUntil(p)}</Text>
          </View>
          <Text style={{ fontSize: 18, fontWeight: '900', color: colors.text, marginTop: 4 }}>{promoLabel(p)}</Text>
          <Muted>{[p.shop_name, distanceLabel(p.distance_km ?? null)].filter(Boolean).join(' · ')}</Muted>
        </Pressable>
      ))}
    </ScrollView>
  );
}
