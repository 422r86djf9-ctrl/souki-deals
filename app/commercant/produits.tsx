// Mes produits et mes prix (remise par produit possible)
import { Stack, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { ActivityIndicator, Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, Switch, Text, View } from 'react-native';
import { euros, finalCents, parseEuros, Product, unitLabel } from '../../src/lib/deals';
import { t } from '../../src/lib/i18n';
import { errorMessage, supabase } from '../../src/lib/supabase';
import { Button, Chip, colors, DiscountTag, ErrorText, Field, Muted, styles } from '../../src/lib/theme';

type Form = { id: number | null; name: string; category: string; unit: 'piece' | 'kg'; price: string; discount: string; inStock: boolean };
const EMPTY: Form = { id: null, name: '', category: '', unit: 'piece', price: '', discount: '', inStock: true };

export default function Produits() {
  const [shop, setShop] = useState<{ id: string; discount_pct: number } | null>(null);
  const [minDiscount, setMinDiscount] = useState(5);
  const [products, setProducts] = useState<Product[]>([]);
  const [form, setForm] = useState<Form | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    const { data: u } = await supabase.auth.getUser();
    const [s, st] = await Promise.all([
      supabase.from('shops').select('id, discount_pct').eq('owner_id', u.user?.id ?? '').maybeSingle(),
      supabase.from('settings').select('discount_min').eq('id', 1).single(),
    ]);
    if (st.data) setMinDiscount(Number(st.data.discount_min));
    if (s.data) {
      setShop(s.data);
      const { data, error } = await supabase
        .from('products')
        .select('id, shop_id, name, category, unit, price_cents, discount_pct, in_stock, active')
        .eq('shop_id', s.data.id)
        .eq('active', true)
        .order('category')
        .order('name');
      if (error) setError(errorMessage(error));
      setProducts((data ?? []) as Product[]);
    }
    setLoading(false);
  }, []);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load]),
  );

  function edit(p: Product) {
    setError('');
    setForm({
      id: p.id,
      name: p.name,
      category: p.category ?? '',
      unit: p.unit,
      price: (p.price_cents / 100).toFixed(2).replace('.', ','),
      discount: p.discount_pct != null ? String(p.discount_pct).replace('.', ',') : '',
      inStock: p.in_stock,
    });
  }

  async function save() {
    if (!form || !shop) return;
    setError('');
    const price = parseEuros(form.price);
    const pct = form.discount.trim() ? Number(form.discount.replace(',', '.')) : null;
    if (form.name.trim().length < 2) return setError(t('Indiquez le nom du produit.'));
    if (!price) return setError(t('Prix invalide (ex. 12,90).'));
    if (pct != null && (!Number.isFinite(pct) || pct < minDiscount || pct > 90)) {
      return setError(t('La remise doit être entre {min} % et 90 %, ou vide pour la remise du magasin.', { min: minDiscount }));
    }
    const row = { name: form.name.trim(), category: form.category.trim() || null, unit: form.unit, price_cents: price, discount_pct: pct, in_stock: form.inStock };
    setSaving(true);
    const { error } = form.id
      ? await supabase.from('products').update(row).eq('id', form.id)
      : await supabase.from('products').insert({ ...row, shop_id: shop.id });
    setSaving(false);
    if (error) return setError(errorMessage(error));
    setForm(null);
    await load();
  }

  function remove(p: Product) {
    Alert.alert(t('Retirer ce produit ?'), p.name, [
      { text: t('Non'), style: 'cancel' },
      {
        text: t('Oui, retirer'),
        style: 'destructive',
        onPress: async () => {
          const { error } = await supabase.from('products').update({ active: false }).eq('id', p.id);
          if (error) setError(errorMessage(error));
          setForm(null);
          await load();
        },
      },
    ]);
  }

  if (loading) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;
  if (!shop) return <ErrorText>{t('Aucun commerce.')}</ErrorText>;

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 16, paddingBottom: 40 }} keyboardShouldPersistTaps="handled">
        <Stack.Screen options={{ title: t('Mes produits') }} />
        <Muted>
          {t('Mettez vos prix habituels : les clients voient le prix après votre remise ({pct} % sur tout le magasin).', { pct: shop.discount_pct })}
        </Muted>

        {form ? (
          <View style={[styles.card, { marginTop: 12, borderColor: colors.prune }]}>
            <Field label={t('Nom du produit')} value={form.name} onChangeText={(v) => setForm({ ...form, name: v })} maxLength={60} placeholder={t('Merguez maison')} />
            <Field label={t('Rayon (facultatif)')} value={form.category} onChangeText={(v) => setForm({ ...form, category: v })} maxLength={40} placeholder={t('Agneau, volaille, épicerie…')} />
            <View style={{ flexDirection: 'row', marginBottom: 6 }}>
              <Chip label={t("À l'unité")} selected={form.unit === 'piece'} onPress={() => setForm({ ...form, unit: 'piece' })} />
              <Chip label={t('Au kilo')} selected={form.unit === 'kg'} onPress={() => setForm({ ...form, unit: 'kg' })} />
            </View>
            <Field
              label={form.unit === 'kg' ? t('Prix habituel au kilo (€)') : t("Prix habituel à l'unité (€)")}
              value={form.price}
              onChangeText={(v) => setForm({ ...form, price: v.replace(/[^0-9.,]/g, '') })}
              keyboardType="decimal-pad"
              maxLength={9}
            />
            <Field
              label={t('Remise spéciale sur ce produit (%) — vide = remise du magasin')}
              value={form.discount}
              onChangeText={(v) => setForm({ ...form, discount: v.replace(/[^0-9.,]/g, '') })}
              keyboardType="decimal-pad"
              maxLength={5}
            />
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
              <Text style={{ color: form.inStock ? colors.success : colors.danger, fontWeight: '600' }}>{form.inStock ? t('En stock') : t('Rupture de stock')}</Text>
              <Switch value={form.inStock} onValueChange={(v) => setForm({ ...form, inStock: v })} trackColor={{ true: colors.prune, false: colors.border }} thumbColor="#FFFFFF" />
            </View>
            <ErrorText>{error}</ErrorText>
            <Button title={t('Enregistrer')} onPress={save} loading={saving} />
            {form.id ? (
              <Button title={t('Retirer ce produit')} variant="secondary" onPress={() => remove(products.find((p) => p.id === form.id) as Product)} />
            ) : null}
            <Button title={t('Annuler')} variant="secondary" onPress={() => setForm(null)} />
          </View>
        ) : (
          <Button title={t('Ajouter un produit')} onPress={() => setForm({ ...EMPTY })} />
        )}

        <View style={{ height: 12 }} />
        {products.length === 0 ? <Muted>{t('Aucun produit pour le moment.')}</Muted> : null}
        {products.map((p) => {
          const pct = p.discount_pct ?? shop.discount_pct;
          return (
            <Pressable
              key={p.id}
              onPress={() => edit(p)}
              accessibilityRole="button"
              style={({ pressed }) => [styles.card, { flexDirection: 'row', justifyContent: 'space-between' }, pressed && { opacity: 0.85 }, !p.in_stock && { opacity: 0.6 }]}
            >
              <View style={{ flex: 1, paddingRight: 8 }}>
                <Text style={{ fontSize: 16, fontWeight: '700', color: colors.text }}>{p.name}</Text>
                <Muted>{[p.category, unitLabel(p.unit), p.in_stock ? null : t('Rupture de stock')].filter(Boolean).join(' · ')}</Muted>
              </View>
              <View style={{ alignItems: 'flex-end' }}>
                <Text style={{ fontWeight: '900', color: colors.prune }}>{euros(finalCents(p.price_cents, pct))}</Text>
                <Text style={{ fontSize: 12, color: colors.muted, textDecorationLine: 'line-through' }}>{euros(p.price_cents)}</Text>
                <DiscountTag pct={pct} />
              </View>
            </Pressable>
          );
        })}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
