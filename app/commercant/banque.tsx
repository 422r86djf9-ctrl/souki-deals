// Coordonnées bancaires du commerçant : Souki Deals y verse les offres de bienvenue à rembourser
import { Stack, router } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, KeyboardAvoidingView, Platform, ScrollView, Text, View } from 'react-native';
import { t } from '../../src/lib/i18n';
import { errorMessage, supabase } from '../../src/lib/supabase';
import { Button, colors, ErrorText, Field, Muted, styles } from '../../src/lib/theme';

// « FR7630006000011234567890189 » -> « FR76 3000 6000 0112 3456 7890 189 »
function formatIban(iban: string): string {
  return iban.replace(/\s/g, '').toUpperCase().replace(/(.{4})/g, '$1 ').trim();
}

export default function Banque() {
  const [loading, setLoading] = useState(true);
  const [holder, setHolder] = useState('');
  const [iban, setIban] = useState('');
  const [bic, setBic] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    (async () => {
      const { data } = await supabase.from('shop_bank').select('holder, iban, bic').maybeSingle();
      if (data) {
        const d = data as { holder: string; iban: string; bic: string | null };
        setHolder(d.holder);
        setIban(formatIban(d.iban));
        setBic(d.bic ?? '');
      }
      setLoading(false);
    })();
  }, []);

  async function save() {
    setError('');
    if (holder.trim().length < 2) return setError(t('Indiquez le titulaire du compte.'));
    setBusy(true);
    const { error } = await supabase.rpc('merchant_save_bank', { p_holder: holder.trim(), p_iban: iban, p_bic: bic.trim() || null });
    setBusy(false);
    if (error) return setError(errorMessage(error));
    router.back();
  }

  if (loading) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 16, paddingBottom: 40 }} keyboardShouldPersistTaps="handled">
        <Stack.Screen options={{ title: t('Mon IBAN') }} />
        <View style={styles.card}>
          <Text style={{ fontWeight: '800', color: colors.text }}>{t('Pour recevoir vos remboursements')}</Text>
          <Muted>
            {t('Quand les offres de bienvenue dépassent votre commission de la semaine, Souki Deals vous verse la différence sur ce compte.')}
          </Muted>
        </View>
        <Field label={t('Titulaire du compte')} value={holder} onChangeText={setHolder} maxLength={70} placeholder={t('Nom de la société ou du gérant')} />
        <Field
          label={t('IBAN')}
          value={iban}
          onChangeText={(v) => setIban(formatIban(v.replace(/[^A-Za-z0-9]/g, '')))}
          autoCapitalize="characters"
          autoCorrect={false}
          maxLength={42}
          placeholder="FR76 …"
        />
        <Field
          label={t('BIC (facultatif)')}
          value={bic}
          onChangeText={(v) => setBic(v.toUpperCase().replace(/[^A-Z0-9]/g, ''))}
          autoCapitalize="characters"
          autoCorrect={false}
          maxLength={11}
        />
        <Muted>{t('Recopiez-les depuis votre RIB. Seul Souki Deals les voit, uniquement pour vous faire des virements.')}</Muted>
        <ErrorText>{error}</ErrorText>
        <Button title={t('Enregistrer mon IBAN')} onPress={save} loading={busy} />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
