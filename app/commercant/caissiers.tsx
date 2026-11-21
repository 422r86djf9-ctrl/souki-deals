// Mes caissiers : le patron ajoute ou retire les caissiers de son commerce (une caisse = un appareil).
// Chaque caissier se connecte avec son propre compte et ne voit que la caisse.
import { Stack, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, KeyboardAvoidingView, Platform, ScrollView, Text, View } from 'react-native';
import { euros, shortDate } from '../../src/lib/deals';
import { t } from '../../src/lib/i18n';
import { errorMessage, supabase } from '../../src/lib/supabase';
import { Button, colors, ErrorText, Field, InfoText, Muted, SectionTitle, styles } from '../../src/lib/theme';

type Cashier = {
  id: string;
  email: string;
  display_name: string;
  status: 'invited' | 'active';
  created_at: string;
  accepted_at: string | null;
  today_count: number;
  today_cents: number;
  month_count: number;
  month_cents: number;
};

export default function Caissiers() {
  const [list, setList] = useState<Cashier[]>([]);
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');

  const load = useCallback(async () => {
    const { data, error } = await supabase.rpc('merchant_cashiers');
    if (error) return setError(errorMessage(error));
    setList((data ?? []) as Cashier[]);
  }, []);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load]),
  );

  async function add() {
    setError('');
    setInfo('');
    if (!name.trim()) return setError(t('Indiquez le prénom du caissier (40 caractères au plus).'));
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email.trim())) return setError(t('Adresse e-mail invalide.'));
    setBusy(true);
    const { error } = await supabase.rpc('merchant_add_cashier', { p_email: email.trim(), p_name: name.trim() });
    setBusy(false);
    if (error) return setError(errorMessage(error));
    setInfo(
      t('{name} est ajouté. Il installe Souki Deals sur l’appareil de sa caisse, crée son compte avec {email}, puis accepte l’invitation.', {
        name: name.trim(),
        email: email.trim().toLowerCase(),
      }),
    );
    setName('');
    setEmail('');
    await load();
  }

  function remove(c: Cashier) {
    Alert.alert(t('Retirer {name} ?', { name: c.display_name }), t('Il perd l’accès à votre caisse tout de suite. Ses achats déjà saisis restent comptés.'), [
      { text: t('Annuler'), style: 'cancel' },
      {
        text: t('Retirer'),
        style: 'destructive',
        onPress: async () => {
          const { error } = await supabase.rpc('merchant_remove_cashier', { p_id: c.id });
          if (error) return setError(errorMessage(error));
          await load();
        },
      },
    ]);
  }

  const active = list.filter((c) => c.status === 'active');
  const todayCount = active.reduce((s, c) => s + c.today_count, 0);
  const todayCents = active.reduce((s, c) => s + Number(c.today_cents), 0);

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 16, paddingBottom: 40 }} keyboardShouldPersistTaps="handled">
        <Stack.Screen options={{ title: t('Mes caissiers') }} />
        <Muted>
          {t('Plusieurs caisses ? Ajoutez vos caissiers. Chacun se connecte sur l’appareil de sa caisse et voit les clients Souki Deals présents dans le magasin. Il saisit le montant payé, rien de plus : il ne voit ni vos ventes, ni vos factures, ni votre IBAN.')}
        </Muted>

        <SectionTitle>{t('Ajouter un caissier')}</SectionTitle>
        <Field label={t('Prénom')} value={name} onChangeText={setName} maxLength={40} />
        <Field label={t('E-mail du caissier')} value={email} onChangeText={setEmail} keyboardType="email-address" autoCapitalize="none" autoCorrect={false} />
        <ErrorText>{error}</ErrorText>
        <InfoText>{info}</InfoText>
        <Button title={t('Ajouter')} onPress={add} loading={busy} />

        <SectionTitle>{list.length ? t('Mes caissiers ({n})', { n: list.length }) : t('Mes caissiers')}</SectionTitle>
        {active.length ? (
          <Muted>{t('Aujourd’hui : {n} achat(s) saisi(s) en caisse · {amount}', { n: todayCount, amount: euros(todayCents) })}</Muted>
        ) : null}
        {list.length === 0 ? <Muted>{t('Aucun caissier pour l’instant. Seul vous avez accès à la caisse.')}</Muted> : null}
        {list.map((c) => (
          <View key={c.id} style={[styles.card, c.status === 'invited' && { borderColor: colors.saffron, borderWidth: 2 }]}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
              <Text style={{ fontSize: 17, fontWeight: '800', color: colors.text, flex: 1 }}>{c.display_name}</Text>
              <Text style={{ fontWeight: '700', color: c.status === 'active' ? colors.success : colors.saffronDark }}>
                {c.status === 'active' ? t('Actif') : t('Invitation envoyée')}
              </Text>
            </View>
            <Muted>{c.email}</Muted>
            {c.status === 'active' ? (
              <>
                <Text style={{ color: colors.text, marginTop: 4 }}>
                  {t('Aujourd’hui : {n} achat(s) · {amount}', { n: c.today_count, amount: euros(Number(c.today_cents)) })}
                </Text>
                <Muted>{t('30 derniers jours : {n} achat(s) · {amount}', { n: c.month_count, amount: euros(Number(c.month_cents)) })}</Muted>
                {c.accepted_at ? <Muted>{t('Caissier depuis le {date}', { date: shortDate(c.accepted_at) })}</Muted> : null}
              </>
            ) : (
              <Muted>{t('En attente : il doit créer son compte avec cet e-mail et accepter l’invitation dans l’appli.')}</Muted>
            )}
            <Button title={t('Retirer')} variant="secondary" onPress={() => remove(c)} />
          </View>
        ))}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
