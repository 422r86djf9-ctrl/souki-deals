// Choisir un point sur la carte (position du commerce)
import { useState } from 'react';
import { Text, View } from 'react-native';
import { currentPosition } from '../lib/deals';
import { t } from '../lib/i18n';
import { Button, colors, Muted } from '../lib/theme';
import { LiveMap } from './LiveMap';

type Props = {
  value: { lat: number; lng: number } | null;
  onChange: (p: { lat: number; lng: number } | null) => void;
  hint: string;
};

export function MapPicker({ value, onChange, hint }: Props) {
  const [locating, setLocating] = useState(false);
  const [error, setError] = useState('');

  async function useMine() {
    setError('');
    setLocating(true);
    const p = await currentPosition();
    setLocating(false);
    if (p) onChange(p);
    else setError(t('Position indisponible : autorisez la localisation ou touchez la carte.'));
  }

  return (
    <View>
      <Muted>{hint}</Muted>
      <View style={{ height: 8 }} />
      <LiveMap
        markers={value ? [{ id: 'pick', kind: 'pick', lat: value.lat, lng: value.lng, label: t('Ici') }] : []}
        pickMode
        onPick={(lat, lng) => onChange({ lat, lng })}
        style={{ height: 260 }}
      />
      <Button title={t('Utiliser ma position actuelle')} variant="secondary" onPress={useMine} loading={locating} />
      {value ? <Text style={{ color: colors.success, marginTop: 6, fontWeight: '600' }}>{t('Point placé. Touchez la carte pour le déplacer.')}</Text> : null}
      {error ? <Text style={{ color: colors.danger, marginTop: 6 }}>{error}</Text> : null}
    </View>
  );
}
