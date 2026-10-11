// Le client confirme le montant payé en caisse, ou le conteste
import { useState } from 'react';
import { Text, TextInput, View } from 'react-native';
import { euros } from '../lib/deals';
import { t } from '../lib/i18n';
import { errorMessage, supabase } from '../lib/supabase';
import { Button, colors, ErrorText, styles } from '../lib/theme';

export function PurchaseAnswer({ id, amountCents, shopName, onDone }: { id: string; amountCents: number; shopName: string; onDone: () => void }) {
  const [disputing, setDisputing] = useState(false);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function answer(ok: boolean) {
    setError('');
    if (!ok && reason.trim().length < 3) return setError(t('Expliquez en quelques mots ce qui ne va pas.'));
    setBusy(true);
    const { error } = await supabase.rpc('client_answer_purchase', { p_id: id, p_ok: ok, p_reason: ok ? null : reason.trim() });
    setBusy(false);
    if (error) return setError(errorMessage(error));
    onDone();
  }

  return (
    <View style={[styles.card, { borderColor: colors.saffron, borderWidth: 2 }]}>
      <Text style={{ fontSize: 17, fontWeight: '800', color: colors.text }}>
        {t('Vous avez payé {amount} chez {shop} ?', { amount: euros(amountCents), shop: shopName })}
      </Text>
      <ErrorText>{error}</ErrorText>
      {disputing ? (
        <>
          <TextInput
            value={reason}
            onChangeText={setReason}
            placeholder={t('Ex. : j’ai payé 30 €, pas 40 €')}
            placeholderTextColor={colors.muted}
            maxLength={500}
            style={[styles.input, { marginTop: 8 }]}
          />
          <Button title={t('Envoyer la contestation')} onPress={() => answer(false)} loading={busy} />
          <Button title={t('Annuler')} variant="secondary" onPress={() => setDisputing(false)} />
        </>
      ) : (
        <>
          <Button title={t('Oui, c’est le bon montant')} onPress={() => answer(true)} loading={busy} />
          <Button title={t('Non, ce n’est pas le bon montant')} variant="secondary" onPress={() => setDisputing(true)} disabled={busy} />
        </>
      )}
    </View>
  );
}
