import { Href, router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { ActivityIndicator, Image, Pressable, RefreshControl, ScrollView, Text, View } from 'react-native';
import { euros } from '../src/lib/deals';
import { registerForPush, unregisterPush, updateMyArea } from '../src/lib/push';
import { Espace, getEspace, setEspace } from '../src/lib/espace';
import { t } from '../src/lib/i18n';
import { errorMessage, supabase, whoami, Whoami } from '../src/lib/supabase';
import { Button, colors, ErrorText, Muted, styles } from '../src/lib/theme';

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

export default function Accueil() {
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

  return (
    <ScrollView
      style={{ backgroundColor: colors.background }}
      contentContainerStyle={{ padding: 20 }}
      refreshControl={
        <RefreshControl
          refreshing={refreshing}
          onRefresh={async () => {
            setRefreshing(true);
            await load();
            setRefreshing(false);
          }}
        />
      }
    >
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
