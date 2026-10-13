// Tablette du commerçant : clients qui viennent de scanner le QR code du magasin.
// Le commerçant saisit le montant payé (remise déduite), ou indique que le client n'a rien acheté.
import { useFocusEffect } from 'expo-router';
import { useCallback, useRef, useState } from 'react';
import { Alert, Text, TextInput, Vibration, View } from 'react-native';
import { euros, parseEuros, timeLabel } from '../lib/deals';
import { t } from '../lib/i18n';
import { errorMessage, supabase } from '../lib/supabase';
import { Button, colors, ErrorText, InfoText, Muted, SectionTitle, styles } from '../lib/theme';
import { WelcomeBanner } from './WelcomeBanner';

type Visit = { id: string; code: string; first_name: string; created_at: string; expires_at: string; welcome_cents?: number; welcome_min_cents?: number };

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
        <View key={v.id} style={[styles.card, { borderColor: colors.saffron, borderWidth: 2 }]}>
          <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
            <Text style={{ fontSize: 22, fontWeight: '900', color: colors.text }}>{v.first_name}</Text>
            <Text style={{ fontSize: 18, fontWeight: '800', color: colors.prune, letterSpacing: 2 }}>{v.code}</Text>
          </View>
          <Muted>{t('Arrivé à {time} · remise de {pct} % à appliquer', { time: timeLabel(v.created_at), pct: String(discountPct).replace('.', ',') })}</Muted>
          <WelcomeBanner cents={v.welcome_cents ?? 0} minCents={v.welcome_min_cents ?? 0} />
          <Text style={{ fontWeight: '700', color: colors.text, marginTop: 10 }}>{t('Montant payé, remise déduite (€)')}</Text>
          <TextInput
            value={amounts[v.id] ?? ''}
            onChangeText={(x) => setAmounts((a) => ({ ...a, [v.id]: x.replace(/[^0-9.,]/g, '') }))}
            keyboardType="decimal-pad"
            placeholder="0,00"
            placeholderTextColor={colors.muted}
            style={[styles.input, { fontSize: 26, fontWeight: '800', textAlign: 'center' }]}
            maxLength={8}
          />
          <View style={{ flexDirection: 'row', gap: 8 }}>
            <View style={{ flex: 2 }}>
              <Button title={t('Valider l’achat')} onPress={() => complete(v)} loading={busy === v.id} disabled={!!busy} />
            </View>
            <View style={{ flex: 1 }}>
              <Button title={t('Pas d’achat')} variant="secondary" onPress={() => dismiss(v)} disabled={!!busy} />
            </View>
          </View>
        </View>
      ))}
    </View>
  );
}
