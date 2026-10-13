// Commerçant : ses promos (à ses frais) — offre flash et produit offert. 3 en cours au plus.
import { Stack, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { ActivityIndicator, Alert, ScrollView, Text, View } from 'react-native';
import { parseEuros } from '../../src/lib/deals';
import { t } from '../../src/lib/i18n';
import { Promo, promoLabel, promoUntil } from '../../src/lib/promos';
import { errorMessage, supabase } from '../../src/lib/supabase';
import { Button, Chip, colors, ErrorText, Field, InfoText, Muted, SectionTitle, styles } from '../../src/lib/theme';

type Kind = 'flash' | 'gift';

export default function MesPromos() {
  const [promos, setPromos] = useState<Promo[]>([]);
  const [loading, setLoading] = useState(true);
  const [kind, setKind] = useState<Kind>('flash');
  const [title, setTitle] = useState('');
  const [pct, setPct] = useState('20');
  const [min, setMin] = useState('20');
  const [days, setDays] = useState(0);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');

  const load = useCallback(async () => {
    const { data: u } = await supabase.auth.getUser();
    const { data: shop } = await supabase.from('shops').select('id').eq('owner_id', u.user?.id ?? '').maybeSingle();
    if (shop) {
      const { data } = await supabase
        .from('promos')
        .select('id, shop_id, kind, title, discount_pct, min_cents, ends_at, active')
        .eq('shop_id', (shop as { id: string }).id)
        .eq('active', true)
        .gt('ends_at', new Date().toISOString())
        .order('created_at', { ascending: false });
      setPromos((data ?? []) as Promo[]);
    }
    setLoading(false);
  }, []);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load]),
  );

  async function save() {
    setError('');
    setInfo('');
    const p = Number(pct.replace(',', '.'));
    const m = parseEuros(min);
    if (title.trim().length < 2) return setError(t('Indiquez le produit (2 à 60 caractères).'));
    if (kind === 'flash' && !Number.isFinite(p)) return setError(t('Indiquez la remise en %.'));
    if (kind === 'gift' && !m) return setError(t('Indiquez le montant d’achat minimum.'));
    setBusy(true);
    const { error } = await supabase.rpc('merchant_save_promo', {
      p_kind: kind,
      p_title: title.trim(),
      p_pct: kind === 'flash' ? p : null,
      p_min_cents: kind === 'gift' ? m : null,
      p_days: days,
    });
    setBusy(false);
    if (error) return setError(errorMessage(error));
    setTitle('');
    setInfo(t('Promo publiée : les clients la voient tout de suite.'));
    await load();
  }

  function stop(p: Promo) {
    Alert.alert(t('Arrêter cette promo ?'), promoLabel(p), [
      { text: t('Annuler'), style: 'cancel' },
      {
        text: t('Arrêter'),
        onPress: async () => {
          const { error } = await supabase.rpc('merchant_stop_promo', { p_id: p.id });
          if (error) return setError(errorMessage(error));
          await load();
        },
      },
    ]);
  }

  if (loading) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;

  const durations: { d: number; label: string }[] =
    kind === 'flash'
      ? [
          { d: 0, label: t('Aujourd’hui') },
          { d: 1, label: t('2 jours') },
          { d: 6, label: t('1 semaine') },
        ]
      : [
          { d: 6, label: t('1 semaine') },
          { d: 13, label: t('2 semaines') },
          { d: 29, label: t('1 mois') },
        ];

  return (
    <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 16, paddingBottom: 40 }} keyboardShouldPersistTaps="handled">
      <Stack.Screen options={{ title: t('Mes promos') }} />
      <Muted>{t('Vos promos s’ajoutent à votre remise habituelle. Elles sont à vos frais et attirent les clients du quartier.')}</Muted>

      <SectionTitle>{t('Promos en cours ({n}/3)', { n: promos.length })}</SectionTitle>
      {promos.length === 0 ? <Muted>{t('Aucune promo en cours.')}</Muted> : null}
      {promos.map((p) => (
        <View key={p.id} style={styles.card}>
          <Text style={{ fontSize: 16, fontWeight: '900', color: colors.text }}>{promoLabel(p)}</Text>
          <Muted>{`${p.kind === 'flash' ? t('Offre flash') : t('Produit offert')} · ${promoUntil(p)}`}</Muted>
          <Button title={t('Arrêter')} variant="secondary" onPress={() => stop(p)} />
        </View>
      ))}

      {promos.length < 3 ? (
        <>
          <SectionTitle>{t('Nouvelle promo')}</SectionTitle>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
            <Chip
              label={t('Offre flash : un produit à -X %')}
              selected={kind === 'flash'}
              onPress={() => {
                setKind('flash');
                setDays(0);
              }}
            />
            <Chip
              label={t('Produit offert dès un montant')}
              selected={kind === 'gift'}
              onPress={() => {
                setKind('gift');
                setDays(6);
              }}
            />
          </View>
          <Field
            label={kind === 'flash' ? t('Produit en promo') : t('Produit offert')}
            value={title}
            onChangeText={setTitle}
            maxLength={60}
            placeholder={kind === 'flash' ? t('Gigot d’agneau') : t('Une baguette')}
          />
          {kind === 'flash' ? (
            <Field label={t('Remise (%)')} value={pct} onChangeText={(v) => setPct(v.replace(/[^0-9.,]/g, ''))} keyboardType="decimal-pad" maxLength={4} />
          ) : (
            <Field label={t('Dès un achat de (€)')} value={min} onChangeText={(v) => setMin(v.replace(/[^0-9.,]/g, ''))} keyboardType="decimal-pad" maxLength={7} />
          )}
          <Text style={{ fontWeight: '600', color: colors.text, marginBottom: 6 }}>{t('Durée')}</Text>
          <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
            {durations.map((x) => (
              <Chip key={x.d} label={x.label} selected={days === x.d} onPress={() => setDays(x.d)} />
            ))}
          </View>
          <ErrorText>{error}</ErrorText>
          <InfoText>{info}</InfoText>
          <Button title={t('Publier la promo')} onPress={save} loading={busy} />
        </>
      ) : (
        <>
          <ErrorText>{error}</ErrorText>
          <InfoText>{info}</InfoText>
        </>
      )}
    </ScrollView>
  );
}
