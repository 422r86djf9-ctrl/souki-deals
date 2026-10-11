import { Href, router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { ActivityIndicator, Pressable, RefreshControl, ScrollView, Text, View } from 'react-native';
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
  const [error, setError] = useState('');
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    setError('');
    try {
      const data = await whoami();
      if (!data.user_id) return router.replace('/connexion');
      if (!data.profile?.full_name) return router.replace('/profil');
      setMe(data);
    } catch (e) {
      setError(errorMessage(e));
    }
  }, []);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load]),
  );

  async function logout() {
    await supabase.auth.signOut();
    router.replace('/connexion');
  }

  if (!me && !error) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;

  const firstName = me?.profile?.full_name?.split(' ')[0] ?? '';
  const pending = me?.pending_purchases ?? 0;

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
      <Text style={{ fontSize: 26, fontWeight: '800', color: colors.text }}>{t('Bonjour {name}', { name: firstName })}</Text>
      <Muted>{t('Le halal au meilleur prix, près de chez vous')}</Muted>
      <View style={{ height: 18 }} />
      <ErrorText>{error}</ErrorText>

      {me ? (
        <>
          {pending > 0 ? (
            <Card
              title={pending > 1 ? t('{n} achats à confirmer', { n: pending }) : t('{n} achat à confirmer', { n: pending })}
              subtitle={t('Vérifiez le montant payé en caisse.')}
              href="/achats"
              strong
            />
          ) : null}
          <Card title={t('Autour de moi')} subtitle={t('Boucheries, restaurants, épiceries halal près de vous, avec leur remise.')} href="/autour" />
          <Card title={t('Chercher un produit')} subtitle={t('Merguez, agneau, poulet… le moins cher autour de vous.')} href="/recherche" />
          <Card title={t('Mes bons et achats')} subtitle={t('Vos QR codes de réduction et vos économies.')} href="/achats" />
          <Card
            title={me.shop ? me.shop.name : t('Inscrire mon commerce')}
            subtitle={me.shop ? t('Scanner un bon, mes produits, mon compte.') : t('Attirez de nouveaux clients : rien à payer si on ne vous en amène pas.')}
            badge={me.shop ? shopBadge(me.shop) : undefined}
            href={me.shop ? '/commercant' : '/commercant/inscription'}
          />
          {me.is_admin ? <Card title={t('Administration')} subtitle={t('Commerces, contestations, commissions, réglages.')} badge={t('Fondateur')} href="/admin" /> : null}
        </>
      ) : null}

      <View style={{ height: 12 }} />
      <Button title={t('Mon profil')} variant="secondary" onPress={() => router.push('/profil')} />
      <Button title={t('Se déconnecter')} variant="secondary" onPress={logout} />
    </ScrollView>
  );
}
