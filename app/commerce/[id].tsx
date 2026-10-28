// Fiche d'un commerce : produits et prix remisés, bon de réduction, signalement
import { Stack, router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, Image, Linking, Modal, Pressable, ScrollView, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Icon } from '../../src/components/Icon';
import { euros, finalCents, Kind, kindLabel, openDirections, Product, unitLabel } from '../../src/lib/deals';
import { t } from '../../src/lib/i18n';
import { photoUrl } from '../../src/lib/photos';
import { getChosenPromo, Promo, promoLabel, promoUntil, setChosenPromo } from '../../src/lib/promos';
import { errorMessage, supabase } from '../../src/lib/supabase';
import { Button, Chip, colors, DiscountTag, ErrorText, InfoText, Muted, SectionTitle, styles } from '../../src/lib/theme';

type Shop = {
  id: string;
  name: string;
  kind: Kind;
  address: string;
  lat: number;
  lng: number;
  phone: string | null;
  halal_cert: string | null;
  hours: string | null;
  description: string | null;
  discount_pct: number;
};

export default function Commerce() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const insets = useSafeAreaInsets();
  const [shop, setShop] = useState<Shop | null>(null);
  const [products, setProducts] = useState<Product[]>([]);
  const [promos, setPromos] = useState<Promo[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [reportOpen, setReportOpen] = useState(false);
  const [reportKind, setReportKind] = useState<'prix' | 'halal' | 'photo' | 'autre'>('prix');
  const [zoom, setZoom] = useState<Product | null>(null);
  const [reportProduct, setReportProduct] = useState<number | null>(null);
  const [reportText, setReportText] = useState('');
  const [info, setInfo] = useState('');
  const [chosenId, setChosenId] = useState<number | null>(getChosenPromo()?.id ?? null);

  function choose(p: Promo) {
    setChosenPromo(p);
    setChosenId(p.id);
    router.push('/entree');
  }

  useEffect(() => {
    (async () => {
      try {
        const [s, p, pr] = await Promise.all([
          supabase.from('shops').select('id, name, kind, address, lat, lng, phone, halal_cert, hours, description, discount_pct').eq('id', id).maybeSingle(),
          supabase
            .from('products')
            .select('id, shop_id, name, category, unit, price_cents, discount_pct, in_stock, active, packaged, photo_path')
            .eq('shop_id', id)
            .eq('active', true)
            .order('category')
            .order('name'),
          supabase
            .from('promos')
            .select('id, shop_id, kind, title, discount_pct, min_cents, ends_at')
            .eq('shop_id', id)
            .eq('active', true)
            .gt('ends_at', new Date().toISOString())
            .order('kind'),
        ]);
        if (s.error) throw s.error;
        if (p.error) throw p.error;
        setShop(s.data as Shop | null);
        setProducts((p.data ?? []) as Product[]);
        setPromos((pr.data ?? []) as Promo[]);
      } catch (e) {
        setError(errorMessage(e));
      } finally {
        setLoading(false);
      }
    })();
  }, [id]);

  async function getVoucher() {
    setBusy(true);
    setError('');
    const { data, error } = await supabase.rpc('create_voucher', { p_shop_id: id });
    setBusy(false);
    if (error) return setError(errorMessage(error));
    const v = (data as { id: string }[] | null)?.[0];
    if (v) router.push({ pathname: '/bon/[id]', params: { id: v.id } });
  }

  async function sendReport() {
    setError('');
    setInfo('');
    if (reportText.trim().length < 3) return setError(t('Décrivez le problème (3 à 500 caractères).'));
    setBusy(true);
    const { error } = await supabase.rpc('report_create', { p_shop_id: id, p_kind: reportKind, p_body: reportText.trim(), p_product_id: reportKind === 'photo' ? reportProduct : null });
    setBusy(false);
    if (error) return setError(errorMessage(error));
    setReportOpen(false);
    setReportText('');
    setInfo(t('Merci, votre signalement est envoyé à Souki Deals.'));
  }

  if (loading) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;
  if (!shop) {
    return (
      <View style={{ padding: 20 }}>
        <Stack.Screen options={{ title: t('Commerce') }} />
        <ErrorText>{error || t("Ce commerce n'est pas disponible.")}</ErrorText>
      </View>
    );
  }

  const best = Math.max(shop.discount_pct, ...products.map((p) => p.discount_pct ?? 0));
  const cover = products.find((p) => p.photo_path)?.photo_path ?? null;

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      <Stack.Screen options={{ headerShown: false, title: shop.name }} />
      <ScrollView contentContainerStyle={{ paddingBottom: 24 }} keyboardShouldPersistTaps="handled">
        <View style={{ height: 230 + insets.top, backgroundColor: colors.prune }}>
          {cover ? (
            <Image source={{ uri: photoUrl(cover) as string }} style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 }} resizeMode="cover" accessibilityLabel={shop.name} />
          ) : (
            <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', paddingTop: insets.top }}>
              <Text style={{ fontSize: 90, fontWeight: '900', color: 'rgba(255,255,255,0.25)' }}>{shop.name.slice(0, 1).toUpperCase()}</Text>
            </View>
          )}
          <Pressable
            onPress={() => (router.canGoBack() ? router.back() : router.replace('/accueil'))}
            accessibilityRole="button"
            accessibilityLabel={t('Retour')}
            style={{ position: 'absolute', left: 16, top: insets.top + 10, width: 44, height: 44, borderRadius: 22, backgroundColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' }}
          >
            <Icon name="back" color={colors.text} />
          </Pressable>
          <View style={{ position: 'absolute', right: 16, bottom: -20, backgroundColor: '#E8590C', borderRadius: 16, paddingHorizontal: 16, paddingVertical: 10, elevation: 4 }}>
            <Text style={{ color: '#FFFFFF', fontSize: 24, fontWeight: '900' }}>{`-${Number(shop.discount_pct).toLocaleString('fr-FR')} %`}</Text>
          </View>
        </View>

        <View style={{ padding: 20, gap: 14 }}>
          <View style={{ gap: 6, paddingRight: 90 }}>
            <Text style={{ fontSize: 24, fontWeight: '900', color: colors.text }}>{shop.name}</Text>
            <Text style={{ color: colors.muted }}>{`${kindLabel(shop.kind)} · ${shop.address}`}</Text>
          </View>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8 }}>
            {shop.halal_cert ? (
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: colors.pruneSoft, borderRadius: 8, paddingHorizontal: 10, paddingVertical: 6 }}>
                <Icon name="shield" color={colors.prune} size={16} />
                <Text style={{ color: colors.prune, fontWeight: '800', fontSize: 13 }}>{t('Certification déclarée : {c}', { c: shop.halal_cert })}</Text>
              </View>
            ) : null}
            {shop.hours ? (
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: colors.card, borderColor: colors.border, borderWidth: 1, borderRadius: 8, paddingHorizontal: 10, paddingVertical: 6 }}>
                <Icon name="time" color={colors.muted} size={16} />
                <Text style={{ color: colors.text, fontSize: 13 }}>{shop.hours}</Text>
              </View>
            ) : null}
          </View>

          <View style={[styles.card, { flexDirection: 'row', alignItems: 'center', gap: 12, marginBottom: 0 }]}>
            <View style={{ width: 42, height: 42, borderRadius: 12, backgroundColor: colors.pruneSoft, alignItems: 'center', justifyContent: 'center' }}>
              <Icon name="tag" color={colors.prune} />
            </View>
            <View style={{ flex: 1 }}>
              <Text style={{ fontWeight: '800', color: colors.text, fontSize: 15 }}>{t('Remise permanente -{n} %', { n: shop.discount_pct })}</Text>
              <Text style={{ color: colors.muted, fontSize: 13 }}>
                {best > shop.discount_pct ? t('sur tout le magasin, jusqu’à -{n} % sur certains produits', { n: best }) : t('sur tout le magasin')}
              </Text>
            </View>
          </View>

          {promos.map((p) => (
            <View key={p.id} style={{ backgroundColor: colors.saffronSoft, borderColor: colors.saffron, borderWidth: 1.5, borderRadius: 18, padding: 14, gap: 8 }}>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                <Icon name="flash" color={colors.saffronDark} size={16} />
                <Text style={{ fontSize: 12, fontWeight: '800', letterSpacing: 0.5, color: colors.saffronDark, flex: 1 }}>
                  {`${p.kind === 'flash' ? t('OFFRE FLASH') : t('CADEAU')} · ${promoUntil(p)}`}
                </Text>
              </View>
              <Text style={{ fontSize: 17, fontWeight: '900', color: colors.text }}>{promoLabel(p)}</Text>
              <Pressable
                onPress={() => choose(p)}
                accessibilityRole="button"
                style={({ pressed }) => [
                  { height: 48, borderRadius: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: chosenId === p.id ? colors.prune : '#E8590C' },
                  pressed && { opacity: 0.85 },
                ]}
              >
                <Text style={{ color: '#FFFFFF', fontWeight: '800', fontSize: 15 }}>
                  {chosenId === p.id ? t('Offre choisie ✓ : je suis dans le magasin') : t('Choisir cette offre')}
                </Text>
              </Pressable>
            </View>
          ))}

          <ErrorText>{error}</ErrorText>
          <InfoText>{info}</InfoText>

          {shop.description ? (
            <View>
              <SectionTitle>{t('À propos')}</SectionTitle>
              <Muted>{shop.description}</Muted>
            </View>
          ) : null}

          <Text style={{ fontSize: 18, fontWeight: '800', color: colors.text }}>{t('Produits et prix')}</Text>
          {products.length === 0 ? <Muted>{t('Le commerçant n’a pas encore mis ses prix. La remise s’applique quand même en caisse.')}</Muted> : null}
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginHorizontal: -5 }}>
            {products.map((p) => {
              const pct = p.discount_pct ?? shop.discount_pct;
              return (
                <View key={p.id} style={[{ width: '33.33%', padding: 5 }, !p.in_stock && { opacity: 0.55 }]}>
                  <Pressable onPress={() => (p.photo_path ? setZoom(p) : undefined)} accessibilityRole={p.photo_path ? 'imagebutton' : undefined} accessibilityLabel={p.name}>
                    {p.photo_path ? (
                      <Image source={{ uri: photoUrl(p.photo_path) as string }} style={{ width: '100%', aspectRatio: 1, borderRadius: 14, backgroundColor: colors.border }} />
                    ) : (
                      <View style={{ width: '100%', aspectRatio: 1, borderRadius: 14, backgroundColor: colors.pruneSoft, alignItems: 'center', justifyContent: 'center' }}>
                        <Text style={{ fontSize: 30, fontWeight: '900', color: colors.prune }}>{p.name.slice(0, 1).toUpperCase()}</Text>
                      </View>
                    )}
                    <View style={{ position: 'absolute', top: 6, right: 6 }}>
                      <DiscountTag pct={pct} />
                    </View>
                  </Pressable>
                  <Text style={{ fontSize: 13, fontWeight: '700', color: colors.text, marginTop: 6 }} numberOfLines={2}>{p.name}</Text>
                  <Text style={{ fontSize: 14, fontWeight: '900', color: colors.prune }}>{`${euros(finalCents(p.price_cents, pct))}${p.unit === 'kg' ? ' /kg' : ''}`}</Text>
                  <Text style={{ fontSize: 11, color: colors.muted, textDecorationLine: 'line-through' }}>{euros(p.price_cents)}</Text>
                  {!p.in_stock ? <Text style={{ color: colors.danger, fontSize: 11 }}>{t('Rupture de stock')}</Text> : null}
                </View>
              );
            })}
          </View>

          <Pressable onPress={getVoucher} disabled={busy} accessibilityRole="button" style={{ paddingVertical: 8 }}>
            <Text style={{ color: colors.prune, fontWeight: '700', textAlign: 'center' }}>{busy ? t('Un instant…') : t('Obtenir mon bon de réduction')}</Text>
          </Pressable>

      <Modal visible={!!zoom} transparent animationType="fade" onRequestClose={() => setZoom(null)}>
        <Pressable onPress={() => setZoom(null)} style={{ flex: 1, backgroundColor: 'rgba(0,0,0,0.85)', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
          {zoom?.photo_path ? (
            <Image source={{ uri: photoUrl(zoom.photo_path) as string }} style={{ width: '100%', aspectRatio: 1, borderRadius: 16 }} resizeMode="contain" />
          ) : null}
          <Text style={{ color: '#fff', fontSize: 18, fontWeight: '800', marginTop: 12 }}>{zoom?.name ?? ''}</Text>
          <Pressable
            onPress={() => {
              setReportKind('photo');
              setReportProduct(zoom?.id ?? null);
              setReportOpen(true);
              setZoom(null);
            }}
            accessibilityRole="button"
            style={{ marginTop: 16, padding: 8 }}
          >
            <Text style={{ color: '#fff', textDecorationLine: 'underline' }}>{t('Signaler cette photo')}</Text>
          </Pressable>
        </Pressable>
      </Modal>

      <View style={{ height: 12 }} />
      {reportOpen ? (
        <View style={styles.card}>
          <Text style={{ fontWeight: '800', color: colors.text, marginBottom: 8 }}>{t('Signaler un problème')}</Text>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
            <Chip label={t('Prix faux')} selected={reportKind === 'prix'} onPress={() => setReportKind('prix')} />
            <Chip label={t('Doute sur le halal')} selected={reportKind === 'halal'} onPress={() => setReportKind('halal')} />
            {reportKind === 'photo' ? <Chip label={t('Photo trompeuse')} selected onPress={() => undefined} /> : null}
            <Chip label={t('Autre')} selected={reportKind === 'autre'} onPress={() => setReportKind('autre')} />
          </View>
          <TextInput
            value={reportText}
            onChangeText={setReportText}
            placeholder={t('Expliquez en quelques mots')}
            placeholderTextColor={colors.muted}
            multiline
            maxLength={500}
            style={[styles.input, { minHeight: 80, textAlignVertical: 'top' }]}
          />
          <Button title={t('Envoyer')} onPress={sendReport} loading={busy} />
          <Button title={t('Annuler')} variant="secondary" onPress={() => setReportOpen(false)} />
        </View>
      ) : (
        <Pressable onPress={() => setReportOpen(true)} accessibilityRole="button" style={{ paddingVertical: 10 }}>
          <Text style={{ color: colors.muted, textDecorationLine: 'underline', textAlign: 'center' }}>{t('Signaler un problème')}</Text>
        </Pressable>
      )}
        </View>
      </ScrollView>

      <View style={{ flexDirection: 'row', gap: 10, paddingHorizontal: 20, paddingTop: 12, paddingBottom: Math.max(insets.bottom, 12), backgroundColor: colors.card, borderTopWidth: 1, borderTopColor: colors.border }}>
        <Pressable
          onPress={() => openDirections(shop.lat, shop.lng)}
          accessibilityRole="button"
          accessibilityLabel={t('Itinéraire')}
          style={{ width: 56, height: 56, borderRadius: 16, borderWidth: 1.5, borderColor: colors.prune, alignItems: 'center', justifyContent: 'center' }}
        >
          <Icon name="navigate" color={colors.prune} />
        </Pressable>
        {shop.phone ? (
          <Pressable
            onPress={() => Linking.openURL(`tel:${shop.phone}`)}
            accessibilityRole="button"
            accessibilityLabel={t('Appeler')}
            style={{ width: 56, height: 56, borderRadius: 16, borderWidth: 1.5, borderColor: colors.prune, alignItems: 'center', justifyContent: 'center' }}
          >
            <Icon name="call" color={colors.prune} />
          </Pressable>
        ) : null}
        <Pressable
          onPress={() => router.push('/entree')}
          accessibilityRole="button"
          style={({ pressed }) => [{ flex: 1, height: 56, borderRadius: 16, backgroundColor: colors.prune, alignItems: 'center', justifyContent: 'center', flexDirection: 'row', gap: 8 }, pressed && { opacity: 0.85 }]}
        >
          <Icon name="scan" color="#FFFFFF" />
          <Text style={{ color: '#FFFFFF', fontWeight: '800', fontSize: 16 }}>{t('Je suis dans le magasin')}</Text>
        </Pressable>
      </View>
    </View>
  );
}
