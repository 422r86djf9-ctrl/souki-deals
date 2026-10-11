// Connexion par e-mail et mot de passe
import { router } from 'expo-router';
import { useState } from 'react';
import { Image, KeyboardAvoidingView, Platform, Pressable, ScrollView, Text, View } from 'react-native';
import { LanguagePicker } from '../src/components/LanguagePicker';
import { t } from '../src/lib/i18n';
import { errorMessage, supabase } from '../src/lib/supabase';
import { Button, colors, ErrorText, Field, InfoText, Muted } from '../src/lib/theme';

export default function Connexion() {
  const [mode, setMode] = useState<'login' | 'signup'>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');

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
        const { data, error } = await supabase.auth.signUp({ email: mail, password });
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

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 20, paddingTop: 32 }} keyboardShouldPersistTaps="handled">
        <LanguagePicker />
        <Image source={require('../assets/icon.png')} style={{ width: 84, height: 84, borderRadius: 20, marginBottom: 12 }} />
        <Text style={{ fontSize: 38, fontWeight: '900', color: colors.prune }}>
          Souki <Text style={{ color: colors.saffronDark }}>Deals</Text>
        </Text>
        <Text style={{ fontSize: 17, fontWeight: '600', color: colors.prune, marginBottom: 24 }}>
          {t('Le halal au meilleur prix, près de chez vous')}
        </Text>
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
        <View style={{ marginTop: 28 }}>
          <Muted>{t('Un seul compte suffit : obtenez vos bons de réduction, ou inscrivez votre commerce.')}</Muted>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
