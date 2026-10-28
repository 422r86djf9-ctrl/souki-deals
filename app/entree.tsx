// Client : en entrant dans le magasin, il scanne le QR code collé sur la tablette du comptoir.
// Sa visite s'affiche chez le commerçant, qui saisit le montant payé ; le client le confirme ici.
import { Stack, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, ScrollView, Text, View } from 'react-native';
import { PurchaseAnswer } from '../src/components/PurchaseAnswer';
import { Scanner } from '../src/components/Scanner';
import { euros, openDirections, shopCodeFromScan } from '../src/lib/deals';
import { tryArrive } from '../src/lib/arrival';
import { t } from '../src/lib/i18n';
import { getChosenPromo, Promo, promoLabel, setChosenPromo } from '../src/lib/promos';
import { errorMessage, supabase } from '../src/lib/supabase';
import { Button, colors, DiscountTag, ErrorText, Field, Muted, styles } from '../src/lib/theme';

type Visit = {
  id: string;
  status: 'reserved' | 'waiting' | 'done' | 'expired' | 'dismissed' | 'cancelled';
  expires_at: string;
  purchase_id: string | null;
  shop_id: string;
  promos: Promo | null;
  shops: { name: string; discount_pct: number; lat: number; lng: number } | null;
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
  const [firstName, setFirstName] = useState('');
  const [arriveMsg, setArriveMsg] = useState('');
  const [checking, setChecking] = useState(false);
  const [showScan, setShowScan] = useState(false);

  const loadVisit = useCallback(async (id?: string) => {
    const { data: u } = await supabase.auth.getUser();
    const uid = u.user?.id;
    if (!uid) return;
    supabase
      .from('profiles')
      .select('full_name')
      .eq('id', uid)
      .maybeSingle()
      .then(({ data: pf }) => setFirstName(((pf as { full_name: string | null } | null)?.full_name ?? '').split(' ')[0]));
    let q = supabase
      .from('checkins')
      .select('id, status, expires_at, purchase_id, shop_id, promos(id, shop_id, kind, title, discount_pct, min_cents, ends_at), shops(name, discount_pct, lat, lng), vouchers(code)')
      .eq('client_id', uid);
    q = id ? q.eq('id', id) : q.in('status', ['waiting', 'reserved']).gt('expires_at', new Date().toISOString());
    const { data } = await q.order('created_at', { ascending: false }).limit(1).maybeSingle();
    const v = (data ?? null) as unknown as Visit | null;
    setVisit(v);
    if (v && (v.status === 'waiting' || v.status === 'reserved')) {
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

  // Précommande : on vérifie la position (à l'ouverture, puis toutes les 20 s) pour activer la visite à l'arrivée
  const arrive = useCallback(
    async (manual: boolean) => {
      if (!visit || visit.status !== 'reserved') return;
      setChecking(true);
      const r = await tryArrive(visit.id, manual);
      setChecking(false);
      if (r.ok) {
        setArriveMsg('');
        await loadVisit(visit.id);
      } else if (r.message === 'NO_PERMISSION') {
        setArriveMsg(t('Autorisez la localisation pour que l’appli détecte votre arrivée, ou scannez le QR code du comptoir.'));
      } else if (manual || r.far) {
        setArriveMsg(r.message);
      }
    },
    [visit, loadVisit],
  );
  useEffect(() => {
    if (!visit || visit.status !== 'reserved') return;
    arrive(false);
    const timer = setInterval(() => arrive(false), 20000);
    return () => clearInterval(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visit?.id, visit?.status]);

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
    Alert.alert(
      visit.status === 'reserved' ? t('Annuler la précommande ?') : t('Repartir sans acheter ?'),
      t('Votre visite et votre bon seront annulés.'),
      [
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
      {!visit || visit.status === 'cancelled' || (visit.status === 'reserved' && showScan) ? (
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

      {/* 1 bis. Précommande : en route vers le magasin */}
      {visit?.status === 'reserved' && !showScan ? (
        <View style={{ gap: 14 }}>
          <View style={{ backgroundColor: colors.prune, borderRadius: 22, padding: 18, gap: 6 }}>
            <Text style={{ color: '#CDEBD7', fontWeight: '800', fontSize: 12, letterSpacing: 1 }}>{t('PRÉCOMMANDE VALIDÉE ✓')}</Text>
            <Text style={{ color: '#FFFFFF', fontWeight: '900', fontSize: 24 }}>{visit.shops?.name ?? ''}</Text>
            <Text style={{ color: '#FFFFFF', fontSize: 16, fontWeight: '700' }}>
              {visit.promos ? promoLabel(visit.promos) : t('Remise de {pct} % sur tout le magasin', { pct: Number(visit.shops?.discount_pct ?? 5).toLocaleString('fr-FR') })}
            </Text>
          </View>
          <View style={[styles.card, { gap: 6 }]}>
            <Text style={{ fontWeight: '800', color: colors.text, fontSize: 16 }}>{t('En arrivant, ouvrez simplement l’appli')}</Text>
            <Text style={{ color: colors.text }}>
              {t('Elle détecte que vous êtes au magasin et prévient le commerçant. Vous n’avez rien à scanner ni à montrer : après avoir payé, vous confirmez juste le montant.')}
            </Text>
          </View>
          {arriveMsg ? <Text style={{ color: colors.saffronDark, fontWeight: '700', textAlign: 'center' }}>{arriveMsg}</Text> : null}
          <Button title={checking ? t('Vérification de votre position…') : t('Je suis arrivé')} onPress={() => arrive(true)} disabled={checking} />
          {visit.shops ? <Button title={t('Itinéraire')} variant="secondary" onPress={() => openDirections(visit.shops!.lat, visit.shops!.lng)} /> : null}
          <Pressable onPress={() => setShowScan(true)} accessibilityRole="button" style={{ paddingVertical: 8 }}>
            <Text style={{ color: colors.prune, fontWeight: '700', textAlign: 'center' }}>{t('Pas détecté ? Scannez le QR code du comptoir')}</Text>
          </Pressable>
          <Pressable onPress={leave} accessibilityRole="button" style={{ paddingVertical: 8 }}>
            <Text style={{ color: colors.muted, textAlign: 'center', textDecorationLine: 'underline' }}>{t('Annuler la précommande')}</Text>
          </Pressable>
        </View>
      ) : null}

      {/* 2. En attente du montant : le bon à montrer en caisse */}
      {visit?.status === 'waiting' ? (
        <View style={{ backgroundColor: colors.prune, borderRadius: 26, padding: 16, gap: 14 }}>
          <View style={{ backgroundColor: '#FFFFFF', borderRadius: 22, overflow: 'hidden' }}>
            <View style={{ alignItems: 'center', paddingHorizontal: 18, paddingTop: 20, paddingBottom: 14, gap: 4 }}>
              <Text style={{ fontSize: 12, fontWeight: '800', letterSpacing: 2, color: colors.muted, textAlign: 'center' }}>{(visit.shops?.name ?? '').toUpperCase()}</Text>
              <Text style={{ fontSize: 60, fontWeight: '900', color: '#E8590C', lineHeight: 66 }}>
                {visit.promos
                  ? visit.promos.discount_pct
                    ? `-${Number(visit.promos.discount_pct).toLocaleString('fr-FR')} %`
                    : t('Cadeau')
                  : `-${Number(visit.shops?.discount_pct ?? 5).toLocaleString('fr-FR')} %`}
              </Text>
              <Text style={{ fontSize: 18, fontWeight: '800', color: colors.text, textAlign: 'center' }}>
                {visit.promos ? visit.promos.title : t('sur tout le magasin')}
              </Text>
              {visit.promos ? (
                <Text style={{ fontSize: 13, color: colors.muted, textAlign: 'center' }}>
                  {t('Et -{n} % sur le reste des achats', { n: Number(visit.shops?.discount_pct ?? 5).toLocaleString('fr-FR') })}
                </Text>
              ) : null}
            </View>
            <View style={{ flexDirection: 'row', alignItems: 'center' }}>
              <View style={{ width: 22, height: 44, borderTopRightRadius: 22, borderBottomRightRadius: 22, backgroundColor: colors.prune, marginLeft: -1 }} />
              <View style={{ flex: 1, borderTopWidth: 3, borderStyle: 'dashed', borderColor: colors.border }} />
              <View style={{ width: 22, height: 44, borderTopLeftRadius: 22, borderBottomLeftRadius: 22, backgroundColor: colors.prune, marginRight: -1 }} />
            </View>
            <View style={{ alignItems: 'center', paddingHorizontal: 18, paddingTop: 12, paddingBottom: 20, gap: 8 }}>
              <Text style={{ fontSize: 13, color: colors.muted }}>{t('Code à montrer en caisse')}</Text>
              <Text style={{ fontSize: 40, fontWeight: '900', color: colors.prune, letterSpacing: 4 }} numberOfLines={1} adjustsFontSizeToFit selectable>{visit.vouchers?.code ?? ''}</Text>
              <Text style={{ fontSize: 13, color: colors.muted }}>
                {[firstName, t('valable jusqu’à {h}', { h: new Date(visit.expires_at).toTimeString().slice(0, 5).replace(':', ' h ') })].filter(Boolean).join(' · ')}
              </Text>
              <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: colors.pruneSoft, borderRadius: 12, paddingHorizontal: 12, paddingVertical: 8 }}>
                <ActivityIndicator size="small" color={colors.prune} />
                <Text style={{ color: colors.prune, fontWeight: '700', fontSize: 13, flexShrink: 1 }}>{t('Le commerçant vous voit sur sa tablette : inutile de montrer votre téléphone')}</Text>
              </View>
            </View>
          </View>

          {welcome && welcome.amount_cents > 0 ? (
            <View style={{ backgroundColor: colors.saffron, borderRadius: 18, padding: 14, flexDirection: 'row', alignItems: 'center', gap: 12 }}>
              <Text style={{ fontSize: 24, fontWeight: '900', color: colors.text }}>{euros(welcome.amount_cents)}</Text>
              <Text style={{ flex: 1, fontSize: 13, fontWeight: '700', color: colors.text }}>
                {t('de bienvenue déduits si vous payez {min} ou plus', { min: euros(welcome.min_cents) })}
              </Text>
            </View>
          ) : null}

          {!visit.promos && shopPromos.length ? (
            <View style={{ gap: 8 }}>
              <Text style={{ fontWeight: '800', color: '#FFFFFF', textAlign: 'center' }}>{t('Une offre en cours ici :')}</Text>
              {shopPromos.map((p) => (
                <Pressable
                  key={p.id}
                  onPress={() => usePromo(p)}
                  accessibilityRole="button"
                  style={({ pressed }) => [{ minHeight: 50, borderRadius: 14, backgroundColor: '#E8590C', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 12 }, pressed && { opacity: 0.85 }]}
                >
                  <Text style={{ color: '#FFFFFF', fontWeight: '800', textAlign: 'center' }}>{t('Utiliser : {offer}', { offer: promoLabel(p) })}</Text>
                </Pressable>
              ))}
            </View>
          ) : null}

          <Text style={{ color: '#E5F4EA', textAlign: 'center', fontSize: 13 }}>
            {t('Payez en caisse avec la remise. Le commerçant saisit le montant sur sa tablette : il s’affichera ici.')}
          </Text>

          {visit.promos ? (
            <Pressable onPress={() => usePromo(null)} accessibilityRole="button" style={{ minHeight: 50, borderRadius: 14, borderWidth: 2, borderColor: '#FFFFFF', alignItems: 'center', justifyContent: 'center' }}>
              <Text style={{ color: '#FFFFFF', fontWeight: '800' }}>{t('Retirer cette offre')}</Text>
            </Pressable>
          ) : null}
          <Pressable onPress={leave} accessibilityRole="button" style={{ paddingVertical: 10 }}>
            <Text style={{ color: '#FFFFFF', textAlign: 'center', textDecorationLine: 'underline' }}>{t('Je repars sans acheter')}</Text>
          </Pressable>
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
