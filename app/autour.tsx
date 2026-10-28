// Autour de moi : commerces halal proches, avec leur remise
import { Stack, router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, Text, View } from 'react-native';
import { LiveMap, MapMarker } from '../src/components/LiveMap';
import { currentPosition, distanceLabel, Kind, KINDS, kindLabel, NearbyShop, Zone } from '../src/lib/deals';
import { t, zoneLabel } from '../src/lib/i18n';
import { errorMessage, supabase } from '../src/lib/supabase';
import { Button, Chip, colors, DiscountTag, ErrorText, Muted, styles } from '../src/lib/theme';

const RADII = [1, 3, 5, 10];

export default function Autour() {
  const [pos, setPos] = useState<{ lat: number; lng: number } | null>(null);
  const [locating, setLocating] = useState(true);
  const [zones, setZones] = useState<Zone[]>([]);
  const [zone, setZone] = useState<number | null>(null);
  const params = useLocalSearchParams<{ kind?: string }>();
  const [kind, setKind] = useState<Kind | null>(KINDS.includes(params.kind as Kind) ? (params.kind as Kind) : null);
  const [radius, setRadius] = useState(3);
  const [view, setView] = useState<'list' | 'map'>('list');
  const [shops, setShops] = useState<NearbyShop[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const locate = useCallback(async () => {
    setLocating(true);
    const p = await currentPosition();
    setPos(p);
    setLocating(false);
  }, []);

  useEffect(() => {
    locate();
    supabase
      .from('zones')
      .select('id, name, name_en, name_ar, open, sort')
      .eq('open', true)
      .order('sort')
      .then(({ data }) => setZones((data ?? []) as Zone[]));
  }, [locate]);

  useEffect(() => {
    if (locating) return;
    if (!pos && !zone) {
      setShops([]);
      return;
    }
    setLoading(true);
    setError('');
    supabase
      .rpc('nearby_shops', {
        p_lat: pos?.lat ?? null,
        p_lng: pos?.lng ?? null,
        p_radius_km: radius,
        p_kind: kind,
        p_zone: pos ? null : zone,
      })
      .then(({ data, error }) => {
        if (error) setError(errorMessage(error));
        else setShops((data ?? []) as NearbyShop[]);
        setLoading(false);
      });
  }, [pos, zone, kind, radius, locating]);

  const markers = useMemo<MapMarker[]>(
    () => [
      ...(pos ? [{ id: 'me', kind: 'me' as const, lat: pos.lat, lng: pos.lng, label: t('Vous') }] : []),
      ...shops.map((s) => ({ id: s.id, kind: 'shop' as const, lat: s.lat, lng: s.lng, label: `${s.name} · -${s.best_discount} %` })),
    ],
    [pos, shops],
  );

  if (locating) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background }}>
        <Stack.Screen options={{ title: t('Autour de moi') }} />
        <ActivityIndicator color={colors.prune} />
        <Muted>{t('Recherche de votre position…')}</Muted>
      </View>
    );
  }

  const header = (
    <View>
      {pos ? (
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center' }}>
          <Text style={{ color: colors.muted, marginRight: 8, marginBottom: 8 }}>{t('Rayon :')}</Text>
          {RADII.map((r) => (
            <Chip key={r} label={t('{km} km', { km: r })} selected={radius === r} onPress={() => setRadius(r)} />
          ))}
        </View>
      ) : (
        <>
          <Muted>{t('Position indisponible : choisissez votre département.')}</Muted>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginTop: 8 }}>
            {zones.map((z) => (
              <Chip key={z.id} label={zoneLabel(z)} selected={zone === z.id} onPress={() => setZone(z.id)} />
            ))}
          </View>
          <Button title={t('Réessayer avec ma position')} variant="secondary" onPress={locate} />
        </>
      )}
      <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginTop: 8 }}>
        <Chip label={t('Tout')} selected={kind === null} onPress={() => setKind(null)} />
        {KINDS.map((k) => (
          <Chip key={k} label={kindLabel(k)} selected={kind === k} onPress={() => setKind(k)} />
        ))}
      </View>
      <View style={{ flexDirection: 'row', marginBottom: 8 }}>
        <Chip label={t('Liste')} selected={view === 'list'} onPress={() => setView('list')} />
        <Chip label={t('Carte')} selected={view === 'map'} onPress={() => setView('map')} />
      </View>
      <ErrorText>{error}</ErrorText>
      {view === 'map' ? <LiveMap markers={markers} onSelect={(id) => router.push({ pathname: '/commerce/[id]', params: { id } })} style={{ height: 380, marginBottom: 12 }} /> : null}
    </View>
  );

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <Stack.Screen options={{ title: t('Autour de moi') }} />
      <FlatList
        data={view === 'list' ? shops : []}
        keyExtractor={(s) => s.id}
        contentContainerStyle={{ padding: 16 }}
        ListHeaderComponent={header}
        ListEmptyComponent={
          view === 'list' ? (
            loading ? (
              <ActivityIndicator color={colors.prune} />
            ) : pos || zone ? (
              <Muted>{t('Aucun commerce partenaire ici pour le moment. Élargissez le rayon ou changez de type.')}</Muted>
            ) : null
          ) : null
        }
        renderItem={({ item: s }) => (
          <Pressable
            onPress={() => router.push({ pathname: '/commerce/[id]', params: { id: s.id } })}
            accessibilityRole="button"
            style={({ pressed }) => [styles.card, pressed && { opacity: 0.85 }]}
          >
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <View style={{ flex: 1, paddingRight: 8 }}>
                <Text style={{ fontSize: 17, fontWeight: '800', color: colors.text }}>{s.name}</Text>
                <Muted>{[kindLabel(s.kind), distanceLabel(s.distance_km)].filter(Boolean).join(' · ')}</Muted>
                <Text style={{ color: colors.muted, fontSize: 13 }} numberOfLines={1}>
                  {s.address}
                </Text>
                {s.halal_cert ? <Text style={{ color: colors.success, fontSize: 13, fontWeight: '600' }}>{t('Certification déclarée : {c}', { c: s.halal_cert })}</Text> : null}
              </View>
              <DiscountTag pct={s.best_discount} />
            </View>
          </Pressable>
        )}
      />
    </View>
  );
}
