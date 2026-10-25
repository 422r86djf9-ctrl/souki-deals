// Client : en entrant dans le magasin, il scanne le QR code collé sur la tablette du comptoir.
// Sa visite s'affiche chez le commerçant, qui saisit le montant payé ; le client le confirme ici.
import { Stack, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Alert, ScrollView, Text, View } from 'react-native';
import { BonOffre } from '../src/components/BonOffre';
import { PurchaseAnswer } from '../src/components/PurchaseAnswer';
import { Scanner } from '../src/components/Scanner';
import { euros, shopCodeFromScan } from '../src/lib/deals';
import { t } from '../src/lib/i18n';
import { getChosenPromo, Promo, promoLabel, setChosenPromo } from '../src/lib/promos';
import { errorMessage, supabase } from '../src/lib/supabase';
import { Button, colors, DiscountTag, ErrorText, Field, Muted, styles } from '../src/lib/theme';

type Visit = {
  id: string;
  status: 'waiting' | 'done' | 'expired' | 'dismissed' | 'cancelled';
  expires_at: string;
  purchase_id: string | null;
  shop_id: string;
  promos: Promo | null;
  shops: { name: string; discount_pct: number } | null;
  vouchers: { code: string } | null;
};
type Purchase = { id: string; amount_cents: number; welcome_cents: number; status: string };

const POLL_MS = 4000;

