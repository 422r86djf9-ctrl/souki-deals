import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, ScrollView, View } from 'react-native';
import { LanguagePicker } from '../src/components/LanguagePicker';
import { useAuth } from '../src/lib/auth';
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

  useEffect(() => {
    if (!session) return;
    supabase
      .from('profiles')
      .select('full_name, phone')
      .eq('id', session.user.id)
      .maybeSingle()
      .then(({ data }) => {
        setFullName(data?.full_name ?? '');
        setPhone(data?.phone ?? '');
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
    </ScrollView>
  );
}
