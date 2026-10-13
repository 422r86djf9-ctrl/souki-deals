// En caisse : rappel de l'offre de bienvenue à déduire (payée par Souki Deals)
import { Text, View } from 'react-native';
import { euros } from '../lib/deals';
import { t } from '../lib/i18n';
import { colors } from '../lib/theme';

export function WelcomeBanner({ cents, minCents }: { cents: number; minCents: number }) {
  if (!cents) return null;
  return (
    <View style={{ backgroundColor: colors.saffronSoft, borderRadius: 12, padding: 12, marginTop: 8 }}>
      <Text style={{ fontWeight: '900', color: colors.text, fontSize: 16 }}>
        {t('Nouveau client : déduisez {amount} de plus', { amount: euros(cents) })}
      </Text>
      <Text style={{ color: colors.text, marginTop: 2 }}>
        {t('Pour un achat d’au moins {min}. Souki Deals vous rembourse cette somme sur votre commission.', { min: euros(minCents) })}
      </Text>
    </View>
  );
}
