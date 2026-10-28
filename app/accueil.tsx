import { Href, router, Stack, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { ActivityIndicator, Image, Pressable, RefreshControl, ScrollView, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { euros } from '../src/lib/deals';
import { registerForPush, unregisterPush, updateMyArea } from '../src/lib/push';
import { Espace, getEspace, setEspace } from '../src/lib/espace';
import { t } from '../src/lib/i18n';
import { errorMessage, supabase, whoami, Whoami } from '../src/lib/supabase';
import { Button, colors, DiscountTag, ErrorText, Muted, styles } from '../src/lib/theme';
import { Icon, IconName } from '../src/components/Icon';

function Card({ title, subtitle, badge, href, strong }: { title: string; subtitle: string; badge?: string; href: Href; strong?: boolean }) {
  return (
    <Pressable
      onPress={() => router.push(href)}
      accessibilityRole="button"
      style={({ pressed }) => [styles.card, strong && { backgroundColor: colors.prune, borderColor: colors.prune }, pressed && { opacity: 0.85 }]}
    >
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
        <Text style={{ fontSize: 18, fontWeight: '800', color: strong ? '#fff' : colors.text, flex: 1 }}>{title}</Text>
        {badge ? (
          <Text
            style={{
              backgroundColor: colors.saffron,
              color: colors.prune,
              fontWeight: '800',
              fontSize: 12,
              paddingHorizontal: 10,
              paddingVertical: 4,
              borderRadius: 99,
              overflow: 'hidden',
            }}
          >
            {badge}
          </Text>
        ) : null}
      </View>
      <Text style={{ color: strong ? colors.pruneSoft : colors.muted, marginTop: 4, fontSize: 15 }}>{subtitle}</Text>
    </Pressable>
  );
}

function shopBadge(s: NonNullable<Whoami['shop']>) {
  if (s.blocked) return t('Masqué');
  if (s.status === 'pending') return t('En validation');
  if (s.status === 'suspended') return t('Suspendu');
  return t('Actif');
}

type Promo = { id: number; shop_id: string; shop_name: string; kind: string; title: string; discount_pct: number | null; min_cents: number | null; ends_at: string | null };

function endsLabel(iso: string | null): string {
  if (!iso) return '';
  const d = new Date(iso);
  const today = new Date().toDateString() === d.toDateString();
  const h = `${d.getHours()} h${d.getMinutes() ? String(d.getMinutes()).padStart(2, '0') : ''}`;
  return today ? t('jusqu’à {h}', { h }) : '';
}

function Tile({ icon, title, subtitle, href }: { icon: IconName; title: string; subtitle: string; href: Href }) {
  return (
    <Pressable
      onPress={() => router.push(href)}
      accessibilityRole="button"
      style={({ pressed }) => [
        { flexBasis: '48%', flexGrow: 1, backgroundColor: colors.card, borderColor: colors.border, borderWidth: 1, borderRadius: 18, padding: 14, gap: 8 },
        pressed && { opacity: 0.85 },
      ]}
    >
      <View style={{ width: 42, height: 42, borderRadius: 12, backgroundColor: colors.pruneSoft, alignItems: 'center', justifyContent: 'center' }}>
        <Icon name={icon} color={colors.prune} />
      </View>
      <Text style={{ fontSize: 15, fontWeight: '800', color: colors.text }}>{title}</Text>
      <Text style={{ fontSize: 12, color: colors.muted }}>{subtitle}</Text>
    </Pressable>
  );
}

function NavItem({ icon, label, href, active }: { icon: IconName; label: string; href?: Href; active?: boolean }) {
  return (
    <Pressable
      onPress={() => (href ? router.push(href) : undefined)}
      accessibilityRole="button"
      accessibilityState={{ selected: !!active }}
      style={{ flex: 1, alignItems: 'center', justifyContent: 'center', minHeight: 48, gap: 2 }}
    >
      <Icon name={icon} color={active ? colors.prune : colors.muted} size={22} />
      <Text style={{ fontSize: 11, fontWeight: active ? '700' : '500', color: active ? colors.prune : colors.muted }}>{label}</Text>
    </Pressable>
  );
}

export default function Accueil() {
  const insets = useSafeAreaInsets();
  const [promos, setPromos] = useState<Promo[]>([]);
  const [me, setMe] = useState<Whoami | null>(null);
  const [espace, setEspaceState] = useState<Espace>('particulier');
  const [error, setError] = useState('');
  const [refreshing, setRefreshing] = useState(false);
  const [welcome, setWelcome] = useState<{ amount_cents: number; min_cents: number } | null>(null);
  const [promoCount, setPromoCount] = useState(0);
  const [unread, setUnread] = useState(0);

  const load = useCallback(async () => {
    setError('');
    try {
      const data = await whoami();
      if (!data.user_id) return router.replace('/connexion');
      if (!data.profile?.full_name) return router.replace('/profil');
      // Sans choix enregistré : commerçant s'il a déjà un commerce, sinon particulier
      const e = (await getEspace()) ?? (data.shop ? 'commercant' : 'particulier');
      setEspaceState(e);
      setMe(data);
      registerForPush();
      updateMyArea();
      const [w, pr, un] = await Promise.all([
        supabase.rpc('client_welcome'),
        supabase.rpc('active_promos', { p_lat: null, p_lng: null, p_radius_km: null }),
        supabase.rpc('support_unread'),
      ]);
      setUnread(typeof un.data === 'number' ? un.data : 0);
      setWelcome((w.data ?? null) as { amount_cents: number; min_cents: number } | null);
      setPromoCount(((pr.data ?? []) as unknown[]).length);
      setPromos((pr.data ?? []) as Promo[]);
    } catch (e) {
      setError(errorMessage(e));
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load]),
  );

  async function switchEspace() {
    const e: Espace = espace === 'commercant' ? 'particulier' : 'commercant';
    await setEspace(e);
    setEspaceState(e);
  }

  async function logout() {
    await unregisterPush();
    await supabase.auth.signOut();
    router.replace('/connexion');
  }

  if (!me && !error) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;

  const firstName = me?.profile?.full_name?.split(' ')[0] ?? '';
  const pending = me?.pending_purchases ?? 0;
  const visits = me?.visits_to_answer ?? 0;

  const flash = promos[0];
  const refresh = (
    <RefreshControl
      refreshing={refreshing}
      onRefresh={async () => {
        setRefreshing(true);
        await load();
        setRefreshing(false);
      }}
    />
  );

  if (me && espace === 'particulier') {
    return (
      <View style={{ flex: 1, backgroundColor: colors.background }}>
        <Stack.Screen options={{ headerShown: false }} />
        <ScrollView contentContainerStyle={{ paddingBottom: 20 }} refreshControl={refresh}>
          <View style={{ backgroundColor: colors.prune, paddingTop: insets.top + 16, paddingHorizontal: 20, paddingBottom: 22, borderBottomLeftRadius: 26, borderBottomRightRadius: 26, gap: 14 }}>
            <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }}>
              <View style={{ flex: 1 }}>
                <Text style={{ color: '#CDEBD7', fontSize: 13 }}>{t('Bonjour {name}', { name: firstName })}</Text>
                <Text style={{ color: '#FFFFFF', fontSize: 22, fontWeight: '800' }}>{t('Le halal au meilleur prix')}</Text>
              </View>
              <Pressable
                onPress={() => router.push('/messages')}
                accessibilityRole="button"
                accessibilityLabel={t('Écrire au fondateur')}
                style={{ width: 44, height: 44, borderRadius: 22, backgroundColor: 'rgba(255,255,255,0.16)', alignItems: 'center', justifyContent: 'center' }}
              >
                <Icon name="chat" color="#FFFFFF" />
                {unread > 0 ? <View style={{ position: 'absolute', top: 8, right: 8, width: 10, height: 10, borderRadius: 5, backgroundColor: colors.saffron }} /> : null}
              </Pressable>
            </View>
            <Pressable
              onPress={() => router.push('/recherche')}
              accessibilityRole="search"
              style={{ flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: '#FFFFFF', borderRadius: 14, height: 48, paddingHorizontal: 14 }}
            >
              <Icon name="search" color={colors.muted} size={20} />
              <Text style={{ color: colors.muted, fontSize: 14 }}>{t('Merguez, agneau, poulet…')}</Text>
            </Pressable>
          </View>

          <View style={{ padding: 20, gap: 16 }}>
            <ErrorText>{error}</ErrorText>
            {pending > 0 ? (
              <Card
                title={pending > 1 ? t('{n} achats à confirmer', { n: pending }) : t('{n} achat à confirmer', { n: pending })}
                subtitle={t('Vérifiez le montant payé en caisse.')}
                href="/achats"
                strong
              />
            ) : null}
            {visits > 0 ? (
              <Card title={t('Avez-vous acheté ?')} subtitle={t('Une visite sans montant saisi : dites-nous ce qui s’est passé.')} href="/achats" strong />
            ) : null}

            {welcome && welcome.amount_cents > 0 ? (
              <View style={{ backgroundColor: colors.saffron, borderRadius: 18, padding: 14, flexDirection: 'row', alignItems: 'center', gap: 14 }}>
                <Text style={{ fontSize: 28, fontWeight: '900', color: colors.text }}>{euros(welcome.amount_cents)}</Text>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontWeight: '800', color: colors.text }}>{t('offerts sur votre 1er achat')}</Text>
                  <Text style={{ fontSize: 12, color: colors.text }}>{t('dès {min}, en plus de la remise', { min: euros(welcome.min_cents) })}</Text>
                </View>
              </View>
            ) : null}

            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}>
              {(
                [
                  ['boucherie', t('Boucheries')],
                  ['epicerie', t('Épiceries')],
                  ['boulangerie', t('Boulangeries')],
                  ['restaurant', t('Restaurants')],
                  ['supermarche', t('Supermarchés')],
                ] as const
              ).map(([k, label]) => (
                <Pressable
                  key={k}
                  onPress={() => router.push({ pathname: '/autour', params: { kind: k } })}
                  accessibilityRole="button"
                  style={{ backgroundColor: colors.card, borderColor: colors.border, borderWidth: 1, borderRadius: 999, paddingHorizontal: 14, minHeight: 40, justifyContent: 'center' }}
                >
                  <Text style={{ fontSize: 13, fontWeight: '700', color: colors.text }}>{label}</Text>
                </Pressable>
              ))}
            </ScrollView>

            {flash ? (
              <View style={{ gap: 8 }}>
                <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'baseline' }}>
                  <Text style={{ fontSize: 17, fontWeight: '800', color: colors.text }}>{flash.kind === 'flash' ? t('Offre flash près de vous') : t('Offre du moment')}</Text>
                  <Text style={{ fontSize: 12, fontWeight: '700', color: colors.saffronDark }}>{endsLabel(flash.ends_at)}</Text>
                </View>
                <Pressable
                  onPress={() => router.push({ pathname: '/commerce/[id]', params: { id: flash.shop_id } })}
                  accessibilityRole="button"
                  style={({ pressed }) => [
                    { backgroundColor: colors.saffronSoft, borderColor: colors.saffron, borderWidth: 1.5, borderRadius: 18, padding: 14, flexDirection: 'row', alignItems: 'center', gap: 12 },
                    pressed && { opacity: 0.85 },
                  ]}
                >
                  <View style={{ flex: 1 }}>
                    <Text style={{ fontSize: 15, fontWeight: '800', color: colors.text }}>{flash.title}</Text>
                    <Text style={{ fontSize: 12, color: colors.muted }}>{flash.shop_name}</Text>
                  </View>
                  {flash.discount_pct ? <DiscountTag pct={flash.discount_pct} big /> : null}
                </Pressable>
                {promoCount > 1 ? (
                  <Pressable onPress={() => router.push('/offres')} accessibilityRole="link" style={{ paddingVertical: 6 }}>
                    <Text style={{ color: colors.prune, fontWeight: '700' }}>{t('Voir les {n} offres du moment', { n: promoCount })}</Text>
                  </Pressable>
                ) : null}
              </View>
            ) : null}

            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
              <Tile icon="pin" title={t('Autour de moi')} subtitle={t('Les commerces halal et leur remise')} href="/autour" />
              <Tile icon="search" title={t('Chercher un produit')} subtitle={t('Le moins cher autour de vous')} href="/recherche" />
              <Tile icon="ticket" title={t('Mes bons et achats')} subtitle={t('Vos bons et vos économies')} href="/achats" />
              <Tile icon="chat" title={t('Écrire au fondateur')} subtitle={unread > 0 ? t('{n} nouvelle réponse', { n: unread }) : t('Une question, une idée ?')} href="/messages" />
            </View>

            {me.shop ? <Card title={me.shop.name} subtitle={t('Scanner un bon, mes produits, mon compte.')} badge={shopBadge(me.shop)} href="/commercant" /> : null}
            {me.is_admin ? (
              <>
                <Card title={t('Administration')} subtitle={t('Commerces, contestations, commissions, réglages.')} badge={t('Fondateur')} href="/admin" />
                <Card
                  title={t('Messages des inscrits')}
                  subtitle={t('Les particuliers et commerçants qui vous écrivent.')}
                  badge={unread > 0 ? t('{n} non lus', { n: unread }) : undefined}
                  href="/admin?tab=messages"
                  strong={unread > 0}
                />
              </>
            ) : null}

            <Button title={t('Passer à l’espace commerçant')} variant="secondary" onPress={switchEspace} />
            <Button title={t('Se déconnecter')} variant="secondary" onPress={logout} />
          </View>
        </ScrollView>

        <View style={{ paddingHorizontal: 20, paddingTop: 10, backgroundColor: colors.background }}>
          <Pressable
            onPress={() => router.push('/entree')}
            accessibilityRole="button"
            style={({ pressed }) => [
              { height: 56, borderRadius: 16, backgroundColor: colors.prune, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 10 },
              pressed && { opacity: 0.85 },
            ]}
          >
            <Icon name="scan" color="#FFFFFF" />
            <Text style={{ color: '#FFFFFF', fontSize: 16, fontWeight: '800' }}>{t('Je suis dans le magasin')}</Text>
          </Pressable>
        </View>
        <View style={{ flexDirection: 'row', backgroundColor: colors.card, borderTopWidth: 1, borderTopColor: colors.border, marginTop: 10, paddingTop: 6, paddingBottom: Math.max(insets.bottom, 10) }}>
          <NavItem icon="home" label={t('Accueil')} active />
          <NavItem icon="pin" label={t('Carte')} href="/autour" />
          <NavItem icon="ticket" label={t('Mes bons')} href="/achats" />
          <NavItem icon="user" label={t('Profil')} href="/profil" />
        </View>
      </View>
    );
  }

  return (
    <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 20 }} refreshControl={refresh}>
      <Stack.Screen options={{ headerShown: true }} />
      <Image source={require('../assets/logo.png')} style={{ width: 190, height: 56, marginBottom: 10 }} resizeMode="contain" accessibilityLabel="Souki Deals" />
      <Text style={{ fontSize: 26, fontWeight: '800', color: colors.text }}>{t('Bonjour {name}', { name: firstName })}</Text>
      <Muted>{espace === 'commercant' ? t('Espace commerçant') : t('Le halal au meilleur prix, près de chez vous')}</Muted>
      <View style={{ height: 18 }} />
      <ErrorText>{error}</ErrorText>

      {me ? (
        <>
          {espace === 'commercant' ? (
            <Card
              title={me.shop ? me.shop.name : t('Inscrire mon commerce')}
              subtitle={me.shop ? t('Scanner un bon, mes produits, mon compte.') : t('Attirez de nouveaux clients : rien à payer si on ne vous en amène pas.')}
              badge={me.shop ? shopBadge(me.shop) : undefined}
              href={me.shop ? '/commercant' : '/commercant/inscription'}
              strong
            />
          ) : (
            <>
              {pending > 0 ? (
                <Card
                  title={pending > 1 ? t('{n} achats à confirmer', { n: pending }) : t('{n} achat à confirmer', { n: pending })}
                  subtitle={t('Vérifiez le montant payé en caisse.')}
                  href="/achats"
                  strong
                />
              ) : null}
              {visits > 0 ? (
                <Card
                  title={t('Avez-vous acheté ?')}
                  subtitle={t('Une visite sans montant saisi : dites-nous ce qui s’est passé.')}
                  href="/achats"
                  strong
                />
              ) : null}
              {welcome && welcome.amount_cents > 0 ? (
                <View style={[styles.card, { backgroundColor: colors.saffron, borderColor: colors.saffron }]}>
                  <Text style={{ fontSize: 20, fontWeight: '900', color: colors.text }}>{t('Bienvenue : {amount} offerts', { amount: euros(welcome.amount_cents) })}</Text>
                  <Text style={{ color: colors.text, marginTop: 2 }}>
                    {t('Sur votre premier achat dès {min}, dans le commerce partenaire de votre choix. En plus de la remise habituelle.', { min: euros(welcome.min_cents) })}
                  </Text>
                </View>
              ) : null}
              {promoCount > 0 ? (
                <Card title={t('Offres du moment ({n})', { n: promoCount })} subtitle={t('Offres flash et cadeaux des commerces près de chez vous.')} href="/offres" />
              ) : null}
              <Card title={t('Je suis dans le magasin')} subtitle={t('Scannez le QR code Souki Deals au comptoir pour avoir votre remise.')} href="/entree" strong />
              <Card title={t('Autour de moi')} subtitle={t('Boucheries, restaurants, épiceries halal près de vous, avec leur remise.')} href="/autour" />
              <Card title={t('Chercher un produit')} subtitle={t('Merguez, agneau, poulet… le moins cher autour de vous.')} href="/recherche" />
              <Card title={t('Mes bons et achats')} subtitle={t('Vos QR codes de réduction et vos économies.')} href="/achats" />
              {me.shop ? (
                <Card title={me.shop.name} subtitle={t('Scanner un bon, mes produits, mon compte.')} badge={shopBadge(me.shop)} href="/commercant" />
              ) : null}
            </>
          )}
          {me.is_admin ? (
            <>
              <Card title={t('Administration')} subtitle={t('Commerces, contestations, commissions, réglages.')} badge={t('Fondateur')} href="/admin" />
              <Card
                title={t('Messages des inscrits')}
                subtitle={t('Les particuliers et commerçants qui vous écrivent.')}
                badge={unread > 0 ? t('{n} non lus', { n: unread }) : undefined}
                href="/admin?tab=messages"
                strong={unread > 0}
              />
            </>
          ) : (
            <Card
              title={t('Écrire au fondateur')}
              subtitle={t('Une question, une idée, un souci ? Je vous réponds directement.')}
              badge={unread > 0 ? t('{n} nouvelle réponse', { n: unread }) : undefined}
              href="/messages"
              strong={unread > 0}
            />
          )}
        </>
      ) : null}

      <View style={{ height: 12 }} />
      {me ? (
        <Button
          title={espace === 'commercant' ? t('Passer à l’espace particulier') : t('Passer à l’espace commerçant')}
          variant="secondary"
          onPress={switchEspace}
        />
      ) : null}
      <Button title={t('Mon profil')} variant="secondary" onPress={() => router.push('/profil')} />
      <Button title={t('Se déconnecter')} variant="secondary" onPress={logout} />
    </ScrollView>
  );
}