export default function Entree() {
  const [visit, setVisit] = useState<Visit | null>(null);
  const [purchase, setPurchase] = useState<Purchase | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [typed, setTyped] = useState('');
  const [welcome, setWelcome] = useState<{ amount_cents: number; min_cents: number } | null>(null);
  const [shopPromos, setShopPromos] = useState<Promo[]>([]);

  const loadVisit = useCallback(async (id?: string) => {
    const { data: u } = await supabase.auth.getUser();
    const uid = u.user?.id;
    if (!uid) return;
    let q = supabase
      .from('checkins')
      .select('id, status, expires_at, purchase_id, shop_id, promos(id, shop_id, kind, title, discount_pct, min_cents, ends_at), shops(name, discount_pct), vouchers(code)')
      .eq('client_id', uid);
    q = id ? q.eq('id', id) : q.eq('status', 'waiting').gt('expires_at', new Date().toISOString());
    const { data } = await q.order('created_at', { ascending: false }).limit(1).maybeSingle();
    const v = (data ?? null) as unknown as Visit | null;
    setVisit(v);
    if (v && v.status === 'waiting') {
      const { data: pr } = await supabase
        .from('promos')
        .select('id, shop_id, kind, title, discount_pct, min_cents, ends_at')
        .eq('shop_id', v.shop_id)
        .eq('active', true)
        .gt('ends_at', new Date().toISOString());
      setShopPromos((pr ?? []) as Promo[]);
    }
    if (v?.purchase_id) {
      const { data: p } = await supabase.from('purchases').select('id, amount_cents, welcome_cents, status').eq('id', v.purchase_id).single();
      setPurchase((p ?? null) as Purchase | null);
    }
    setLoading(false);
  }, []);

  useFocusEffect(
    useCallback(() => {
      loadVisit();
      supabase.rpc('client_welcome').then(({ data }) => setWelcome((data ?? null) as { amount_cents: number; min_cents: number } | null));
    }, [loadVisit]),
  );

  // En attente du montant : on regarde régulièrement si le commerçant l'a saisi
  useEffect(() => {
    if (!visit || visit.status !== 'waiting') return;
    const id = visit.id;
    const timer = setInterval(() => loadVisit(id), POLL_MS);
    return () => clearInterval(timer);
  }, [visit, loadVisit]);

  async function checkin(code: string) {
    setError('');
    setBusy(true);
    const { data, error } = await supabase.rpc('client_checkin', { p_shop_code: code });
    setBusy(false);
    if (error) return setError(errorMessage(error));
    const res = data as { checkin_id: string; shop_id: string };
    // Offre choisie sur la fiche du commerce : on l'attache à la visite
    const chosen = getChosenPromo();
    if (chosen && chosen.shop_id === res.shop_id) {
      await supabase.rpc('client_set_checkin_promo', { p_id: res.checkin_id, p_promo_id: chosen.id });
    }
    setChosenPromo(null);
    await loadVisit(res.checkin_id);
  }

  async function usePromo(p: Promo | null) {
    if (!visit) return;
    setError('');
    const { error } = await supabase.rpc('client_set_checkin_promo', { p_id: visit.id, p_promo_id: p ? p.id : null });
    if (error) return setError(errorMessage(error));
    await loadVisit(visit.id);
  }

  function leave() {
    if (!visit) return;
    Alert.alert(t('Repartir sans acheter ?'), t('Votre visite et votre bon seront annulés.'), [
      { text: t('Rester'), style: 'cancel' },
      {
        text: t('Je repars'),
        onPress: async () => {
          const { error } = await supabase.rpc('client_cancel_checkin', { p_id: visit.id });
          if (error) return setError(errorMessage(error));
          setVisit(null);
          setPurchase(null);
        },
      },
    ]);
  }

  if (loading) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;

  return (
    <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 16, paddingBottom: 40 }}>
      <Stack.Screen options={{ title: t('Je suis dans le magasin') }} />
      <ErrorText>{error}</ErrorText>

      {/* 1. Scanner le QR code du magasin */}
      {!visit || visit.status === 'cancelled' ? (
        <>
          <Text style={{ fontSize: 20, fontWeight: '800', color: colors.text }}>{t('Scannez le QR code Souki Deals du magasin')}</Text>
          <Muted>{t('Il est collé sur la tablette, au comptoir. Votre remise sera appliquée en caisse.')}</Muted>
          <View style={{ height: 12 }} />
          <Scanner
            parse={shopCodeFromScan}
            hint={t("Autorisez l'appareil photo pour scanner le QR code du magasin. Vous pouvez aussi taper son code.")}
            onCode={(code) => {
              if (!busy) checkin(code);
            }}
          />
          {busy ? <ActivityIndicator style={{ marginTop: 12 }} color={colors.prune} /> : null}
          <View style={{ height: 16 }} />
          <Field
            label={t('Ou tapez le code écrit sous le QR code')}
            value={typed}
            onChangeText={(v) => setTyped(v.toUpperCase().replace(/[^A-Z0-9]/g, ''))}
            autoCapitalize="characters"
            maxLength={8}
            placeholder="ABCD2345"
          />
          <Button title={t('Valider le code')} variant="secondary" onPress={() => checkin(typed)} disabled={typed.length !== 8 || busy} />
        </>
      ) : null}

      {/* 2. En attente du montant */}
      {visit?.status === 'waiting' ? (
        <View style={[styles.card, { alignItems: 'center', paddingVertical: 22 }]}>
          <Text style={{ fontSize: 15, color: colors.muted }}>{t('Vous êtes chez')}</Text>
          <Text style={{ fontSize: 24, fontWeight: '900', color: colors.text, textAlign: 'center' }}>{visit.shops?.name ?? ''}</Text>
          <View style={{ marginVertical: 10 }}>
            <DiscountTag pct={visit.shops?.discount_pct ?? 5} big />
          </View>
          {welcome && welcome.amount_cents > 0 ? (
            <Text style={{ color: colors.success, fontWeight: '800', textAlign: 'center', marginBottom: 8 }}>
              {t('+ {amount} offerts sur ce premier achat dès {min} : le commerçant les déduit.', { amount: euros(welcome.amount_cents), min: euros(welcome.min_cents) })}
            </Text>
          ) : null}
          {visit.promos ? (
            <>
              <BonOffre promo={visit.promos} shopName={visit.shops?.name ?? ''} />
              <Button title={t('Retirer cette offre')} variant="secondary" onPress={() => usePromo(null)} />
            </>
          ) : shopPromos.length ? (
            <View style={{ width: '100%', marginBottom: 8 }}>
              <Text style={{ fontWeight: '800', color: colors.text, textAlign: 'center' }}>{t('Une offre en cours ici :')}</Text>
              {shopPromos.map((p) => (
                <Button key={p.id} title={t('Utiliser : {offer}', { offer: promoLabel(p) })} variant="secondary" onPress={() => usePromo(p)} />
              ))}
            </View>
          ) : null}
          <Text style={{ fontSize: 15, color: colors.muted }}>{t('Votre code')}</Text>
          <Text style={{ fontSize: 36, fontWeight: '900', color: colors.prune, letterSpacing: 4 }}>{visit.vouchers?.code ?? ''}</Text>
          <Text style={{ color: colors.text, textAlign: 'center', marginTop: 10 }}>
            {t('Payez en caisse avec la remise. Le commerçant saisit le montant sur sa tablette : il s’affichera ici.')}
          </Text>
          <ActivityIndicator style={{ marginTop: 14 }} color={colors.prune} />
          <Muted>{t('En attente du commerçant…')}</Muted>
          <View style={{ height: 8 }} />
          <Button title={t('Je repars sans acheter')} variant="secondary" onPress={leave} />
        </View>
      ) : null}

      {/* 3. Montant saisi : le client confirme */}
      {visit?.status === 'done' && purchase ? (
        purchase.status === 'pending' ? (
          <PurchaseAnswer id={purchase.id} amountCents={purchase.amount_cents} welcomeCents={purchase.welcome_cents} shopName={visit.shops?.name ?? ''} onDone={() => loadVisit(visit.id)} />
        ) : (
          <View style={[styles.card, { alignItems: 'center', paddingVertical: 22 }]}>
            <Text style={{ fontSize: 22, fontWeight: '900', color: colors.success }}>{t('Achat enregistré, merci !')}</Text>
            <Text style={{ color: colors.text, marginTop: 6 }}>{`${visit.shops?.name ?? ''} · ${euros(purchase.amount_cents)}`}</Text>
          </View>
        )
      ) : null}

      {visit && (visit.status === 'expired' || visit.status === 'dismissed') ? (
        <View style={styles.card}>
          <Text style={{ fontWeight: '800', color: colors.text }}>{t('Visite terminée sans montant saisi.')}</Text>
          <Muted>{t('Dites-nous si vous avez acheté dans « Mes bons et achats ».')}</Muted>
          <Button title={t('Nouvelle visite')} variant="secondary" onPress={() => setVisit(null)} />
        </View>
      ) : null}
    </ScrollView>
  );
}
