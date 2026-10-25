// Fiche d'un commerce : produits et prix remisés, bon de réduction, signalement
import { Stack, router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, Image, Linking, Modal, Pressable, ScrollView, Text, TextInput, View } from 'react-native';
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

  return (
    <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 16, paddingBottom: 40 }} keyboardShouldPersistTaps="handled">
      <Stack.Screen options={{ title: shop.name }} />
      <View style={[styles.card, { backgroundColor: colors.prune, borderColor: colors.prune }]}>
        <Text style={{ fontSize: 22, fontWeight: '900', color: '#fff' }}>{shop.name}</Text>
        <Text style={{ color: colors.pruneSoft }}>{kindLabel(shop.kind)}</Text>
        <Text style={{ color: '#fff', marginTop: 6 }}>{shop.address}</Text>
        {shop.hours ? <Text style={{ color: colors.pruneSoft, marginTop: 2 }}>{shop.hours}</Text> : null}
        {shop.halal_cert ? (
          <Text style={{ color: colors.saffron, fontWeight: '700', marginTop: 6 }}>{t('Certification déclarée : {c}', { c: shop.halal_cert })}</Text>
        ) : null}
        <View style={{ flexDirection: 'row', alignItems: 'center', marginTop: 12 }}>
          <DiscountTag pct={shop.discount_pct} big />
          <Text style={{ color: '#fff', marginLeft: 10, flex: 1 }}>
            {best > shop.discount_pct ? t('sur tout le magasin, jusqu’à -{n} % sur certains produits', { n: best }) : t('sur tout le magasin')}
          </Text>
        </View>
      </View>

      {promos.map((p) => (
        <View key={p.id} style={[styles.card, { borderColor: colors.saffron, borderWidth: 2 }]}>
          <Text style={{ fontSize: 13, fontWeight: '800', color: p.kind === 'flash' ? colors.saffronDark : colors.prune }}>
            {`${p.kind === 'flash' ? t('OFFRE FLASH') : t('CADEAU')} · ${promoUntil(p)}`}
          </Text>
          <Text style={{ fontSize: 17, fontWeight: '900', color: colors.text, marginTop: 2 }}>{promoLabel(p)}</Text>
          <Button
            title={chosenId === p.id ? t('Offre choisie ✓ : je suis dans le magasin') : t('Choisir cette offre')}
            variant={chosenId === p.id ? 'primary' : 'secondary'}
            onPress={() => choose(p)}
          />
        </View>
      ))}
      <Button title={t('Je suis dans le magasin : scanner son QR code')} variant="accent" onPress={() => router.push('/entree')} />
      <Button title={t('Obtenir mon bon de réduction')} variant="secondary" onPress={getVoucher} loading={busy} />
      <Muted>{t('Montrez le QR code en caisse : la remise est appliquée sur votre ticket.')}</Muted>
      <ErrorText>{error}</ErrorText>
      <InfoText>{info}</InfoText>

      <View style={{ flexDirection: 'row', gap: 8, marginTop: 4 }}>
        <View style={{ flex: 1 }}>
          <Button title={t('Itinéraire')} variant="secondary" onPress={() => openDirections(shop.lat, shop.lng)} />
        </View>
        {shop.phone ? (
          <View style={{ flex: 1 }}>
            <Button title={t('Appeler')} variant="secondary" onPress={() => Linking.openURL(`tel:${shop.phone}`)} />
          </View>
        ) : null}
      </View>

      {shop.description ? (
        <>
          <SectionTitle>{t('À propos')}</SectionTitle>
          <Muted>{shop.description}</Muted>
        </>
      ) : null}

      <SectionTitle>{t('Produits et prix')}</SectionTitle>
      {products.length === 0 ? <Muted>{t('Le commerçant n’a pas encore mis ses prix. La remise s’applique quand même en caisse.')}</Muted> : null}
      {products.map((p) => {
        const pct = p.discount_pct ?? shop.discount_pct;
        return (
          <View key={p.id} style={[styles.card, { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 12 }, !p.in_stock && { opacity: 0.6 }]}>
            {p.photo_path ? (
              <Pressable onPress={() => setZoom(p)} accessibilityRole="imagebutton" accessibilityLabel={p.name}>
                <Image source={{ uri: photoUrl(p.photo_path) as string }} style={{ width: 72, height: 72, borderRadius: 10, marginRight: 10, backgroundColor: colors.border }} />
              </Pressable>
            ) : null}
            <View style={{ flex: 1, paddingRight: 8 }}>
              <Text style={{ fontSize: 16, fontWeight: '700', color: colors.text }}>{p.name}</Text>
              <Muted>{[p.category, unitLabel(p.unit)].filter(Boolean).join(' · ')}</Muted>
              {!p.in_stock ? <Text style={{ color: colors.danger, fontSize: 13 }}>{t('Rupture de stock')}</Text> : null}
            </View>
            <View style={{ alignItems: 'flex-end' }}>
              <Text style={{ fontSize: 17, fontWeight: '900', color: colors.prune }}>{euros(finalCents(p.price_cents, pct))}</Text>
              <Text style={{ fontSize: 12, color: colors.muted, textDecorationLine: 'line-through' }}>{euros(p.price_cents)}</Text>
              <DiscountTag pct={pct} />
            </View>
          </View>
        );
      })}

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
    </ScrollView>
  );
}
