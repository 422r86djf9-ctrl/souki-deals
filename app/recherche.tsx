// Chercher un produit : le moins cher autour de moi, remise comprise
import { Stack, router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, Text, TextInput, View } from 'react-native';
import { currentPosition, distanceLabel, euros, kindLabel, unitLabel } from '../src/lib/deals';
import { t } from '../src/lib/i18n';
import { errorMessage, supabase } from '../src/lib/supabase';
import { colors, DiscountTag, ErrorText, Muted, styles } from '../src/lib/theme';

type Row = {
  product_id: number;
  product_name: string;
  category: string | null;
  unit: 'piece' | 'kg';
  price_cents: number;
  discount_pct: number;
  final_cents: number;
  in_stock: boolean;
  shop_id: string;
  shop_name: string;
  kind: string;
  address: string;
  distance_km: number | null;
};

export default function Recherche() {
  const [q, setQ] = useState('');
  const [pos, setPos] = useState<{ lat: number; lng: number } | null>(null);
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const seq = useRef(0);

  useEffect(() => {
    currentPosition().then(setPos);
  }, []);

  useEffect(() => {
    const query = q.trim();
    if (query.length < 2) {
      seq.current++; // annule une recherche en cours
      setRows([]);
      setLoading(false);
      return;
    }
    const my = ++seq.current;
    const timer = setTimeout(async () => {
      setLoading(true);
      const { data, error } = await supabase.rpc('search_products', {
        p_query: query,
        p_lat: pos?.lat ?? null,
        p_lng: pos?.lng ?? null,
        p_radius_km: 10,
      });
      if (my !== seq.current) return; // une recherche plus récente est partie
      setLoading(false);
      if (error) setError(errorMessage(error));
      else {
        setError('');
        setRows((data ?? []) as Row[]);
      }
    }, 350);
    return () => clearTimeout(timer);
  }, [q, pos]);

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <Stack.Screen options={{ title: t('Chercher un produit') }} />
      <FlatList
        data={rows}
        keyExtractor={(r) => String(r.product_id)}
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={{ padding: 16 }}
        ListHeaderComponent={
          <View>
            <TextInput
              value={q}
              onChangeText={setQ}
              placeholder={t('Merguez, agneau, poulet, baklava…')}
              placeholderTextColor={colors.muted}
              autoFocus
              style={[styles.input, { marginBottom: 8 }]}
              accessibilityLabel={t('Chercher un produit')}
            />
            <Muted>{pos ? t('Les moins chers dans un rayon de 10 km, remise comprise.') : t('Position indisponible : résultats de toute la région.')}</Muted>
            <ErrorText>{error}</ErrorText>
            {loading ? <ActivityIndicator color={colors.prune} style={{ marginVertical: 8 }} /> : null}
            <View style={{ height: 8 }} />
          </View>
        }
        ListEmptyComponent={q.trim().length >= 2 && !loading ? <Muted>{t('Aucun produit trouvé.')}</Muted> : null}
        renderItem={({ item: r }) => (
          <Pressable
            onPress={() => router.push({ pathname: '/commerce/[id]', params: { id: r.shop_id } })}
            accessibilityRole="button"
            style={({ pressed }) => [styles.card, pressed && { opacity: 0.85 }, !r.in_stock && { opacity: 0.6 }]}
          >
            <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
              <View style={{ flex: 1, paddingRight: 8 }}>
                <Text style={{ fontSize: 16, fontWeight: '800', color: colors.text }}>{r.product_name}</Text>
                <Muted>{[r.shop_name, kindLabel(r.kind), distanceLabel(r.distance_km)].filter(Boolean).join(' · ')}</Muted>
                {!r.in_stock ? <Text style={{ color: colors.danger, fontSize: 13 }}>{t('Rupture de stock')}</Text> : null}
              </View>
              <View style={{ alignItems: 'flex-end' }}>
                <Text style={{ fontSize: 18, fontWeight: '900', color: colors.prune }}>{euros(r.final_cents)}</Text>
                <Text style={{ fontSize: 12, color: colors.muted, textDecorationLine: 'line-through' }}>{euros(r.price_cents)}</Text>
                <Text style={{ fontSize: 12, color: colors.muted }}>{unitLabel(r.unit)}</Text>
                <View style={{ marginTop: 4 }}>
                  <DiscountTag pct={r.discount_pct} />
                </View>
              </View>
            </View>
          </Pressable>
        )}
      />
    </View>
  );
}
