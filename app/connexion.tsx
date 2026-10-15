// Connexion : on choisit d'abord son espace (particulier ou commerçant), puis e-mail et mot de passe
import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, Image, KeyboardAvoidingView, Platform, Pressable, ScrollView, Text, View } from 'react-native';
import { LanguagePicker } from '../src/components/LanguagePicker';
import { Espace, getEspace, setEspace } from '../src/lib/espace';
import { appleAvailable, signInWithApple, signInWithGoogle } from '../src/lib/social';
import { getLang, t } from '../src/lib/i18n';
import { errorMessage, supabase } from '../src/lib/supabase';
import { Button, colors, ErrorText, Field, InfoText, Muted, styles } from '../src/lib/theme';

function ChoiceCard({ title, subtitle, onPress, strong }: { title: string; subtitle: string; onPress: () => void; strong?: boolean }) {
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      style={({ pressed }) => [
        styles.card,
        { paddingVertical: 20 },
        strong && { backgroundColor: colors.prune, borderColor: colors.prune },
        pressed && { opacity: 0.85 },
      ]}
    >
      <Text style={{ fontSize: 20, fontWeight: '800', color: strong ? '#fff' : colors.prune }}>{title}</Text>
      <Text style={{ fontSize: 15, marginTop: 4, color: strong ? colors.pruneSoft : colors.muted }}>{subtitle}</Text>
    </Pressable>
  );
}

