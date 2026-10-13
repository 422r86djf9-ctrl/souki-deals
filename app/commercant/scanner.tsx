// Scanner le bon du client en caisse, puis saisir le montant payé
import { Stack } from 'expo-router';
import { useEffect, useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, Text, TextInput, View } from 'react-native';
import { Scanner } from '../../src/components/Scanner';
import { WelcomeBanner } from '../../src/components/WelcomeBanner';
import { euros, parseEuros } from '../../src/lib/deals';
import { t } from '../../src/lib/i18n';
import { errorMessage, supabase } from '../../src/lib/supabase';
import { Button, colors, ErrorText, Field, Muted, styles } from '../../src/lib/theme';

type Result = { purchase_id: string; amount_cents: number; commission_cents: number; free: boolean; welcome_cents?: number };
type Info = { first_name: string; status: string; welcome_cents: number; welcome_min_cents: number };

export default function ScannerScreen() {
  const [code, setCode] = useState('');
  const [step, setStep] = useState<'scan' | 'amount' | 'done'>('scan');
  const [amount, setAmount] = useState('');
  const [discount, setDiscount] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [result, setResult] = useState<Result | null>(null);
  const [info, setInfo] = useState<Info | null>(null);

  useEffect(() => {
    supabase.rpc('merchant_stats').then(({ data }) => setDiscount((data as { discount_pct?: number } | null)?.discount_pct ?? null));
  }, []);

  async function takeCode(c: string) {
    setError('');
    const code = c.toUpperCase();
    setCode(code);
    setInfo(null);
    const { data, error } = await supabase.rpc('merchant_voucher_info', { p_code: code });
    if (error) return setError(errorMessage(error));
    setInfo(data as Info);
    setStep('amount');
  }

  async function validate() {
    setError('');
    const cents = parseEuros(amount);
    if (!cents) return setError(t('Montant invalide (ex. 19,00).'));
    setBusy(true);
    const { data, error } = await supabase.rpc('merchant_scan', { p_code: code, p_amount_cents: cents });
    setBusy(false);
    if (error) return setError(errorMessage(error));
    setResult(data as Result);
    setStep('done');
  }

  function again() {
    setCode('');
    setAmount('');
    setResult(null);
    setInfo(null);
    setError('');
    setStep('scan');
  }

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 16, paddingBottom: 40 }} keyboardShouldPersistTaps="handled">
        <Stack.Screen options={{ title: t('Scanner un bon') }} />
        {step === 'scan' ? (
          <>
            <Muted>{t('Visez le QR code sur le téléphone du client.')}</Muted>
            <View style={{ height: 10 }} />
            <Scanner onCode={takeCode} />
            <View style={{ height: 16 }} />
            <Field
              label={t('Ou tapez le code du bon (8 caractères)')}
              value={code}
              onChangeText={(v) => setCode(v.toUpperCase().replace(/[^A-Z0-9]/g, ''))}
              autoCapitalize="characters"
              maxLength={8}
            />
            <Button title={t('Continuer')} onPress={() => takeCode(code)} disabled={code.length !== 8} />
          </>
        ) : null}

        {step === 'amount' ? (
          <>
            <View style={styles.card}>
              <Text style={{ color: colors.muted }}>{t('Bon')}</Text>
              <Text style={{ fontSize: 28, fontWeight: '900', letterSpacing: 4, color: colors.text }}>{code}</Text>
              {info ? <Text style={{ fontSize: 18, fontWeight: '800', color: colors.text }}>{info.first_name}</Text> : null}
              {discount != null ? (
                <Text style={{ color: colors.prune, fontWeight: '700', marginTop: 6 }}>
                  {t('Appliquez votre remise de {pct} % en caisse, puis saisissez le montant payé.', { pct: discount })}
                </Text>
              ) : null}
              {info ? <WelcomeBanner cents={info.welcome_cents} minCents={info.welcome_min_cents} /> : null}
            </View>
            <Field
              label={t('Montant payé par le client, remise déduite (€)')}
              value={amount}
              onChangeText={(v) => setAmount(v.replace(/[^0-9.,]/g, ''))}
              keyboardType="decimal-pad"
              autoFocus
              maxLength={9}
            />
            <ErrorText>{error}</ErrorText>
            <Button title={t('Valider l’achat')} onPress={validate} loading={busy} />
            <Button title={t('Annuler')} variant="secondary" onPress={again} />
          </>
        ) : null}

        {step === 'done' && result ? (
          <>
            <View style={[styles.card, { borderColor: colors.success, borderWidth: 2 }]}>
              <Text style={{ fontSize: 20, fontWeight: '900', color: colors.success }}>{t('Achat enregistré')}</Text>
              <Text style={{ fontSize: 16, color: colors.text, marginTop: 6 }}>{t('Montant : {amount}', { amount: euros(result.amount_cents) })}</Text>
              {result.welcome_cents ? (
                <Text style={{ fontSize: 16, color: colors.success, fontWeight: '700' }}>
                  {t('Bienvenue remboursée par Souki Deals : {amount}', { amount: euros(result.welcome_cents) })}
                </Text>
              ) : null}
              <Text style={{ fontSize: 16, color: colors.text }}>
                {result.free
                  ? t('Commission : offerte (offre de lancement)')
                  : t('Commission Souki Deals : {amount}', { amount: euros(result.commission_cents) })}
              </Text>
              <Muted>{t('Le client confirme le montant sur son téléphone.')}</Muted>
            </View>
            <Button title={t('Scanner un autre bon')} onPress={again} />
          </>
        ) : null}
        {step === 'scan' ? <ErrorText>{error}</ErrorText> : null}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
