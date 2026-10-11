// Lecture du QR code du client avec l'appareil photo (expo-camera)
import { CameraView, useCameraPermissions } from 'expo-camera';
import { useRef } from 'react';
import { View } from 'react-native';
import { codeFromScan } from '../lib/deals';
import { t } from '../lib/i18n';
import { Button, Muted } from '../lib/theme';

export function Scanner({ onCode }: { onCode: (code: string) => void }) {
  const [permission, requestPermission] = useCameraPermissions();
  const done = useRef(false);

  if (!permission) return null;
  if (!permission.granted) {
    return (
      <View>
        <Muted>{t("Autorisez l'appareil photo pour scanner les bons. Vous pouvez aussi taper le code.")}</Muted>
        <Button title={t("Autoriser l'appareil photo")} variant="secondary" onPress={requestPermission} />
      </View>
    );
  }
  return (
    <View style={{ height: 300, borderRadius: 16, overflow: 'hidden' }}>
      <CameraView
        style={{ flex: 1 }}
        facing="back"
        barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
        onBarcodeScanned={(r) => {
          const code = codeFromScan(r.data ?? '');
          if (code && !done.current) {
            done.current = true;
            onCode(code);
            setTimeout(() => {
              done.current = false;
            }, 2500);
          }
        }}
      />
    </View>
  );
}
