// Bon visuel de l'offre choisie : affiché au client en magasin (et rappelé au commerçant)
import { Text, View } from 'react-native';
import { t } from '../lib/i18n';
import { Promo, promoLabel, promoUntil } from '../lib/promos';
import { colors } from '../lib/theme';

export function BonOffre({ promo, shopName, code }: { promo: Promo; shopName: string; code?: string }) {
  return (
    <View style={{ borderWidth: 2, borderStyle: 'dashed', borderColor: colors.saffron, borderRadius: 16, backgroundColor: colors.saffronSoft, padding: 14, marginVertical: 10, width: '100%' }}>
      <Text style={{ fontSize: 12, fontWeight: '800', color: colors.saffronDark, letterSpacing: 1 }}>
        {promo.kind === 'flash' ? t('BON · OFFRE FLASH') : t('BON · CADEAU')}
      </Text>
      <Text style={{ fontSize: 20, fontWeight: '900', color: colors.text, marginTop: 4 }}>{promoLabel(promo)}</Text>
      <Text style={{ color: colors.muted, marginTop: 2 }}>{`${shopName} · ${promoUntil(promo)}`}</Text>
      {code ? <Text style={{ marginTop: 6, fontWeight: '800', color: colors.prune, letterSpacing: 3 }}>{t('Code {code}', { code })}</Text> : null}
      <Text style={{ fontSize: 12, color: colors.muted, marginTop: 6 }}>{t('Montrez ce bon en caisse : le commerçant le voit aussi sur sa tablette.')}</Text>
    </View>
  );
}
