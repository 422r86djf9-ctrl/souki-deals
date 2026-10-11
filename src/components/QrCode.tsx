// QR code du bon, dessiné dans une WebView (bibliothèque qrcodejs). Le code en clair reste affiché dessous.
import { View } from 'react-native';
import { WebView } from 'react-native-webview';

export function QrCode({ value, size = 240 }: { value: string; size?: number }) {
  const safe = value.replace(/[^A-Z0-9:]/gi, '');
  const html = `<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
<style>html,body{margin:0;height:100%;display:flex;align-items:center;justify-content:center;background:#fff}</style></head>
<body><div id="q"></div><script>new QRCode(document.getElementById('q'),{text:'${safe}',width:${size - 24},height:${size - 24},correctLevel:QRCode.CorrectLevel.M});</script></body></html>`;
  return (
    <View style={{ width: size, height: size, borderRadius: 16, overflow: 'hidden', backgroundColor: '#fff', alignSelf: 'center' }}>
      <WebView source={{ html }} originWhitelist={['*']} javaScriptEnabled scrollEnabled={false} style={{ backgroundColor: '#fff' }} />
    </View>
  );
}
