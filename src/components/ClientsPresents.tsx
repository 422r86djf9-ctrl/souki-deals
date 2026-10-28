// Tablette du commerçant : clients qui viennent de scanner le QR code du magasin.
// Le commerçant saisit le montant payé (remise déduite), ou indique que le client n'a rien acheté.
import { useFocusEffect } from 'expo-router';
import { useCallback, useRef, useState } from 'react';
import { Alert, Pressable, Text, TextInput, Vibration, View } from 'react-native';
import { euros, parseEuros, timeLabel } from '../lib/deals';
import { t } from '../lib/i18n';
import { errorMessage, supabase } from '../lib/supabase';
import { colors, ErrorText, InfoText, Muted, SectionTitle, styles } from '../lib/theme';
import { WelcomeBanner } from './WelcomeBanner';

type Visit = {
  id: string;
  code: string;
  first_name: string;
  created_at: string;
  expires_at: string;
  welcome_cents?: number;
  welcome_min_cents?: number;
  promo_kind?: 'flash' | 'gift' | null;
  promo_title?: string | null;
  promo_pct?: number | null;
  promo_min_cents?: number | null;
};

const POLL_MS = 8000;

export function ClientsPresents({ active, discountPct, onPurchase }: { active: boolean; discountPct: number; onPurchase: () => void }) {
  const [visits, setVisits] = useState<Visit[]>([]);
  const [amounts, setAmounts] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');
  const count = useRef(0);

  const load = useCallback(async () => {
    const { data, error } = await supabase.rpc('merchant_checkins');
    if (error) return;
    const list = (data ?? []) as Visit[];
    // Nouveau client : petite vibration pour attirer l'œil
    if (list.length > count.current) Vibration.vibrate([0, 300, 150, 300]);
    count.current = list.length;
    setVisits(list);
  }, []);

  useFocusEffect(
    useCallback(() => {
      if (!active) return;
      load();
      const timer = setInterval(load, POLL_MS);
      return () => clearInterval(timer);
    }, [active, load]),
  );

  async function complete(v: Visit) {
    setError('');
    setInfo('');
    const cents = parseEuros(amounts[v.id] ?? '');
    if (!cents) return setError(t('Indiquez le montant payé, par exemple 23,50.'));
    setBusy(v.id);
    const { error } = await supabase.rpc('merchant_complete_checkin', { p_id: v.id, p_amount_cents: cents });
    setBusy('');
    if (error) return setError(errorMessage(error));
    setInfo(t('Achat de {amount} enregistré pour {name}. Le client va le confirmer.', { amount: euros(cents), name: v.first_name }));
    setAmounts((a) => ({ ...a, [v.id]: '' }));
    await load();
    onPurchase();
  }

  function dismiss(v: Visit) {
    Alert.alert(t('{name} n’a rien acheté ?', { name: v.first_name }), t('Le client devra le confirmer de son côté.'), [
      { text: t('Annuler'), style: 'cancel' },
      {
        text: t('Pas d’achat'),
        onPress: async () => {
          const { error } = await supabase.rpc('merchant_dismiss_checkin', { p_id: v.id });
          if (error) return setError(errorMessage(error));
          await load();
        },
      },
    ]);
  }

  if (!active) return null;

  return (
    <View>
      <SectionTitle>{visits.length ? t('Clients présents ({n})', { n: visits.length }) : t('Clients présents')}</SectionTitle>
      <ErrorText>{error}</ErrorText>
      <InfoText>{info}</InfoText>
      {visits.length === 0 ? (
        <Muted>{t('Quand un client scanne le QR code du magasin, il apparaît ici. Saisissez alors le montant payé.')}</Muted>
      ) : null}
      {visits.map((v) => (
        <View key={v.id} style={{ backgroundColor: colors.saffron, borderRadius: 22, padding: 16, marginBottom: 12, gap: 10 }}>
          <Text style={{ fontSize: 11, fontWeight: '900', letterSpacing: 1.5, color: colors.text }}>{t('CLIENT DANS LE MAGASIN')}</Text>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
            <Text style={{ fontSize: 28, fontWeight: '900', color: colors.text, flex: 1 }} numberOfLines={1}>{v.first_name}</Text>
            <Text style={{ fontSize: 20, fontWeight: '900', color: colors.text, letterSpacing: 3 }}>{v.code}</Text>
          </View>
          <Text style={{ color: colors.text, fontSize: 13 }}>
            {t('Arrivé à {time} · remise de {pct} % à appliquer', { time: timeLabel(v.created_at), pct: String(discountPct).replace('.', ',') })}
          </Text>
          {v.promo_title ? (
            <View style={{ backgroundColor: '#FFFFFF', borderRadius: 14, padding: 12 }}>
              <Text style={{ fontWeight: '800', color: colors.saffronDark, fontSize: 11 }}>{t('OFFRE CHOISIE PAR LE CLIENT')}</Text>
              <Text style={{ fontWeight: '900', color: colors.text, fontSize: 17, marginTop: 2 }}>
                {v.promo_kind === 'gift'
                  ? t('{title} offert dès {min}', { title: v.promo_title, min: euros(v.promo_min_cents ?? 0) })
                  : t('{title} : -{pct} %', { title: v.promo_title, pct: String(v.promo_pct ?? 0).replace('.', ',') })}
              </Text>
            </View>
          ) : null}
          <WelcomeBanner cents={v.welcome_cents ?? 0} minCents={v.welcome_min_cents ?? 0} />
          <Text style={{ fontWeight: '800', color: colors.text }}>{t('Montant payé, remise déduite (€)')}</Text>
          <TextInput
            value={amounts[v.id] ?? ''}
            onChangeText={(x) => setAmounts((a) => ({ ...a, [v.id]: x.replace(/[^0-9.,]/g, '') }))}
            keyboardType="decimal-pad"
            placeholder="0,00"
            placeholderTextColor={colors.muted}
            style={[styles.input, { fontSize: 28, fontWeight: '900', textAlign: 'center', backgroundColor: '#FFFFFF', marginBottom: 0 }]}
            maxLength={8}
          />
          <Pressable
            onPress={() => complete(v)}
            disabled={!!busy}
            accessibilityRole="button"
            style={({ pressed }) => [
              { height: 54, borderRadius: 14, backgroundColor: colors.text, alignItems: 'center', justifyContent: 'center' },
              (pressed || !!busy) && { opacity: 0.8 },
            ]}
          >
            <Text style={{ color: '#FFFFFF', fontWeight: '900', fontSize: 16 }}>{busy === v.id ? t('Un instant…') : t('Valider l’achat')}</Text>
          </Pressable>
          <Pressable onPress={() => dismiss(v)} disabled={!!busy} accessibilityRole="button" style={{ paddingVertical: 6 }}>
            <Text style={{ color: colors.text, textAlign: 'center', fontWeight: '700', textDecorationLine: 'underline' }}>{t('Pas d’achat')}</Text>
          </Pressable>
        </View>
      ))}
    </View>
  );
}
