// Bas du profil : version installée, mise à jour à distance en cours, et bouton pour en chercher une
import Constants from 'expo-constants';
import * as Updates from 'expo-updates';
import { useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import { t } from '../lib/i18n';
import { colors } from '../lib/theme';

export function AppVersion() {
  const [status, setStatus] = useState('');
  const [busy, setBusy] = useState(false);
  const v = Constants.expoConfig?.version ?? '';
  const d = Updates.isEmbeddedLaunch ? null : Updates.createdAt;
  const when = d
    ? `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')} ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
    : null;

  async function check() {
    if (busy) return;
    setBusy(true);
    setStatus(t('Recherche d’une mise à jour…'));
    try {
      if (!Updates.isEnabled) {
        setStatus(t('Mises à jour à distance désactivées dans cette installation.'));
        return;
      }
      const r = await Updates.checkForUpdateAsync();
      if (!r.isAvailable) {
        setStatus(t('Vous avez déjà la dernière version.'));
        return;
      }
      setStatus(t('Téléchargement de la mise à jour…'));
      await Updates.fetchUpdateAsync();
      await Updates.reloadAsync();
    } catch (e) {
      setStatus(`${t('Erreur')} : ${(e as Error)?.message ?? String(e)}`);
    } finally {
      setBusy(false);
    }
  }

  return (
    <View style={{ alignItems: 'center', marginTop: 24, gap: 4 }}>
      <Text style={{ color: colors.muted, fontSize: 12, textAlign: 'center' }}>
        {when ? t('Version {v} · mise à jour du {d}', { v, d: when }) : t('Version {v}', { v })}
      </Text>
      <Text style={{ color: colors.muted, fontSize: 10, textAlign: 'center' }} selectable>
        {`${Updates.channel ?? '-'} · ${Updates.runtimeVersion ?? '-'} · ${(Updates.updateId ?? 'embarquée').slice(0, 8)}`}
      </Text>
      <Pressable onPress={check} accessibilityRole="button" style={{ paddingVertical: 10, paddingHorizontal: 16 }}>
        <Text style={{ color: colors.prune, fontWeight: '700', fontSize: 13 }}>{t('Chercher une mise à jour')}</Text>
      </Pressable>
      {status ? <Text style={{ color: colors.muted, fontSize: 12, textAlign: 'center' }}>{status}</Text> : null}
    </View>
  );
}