export default function Connexion() {
  const [espace, setEspaceState] = useState<Espace | null>(null);
  const [ready, setReady] = useState(false);
  const [mode, setMode] = useState<'login' | 'signup'>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');
  const [apple, setApple] = useState(false);

  useEffect(() => {
    getEspace().then((e) => {
      setEspaceState(e);
      setReady(true);
    });
    appleAvailable().then(setApple);
  }, []);

  async function choose(e: Espace | null) {
    setError('');
    setInfo('');
    setEspaceState(e);
    await setEspace(e);
  }

  async function submit() {
    setError('');
    setInfo('');
    const mail = email.trim().toLowerCase();
    if (!/^\S+@\S+\.\S+$/.test(mail)) return setError(t('Adresse e-mail invalide.'));
    if (password.length < 6) return setError(t('Le mot de passe doit faire au moins 6 caractères.'));
    setLoading(true);
    try {
      if (mode === 'login') {
        const { error } = await supabase.auth.signInWithPassword({ email: mail, password });
        if (error) throw error;
        router.replace('/accueil');
      } else {
        const { data, error } = await supabase.auth.signUp({
          email: mail,
          password,
          // Pour l'e-mail de confirmation : texte particulier ou commerçant, dans la langue choisie
          options: { data: { espace: espace ?? 'particulier', lang: getLang() }, emailRedirectTo: 'https://soukideals.com/compte-confirme.html' },
        });
        if (error) throw error;
        if (data.session) router.replace('/profil');
        else setInfo(t("Compte créé. Ouvrez l'e-mail de confirmation, puis connectez-vous."));
      }
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setLoading(false);
    }
  }

  async function social(provider: 'google' | 'apple') {
    setError('');
    setInfo('');
    setLoading(true);
    try {
      const ok = provider === 'google' ? await signInWithGoogle() : await signInWithApple();
      if (ok) router.replace('/accueil');
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setLoading(false);
    }
  }

  const header = (
    <>
      <LanguagePicker />
      <Image source={require('../assets/icon.png')} style={{ width: 84, height: 84, borderRadius: 20, marginBottom: 12 }} />
      <Text style={{ fontSize: 38, fontWeight: '900', color: colors.prune }}>
        Souki <Text style={{ color: colors.saffronDark }}>Deals</Text>
      </Text>
      <Text style={{ fontSize: 17, fontWeight: '600', color: colors.prune, marginBottom: 24 }}>
        {t('Le halal au meilleur prix, près de chez vous')}
      </Text>
    </>
  );

  if (!ready) return <ActivityIndicator style={{ marginTop: 60 }} color={colors.prune} />;

  // Étape 1 : choisir son espace
  if (!espace) {
    return (
      <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 20, paddingTop: 32 }}>
        {header}
        <Text style={{ fontSize: 20, fontWeight: '800', color: colors.text, marginBottom: 12 }}>{t('Vous êtes :')}</Text>
        <ChoiceCard
          title={t('Particulier')}
          subtitle={t('Je cherche les meilleures remises halal près de chez moi.')}
          onPress={() => choose('particulier')}
          strong
        />
        <ChoiceCard
          title={t('Commerçant')}
          subtitle={t('Je veux inscrire mon commerce et attirer de nouveaux clients.')}
          onPress={() => choose('commercant')}
        />
      </ScrollView>
    );
  }

  // Étape 2 : e-mail et mot de passe
  const pro = espace === 'commercant';
  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 20, paddingTop: 32 }} keyboardShouldPersistTaps="handled">
        {header}
        <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
          <Text
            style={{
              backgroundColor: pro ? colors.saffron : colors.pruneSoft,
              color: colors.prune,
              fontWeight: '800',
              paddingHorizontal: 12,
              paddingVertical: 6,
              borderRadius: 99,
              overflow: 'hidden',
            }}
          >
            {pro ? t('Espace commerçant') : t('Espace particulier')}
          </Text>
          <Pressable onPress={() => choose(null)} accessibilityRole="button" style={{ paddingVertical: 6, paddingHorizontal: 4 }}>
            <Text style={{ color: colors.prune, fontWeight: '700', textDecorationLine: 'underline' }}>{t('Changer')}</Text>
          </Pressable>
        </View>
        <Pressable
          onPress={() => social('google')}
          disabled={loading}
          accessibilityRole="button"
          style={({ pressed }) => [
            styles.card,
            { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', paddingVertical: 14, opacity: pressed || loading ? 0.7 : 1 },
          ]}
        >
          <Text style={{ fontSize: 20, fontWeight: '900', color: '#4285F4', marginRight: 10 }}>G</Text>
          <Text style={{ fontSize: 16, fontWeight: '700', color: colors.text }}>{t('Continuer avec Google')}</Text>
        </Pressable>
        {apple ? (
          <Pressable
            onPress={() => social('apple')}
            disabled={loading}
            accessibilityRole="button"
            style={({ pressed }) => [
              styles.card,
              { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', paddingVertical: 14, backgroundColor: '#000', borderColor: '#000', opacity: pressed || loading ? 0.7 : 1 },
            ]}
          >
            <Text style={{ fontSize: 16, fontWeight: '700', color: '#fff' }}>{`\uF8FF  ${t('Continuer avec Apple')}`}</Text>
          </Pressable>
        ) : null}
        <View style={{ flexDirection: 'row', alignItems: 'center', marginVertical: 12 }}>
          <View style={{ flex: 1, height: 1, backgroundColor: colors.border }} />
          <Text style={{ marginHorizontal: 10, color: colors.muted }}>{t('ou avec votre e-mail')}</Text>
          <View style={{ flex: 1, height: 1, backgroundColor: colors.border }} />
        </View>
        <Field label={t('E-mail')} value={email} onChangeText={setEmail} autoCapitalize="none" autoComplete="email" keyboardType="email-address" placeholder="exemple@gmail.com" />
        <Field
          label={t('Mot de passe')}
          value={password}
          onChangeText={setPassword}
          secureTextEntry
          autoComplete={mode === 'login' ? 'password' : 'new-password'}
          placeholder={t('6 caractères minimum')}
        />
        <ErrorText>{error}</ErrorText>
        <InfoText>{info}</InfoText>
        <Button title={mode === 'login' ? t('Se connecter') : t('Créer mon compte')} onPress={submit} loading={loading} />
        <Pressable
          onPress={() => {
            setMode(mode === 'login' ? 'signup' : 'login');
            setError('');
            setInfo('');
          }}
          style={{ marginTop: 20, alignItems: 'center', paddingVertical: 8 }}
          accessibilityRole="button"
        >
          <Text style={{ color: colors.prune, fontWeight: '700', fontSize: 15 }}>
            {mode === 'login' ? t('Pas encore de compte ? Créer un compte') : t('Déjà un compte ? Se connecter')}
          </Text>
        </Pressable>
        <Pressable onPress={() => router.push('/confidentialite')} accessibilityRole="link" style={{ alignItems: 'center', paddingVertical: 8 }}>
          <Text style={{ color: colors.muted, textDecorationLine: 'underline', fontSize: 13 }}>{t('Confidentialité et données personnelles')}</Text>
        </Pressable>
        <View style={{ marginTop: 20 }}>
          <Muted>
            {pro
              ? t('Après la connexion, inscrivez votre commerce : rien à payer si on ne vous amène pas de clients.')
              : t('Obtenez vos bons de réduction chez les commerces halal autour de vous.')}
          </Muted>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
