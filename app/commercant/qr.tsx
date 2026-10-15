// QR code fixe du magasin, à coller sur la tablette du comptoir : le client le scanne en entrant
import { Stack } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, ScrollView, Text, View } from 'react-native';
import { QrCode } from '../../src/components/QrCode';
import { shopQrValue } from '../../src/lib/deals';
import { qrSvg } from '../../src/lib/qr';
import { t } from '../../src/lib/i18n';
import { shareHtmlAsPdf } from '../../src/lib/releve';
import { errorMessage, supabase } from '../../src/lib/supabase';
import { Button, colors, ErrorText, Muted, styles } from '../../src/lib/theme';

type ShopQr = { name: string; shop_code: string; discount_pct: number };

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c] as string);

// Autocollant imprimable (10 × 14 cm), deux par page A4
function stickerHtml(s: ShopQr): string {
  const pct = String(s.discount_pct).replace('.', ',');
  const one = `<div class="st">
    <div class="band">Souki Deals</div>
    <div class="big">Scannez en entrant</div>
    <div class="sub">-${esc(pct)} % de remise sur vos achats</div>
    <div class="qr">${qrSvg(shopQrValue(s.shop_code), 230)}</div>
    <div class="code">${esc(s.shop_code)}</div>
    <div class="name">${esc(s.name)}</div>
    <div class="ar">امسح الرمز عند الدخول · Scan when you come in</div>
  </div>`;
  return `<!doctype html><html><head><meta charset="utf-8">
<style>
  * { -webkit-print-color-adjust: exact; print-color-adjust: exact; box-sizing: border-box; }
  @page { size: A4; margin: 10mm; }
  body { font-family: Helvetica, Arial, sans-serif; margin: 0; }
  .page { display: flex; justify-content: space-around; flex-wrap: wrap; gap: 8mm; }
  .st { width: 100mm; height: 140mm; border: 1px dashed #bbb; border-radius: 6mm; overflow: hidden; text-align: center; }
  .band { background: #0E7A35; color: #fff; font-weight: bold; font-size: 18pt; padding: 4mm 0; }
  .big { font-size: 20pt; font-weight: 900; color: #0E7A35; margin-top: 5mm; }
  .sub { font-size: 13pt; color: #FF7A1A; font-weight: bold; margin: 1mm 0 4mm; }
  .qr { display: flex; justify-content: center; }
  .code { font-size: 18pt; font-weight: 900; letter-spacing: 3px; color: #1a1a1f; margin-top: 3mm; }
  .name { font-size: 11pt; color: #444; margin-top: 1mm; }
  .ar { font-size: 9pt; color: #666; margin-top: 3mm; }
</style></head><body>
  <div class="page">${one}${one}</div>
</body></html>`;
}

export default function QrMagasin() {
  const [shop, setShop] = useState<ShopQr | null>(null);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    (async () => {
      const { data: u } = await supabase.auth.getUser();
      const { data, error } = await supabase.from('shops').select('name, shop_code, discount_pct').eq('owner_id', u.user?.id ?? '').maybeSingle();
      if (error) setError(errorMessage(error));
      else setShop(data as ShopQr | null);
    })();
  }, []);

  async function print() {
    if (!shop) return;
    setBusy(true);
    setError('');
    try {
      await shareHtmlAsPdf(stickerHtml(shop), `Souki-Deals-QR-${shop.shop_code}`);
    } catch {
      setError(t('Impossible de préparer le fichier.'));
    } finally {
      setBusy(false);
    }
  }

  if (!shop && !error) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;

  return (
    <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 16, paddingBottom: 40 }}>
      <Stack.Screen options={{ title: t('QR code du magasin') }} />
      <ErrorText>{error}</ErrorText>
      {shop ? (
        <>
          <View style={[styles.card, { alignItems: 'center', paddingVertical: 20 }]}>
            <Text style={{ fontSize: 20, fontWeight: '900', color: colors.prune }}>{t('Scannez en entrant')}</Text>
            <Text style={{ color: colors.saffronDark, fontWeight: '800', marginBottom: 12 }}>
              {t('-{pct} % de remise sur vos achats', { pct: String(shop.discount_pct).replace('.', ',') })}
            </Text>
            <QrCode value={shopQrValue(shop.shop_code)} size={280} />
            <Text style={{ fontSize: 26, fontWeight: '900', letterSpacing: 4, color: colors.text, marginTop: 12 }}>{shop.shop_code}</Text>
            <Muted>{shop.name}</Muted>
          </View>
          <Button title={t('Imprimer l’autocollant (PDF)')} onPress={print} loading={busy} />
          <View style={styles.card}>
            <Text style={{ fontWeight: '800', color: colors.text, marginBottom: 4 }}>{t('Comment ça marche')}</Text>
            <Muted>{t('1. Imprimez l’autocollant et collez-le sur la tablette, bien visible au comptoir.')}</Muted>
            <Muted>{t('2. En entrant, le client scanne ce QR code avec Souki Deals : il apparaît dans « Clients présents ».')}</Muted>
            <Muted>{t('3. Appliquez la remise en caisse, puis saisissez le montant payé sur la tablette.')}</Muted>
            <Muted>{t('Ce QR code est le même pour tous vos clients et ne change jamais.')}</Muted>
          </View>
        </>
      ) : null}
    </ScrollView>
  );
}
