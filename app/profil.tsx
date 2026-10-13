import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, ScrollView, Switch, Text, View } from 'react-native';
import { LanguagePicker } from '../src/components/LanguagePicker';
import { useAuth } from '../src/lib/auth';
import { unregisterPush } from '../src/lib/push';
import { t } from '../src/lib/i18n';
import { errorMessage, PHONE_RE, supabase } from '../src/lib/supabase';
import { Button, colors, ErrorText, Field, Muted, SectionTitle, Title } from '../src/lib/theme';

export default function Profil() {
  const { session } = useAuth();
  const [fullName, setFullName] = useState('');
  const [phone, setPhone] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [promos, setPromos] = useState(true);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    if (!session) return;
    supabase
      .from('profiles')
      .select('full_name, phone, notif_promos')
      .eq('id', session.user.id)
      .maybeSingle()
      .then(({ data }) => {
        // Connexion Google ou Apple : le nom est déjà connu
        const meta = (session.user.user_metadata ?? {}) as { full_name?: string; name?: string };
        setFullName(data?.full_name ?? meta.full_name ?? meta.name ?? '');
        setPhone(data?.phone ?? '');
        setPromos((data as { notif_promos?: boolean } | null)?.notif_promos ?? true);
        setLoading(false);
      });
  }, [session]);

  async function save() {
    setError('');
    const name = fullName.trim();
    const tel = phone.trim();
    if (name.length < 2) return setError(t('Indiquez votre nom.'));
    if (tel && !PHONE_RE.test(tel)) return setError(t('Numéro de téléphone invalide.'));
    if (!session) return;
    setSaving(true);
    const { error } = await supabase.from('profiles').upsert({ id: session.user.id, full_name: name, phone: tel || null });
    setSaving(false);
    if (error) return setError(errorMessage(error));
    router.replace('/accueil');
  }

  async function togglePromos(v: boolean) {
    setPromos(v);
    await supabase.rpc('set_my_notif_promos', { p_on: v });
  }

  function askDelete() {
    Alert.alert(
      t('Supprimer votre compte ?'),
      t('Vos informations, vos bons en cours et vos préférences seront effacés. Vos achats passés restent chez les commerçants, sans votre nom. C’est définitif.'),
      [
        { text: t('Annuler'), style: 'cancel' },
        {
          text: t('Supprimer'),
          style: 'destructive',
          onPress: async () => {
            setDeleting(true);
            setError('');
            await unregisterPush();
            const { error } = await supabase.rpc('delete_my_account');
            setDeleting(false);
            if (error) return setError(errorMessage(error));
            await supabase.auth.signOut();
            Alert.alert(t('Compte supprimé'), t('Merci d’avoir utilisé Souki Deals.'));
            router.replace('/connexion');
          },
        },
      ],
    );
  }

  if (loading) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;

  return (
    <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 20 }} keyboardShouldPersistTaps="handled">
      <SectionTitle>{t('Langue')}</SectionTitle>
      <LanguagePicker />
      <View style={{ height: 8 }} />
      <Title>{t('Vos informations')}</Title>
      <Muted>{t('Votre prénom apparaît sur vos bons de réduction.')}</Muted>
      <View style={{ height: 20 }} />
      <Field label={t('Nom et prénom')} value={fullName} onChangeText={setFullName} placeholder="Karim Benali" />
      <Field label={t('Téléphone (facultatif)')} value={phone} onChangeText={setPhone} keyboardType="phone-pad" placeholder="06 12 34 56 78" />
      <ErrorText>{error}</ErrorText>
      <Button title={t('Enregistrer')} onPress={save} loading={saving} />

      <SectionTitle>{t('Notifications')}</SectionTitle>
      <View style={{ flexDirection: 'row', alignItems: 'center', marginBottom: 8 }}>
        <Text style={{ flex: 1, color: colors.text }}>{t('Me prévenir des offres flash près de chez moi (une par jour au plus)')}</Text>
        <Switch value={promos} onValueChange={togglePromos} trackColor={{ true: colors.prune, false: colors.border }} thumbColor="#FFFFFF" />
      </View>

      <SectionTitle>{t('Mon compte')}</SectionTitle>
      <Pressable onPress={() => router.push('/confidentialite')} accessibilityRole="link" style={{ paddingVertical: 10 }}>
        <Text style={{ color: colors.prune, fontWeight: '700' }}>{t('Confidentialité et données personnelles')}</Text>
      </Pressable>
      <Pressable onPress={askDelete} disabled={deleting} accessibilityRole="button" style={{ paddingVertical: 10 }}>
        <Text style={{ color: colors.danger, fontWeight: '700' }}>{deleting ? t('Suppression…') : t('Supprimer mon compte')}</Text>
      </Pressable>
    </ScrollView>
  );
}
