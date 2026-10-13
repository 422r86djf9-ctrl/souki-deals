// Politique de confidentialité (aussi publiée sur le site, exigée par Google Play et l'App Store)
import { Stack } from 'expo-router';
import { ScrollView, Text } from 'react-native';
import { PRIVACY_SECTIONS, PRIVACY_UPDATED } from '../src/lib/confidentialite';
import { t } from '../src/lib/i18n';
import { colors, Muted } from '../src/lib/theme';

export default function Confidentialite() {
  return (
    <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 20, paddingBottom: 40 }}>
      <Stack.Screen options={{ title: t('Confidentialité') }} />
      <Text style={{ fontSize: 24, fontWeight: '900', color: colors.prune }}>Politique de confidentialité</Text>
      <Muted>{`Mise à jour : ${PRIVACY_UPDATED}`}</Muted>
      {PRIVACY_SECTIONS.map((s) => (
        <Text key={s.title} style={{ color: colors.text, marginTop: 14, lineHeight: 21 }}>
          <Text style={{ fontWeight: '800', color: colors.prune }}>{`${s.title}\n`}</Text>
          {s.body.join('\n\n')}
        </Text>
      ))}
    </ScrollView>
  );
}
