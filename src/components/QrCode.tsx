// QR code dessiné sans internet (générateur intégré, src/lib/qr.ts), affiché dans une WebView.
// Le code en clair reste affiché dessous par l'écran qui l'utilise.
import { View } from 'react-native';
import { WebView } from 'react-native-webview';
import { qrSvg } from '../lib/qr';

export function QrCode({ value, size = 240 }: { value: string; size?: number }) {
  const safe = value.replace(/[^A-Z0-9:]/gi, '').toUpperCase();
  const html = `<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>html,body{margin:0;height:100%;display:flex;align-items:center;justify-content:center;background:#fff}svg{width:100%;height:100%}</style></head>
<body>${qrSvg(safe, size)}</body></html>`;
  return (
    <View style={{ width: size, height: size, borderRadius: 16, overflow: 'hidden', backgroundColor: '#fff', alignSelf: 'center' }}>
      <WebView source={{ html }} originWhitelist={['*']} scrollEnabled={false} style={{ backgroundColor: '#fff' }} />
    </View>
  );
}
