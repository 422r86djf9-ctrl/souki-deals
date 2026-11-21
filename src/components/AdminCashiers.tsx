// Administration : achats d'un commerce par caissier (30 derniers jours), affichés à la demande
import { useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import { euros } from '../lib/deals';
import { t } from '../lib/i18n';
import { errorMessage, supabase } from '../lib/supabase';
import { colors, ErrorText, Muted } from '../lib/theme';

type Row = { scanned_by: string | null; name: string; is_owner: boolean; count: number; amount_cents: number };

export function AdminCashiers({ shopId }: { shopId: string }) {
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState('');

  async function toggle() {
    if (rows) return setRows(null);
    setError('');
    const { data, error } = await supabase.rpc('admin_shop_cashiers', { p_shop: shopId });
    if (error) return setError(errorMessage(error));
    setRows((data ?? []) as Row[]);
  }

  return (
    <View>
      <Pressable onPress={toggle} accessibilityRole="button" style={{ paddingVertical: 6 }}>
        <Text style={{ color: colors.prune, fontWeight: '700' }}>{rows ? t('Masquer les achats par caissier') : t('Achats par caissier (30 jours)')}</Text>
      </Pressable>
      <ErrorText>{error}</ErrorText>
      {rows && rows.length === 0 ? <Muted>{t('Aucun achat ces 30 derniers jours.')}</Muted> : null}
      {rows?.map((r) => (
        <View key={r.scanned_by ?? r.name} style={{ flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 3 }}>
          <Text style={{ color: colors.text, flex: 1 }}>
            {r.is_owner ? t('Patron') : r.name === 'Ancien caissier' ? t('Ancien caissier') : r.name}
          </Text>
          <Text style={{ color: colors.text, fontWeight: '700' }}>{`${r.count} · ${euros(Number(r.amount_cents))}`}</Text>
        </View>
      ))}
    </View>
  );
}
