// Bas du profil : version installée et date de la dernière mise à jour à distance
import Constants from 'expo-constants';
import * as Updates from 'expo-updates';
import { Text } from 'react-native';
import { t } from '../lib/i18n';
import { colors } from '../lib/theme';

export function AppVersion() {
  const v = Constants.expoConfig?.version ?? '';
  const d = Updates.isEmbeddedLaunch ? null : Updates.createdAt;
  const when = d
    ? `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
    : null;
  return (
    <Text style={{ color: colors.muted, fontSize: 12, textAlign: 'center', marginTop: 24 }}>
      {when ? t('Version {v} · mise à jour du {d}', { v, d: when }) : t('Version {v}', { v })}
    </Text>
  );
}
