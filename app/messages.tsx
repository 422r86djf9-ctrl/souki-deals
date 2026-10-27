import { Stack, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, KeyboardAvoidingView, Platform, Pressable, ScrollView, Text, TextInput, View } from 'react-native';
import { fullDate } from '../src/lib/deals';
import { t } from '../src/lib/i18n';
import { errorMessage, supabase } from '../src/lib/supabase';
import { colors, ErrorText, Muted } from '../src/lib/theme';

type Message = { id: number; user_id: string; from_admin: boolean; body: string; created_at: string; read_at: string | null };
type Person = { id: string; email: string | null; full_name: string | null; phone: string | null; shop_name: string | null; kind: 'particulier' | 'commercant' };

function when(iso: string): string {
  const d = new Date(iso);
  const h = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
  return new Date().toDateString() === d.toDateString() ? h : `${fullDate(iso)} ${h}`;
}

// Conversation avec le fondateur. Sans paramètre : l'inscrit écrit au fondateur.
// Avec ?user=… : le fondateur lit et répond à cet inscrit.
export default function Messages() {
  const { user } = useLocalSearchParams<{ user?: string }>();
  const asAdmin = typeof user === 'string' && user.length > 0;
  const [messages, setMessages] = useState<Message[]>([]);
  const [person, setPerson] = useState<Person | null>(null);
  const [text, setText] = useState('');
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const scroll = useRef<ScrollView>(null);

  const load = useCallback(async () => {
    if (asAdmin) {
      const { data, error } = await supabase.rpc('admin_support_thread', { p_user: user });
      if (error) setError(errorMessage(error));
      else {
        setPerson((data?.user ?? null) as Person | null);
        setMessages((data?.messages ?? []) as Message[]);
      }
    } else {
      const { data, error } = await supabase.rpc('support_my_thread');
      if (error) setError(errorMessage(error));
      else setMessages((data ?? []) as Message[]);
    }
    setLoading(false);
  }, [asAdmin, user]);

  useEffect(() => {
    load();
    const id = setInterval(load, 15000);
    return () => clearInterval(id);
  }, [load]);

  async function send() {
    const body = text.trim();
    if (!body || sending) return;
    setSending(true);
    setError('');
    const { data, error } = asAdmin
      ? await supabase.rpc('admin_support_reply', { p_user: user, p_body: body })
      : await supabase.rpc('support_send', { p_body: body });
    setSending(false);
    if (error) return setError(errorMessage(error));
    setText('');
    setMessages((m) => [...m, data as Message]);
  }

  const title = asAdmin
    ? (person?.kind === 'commercant' && person.shop_name) || person?.full_name || person?.email || t('Conversation')
    : t('Écrire au fondateur');

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: colors.background }} behavior={Platform.OS === 'ios' ? 'padding' : undefined} keyboardVerticalOffset={90}>
      <Stack.Screen options={{ title }} />
      <ScrollView
        ref={scroll}
        contentContainerStyle={{ padding: 16, paddingBottom: 8 }}
        onContentSizeChange={() => scroll.current?.scrollToEnd({ animated: false })}
        keyboardShouldPersistTaps="handled"
      >
        {asAdmin && person ? (
          <View style={{ marginBottom: 12 }}>
            <Muted>
              {[person.kind === 'commercant' ? t('Commerçant') : t('Particulier'), person.full_name, person.email, person.phone].filter(Boolean).join(' · ')}
            </Muted>
          </View>
        ) : null}
        {!asAdmin ? (
          <View style={{ backgroundColor: '#E5F4EA', borderRadius: 14, padding: 14, marginBottom: 14 }}>
            <Text style={{ color: colors.text, fontWeight: '700' }}>{t('Une question, une idée, un souci ?')}</Text>
            <Text style={{ color: colors.text, marginTop: 4 }}>
              {t('Écrivez-moi directement : je lis chaque message et je vous réponds ici. Vous recevez une notification dès que je réponds. Demba, fondateur de Souki Deals')}
            </Text>
          </View>
        ) : null}
        {loading ? <ActivityIndicator style={{ marginTop: 30 }} color={colors.prune} /> : null}
        {!loading && messages.length === 0 && asAdmin ? <Muted>{t('Aucun message.')}</Muted> : null}
        {messages.map((m) => {
          const mine = asAdmin ? m.from_admin : !m.from_admin;
          return (
            <View key={m.id} style={{ alignItems: mine ? 'flex-end' : 'flex-start', marginVertical: 4 }}>
              <View
                style={{
                  maxWidth: '82%',
                  backgroundColor: mine ? colors.prune : '#FFFFFF',
                  borderColor: mine ? colors.prune : colors.border,
                  borderWidth: 1,
                  borderRadius: 16,
                  borderBottomRightRadius: mine ? 4 : 16,
                  borderBottomLeftRadius: mine ? 16 : 4,
                  paddingHorizontal: 12,
                  paddingVertical: 8,
                }}
              >
                {!mine && !asAdmin ? <Text style={{ color: colors.prune, fontWeight: '800', fontSize: 12, marginBottom: 2 }}>Demba · Souki Deals</Text> : null}
                <Text style={{ color: mine ? '#FFFFFF' : colors.text, fontSize: 15 }} selectable>
                  {m.body}
                </Text>
              </View>
              <Text style={{ color: colors.muted, fontSize: 11, marginTop: 2 }}>
                {when(m.created_at)}
                {mine && m.read_at ? ` · ${t('Lu')}` : ''}
              </Text>
            </View>
          );
        })}
      </ScrollView>
      <View style={{ paddingHorizontal: 12, paddingTop: 4 }}>
        <ErrorText>{error}</ErrorText>
      </View>
      <View style={{ flexDirection: 'row', alignItems: 'flex-end', padding: 12, gap: 8, borderTopWidth: 1, borderTopColor: colors.border, backgroundColor: '#FFFFFF' }}>
        <TextInput
          value={text}
          onChangeText={setText}
          placeholder={t('Votre message…')}
          placeholderTextColor={colors.muted}
          multiline
          maxLength={2000}
          style={{
            flex: 1,
            minHeight: 44,
            maxHeight: 130,
            borderWidth: 1,
            borderColor: colors.border,
            borderRadius: 22,
            paddingHorizontal: 14,
            paddingTop: 11,
            paddingBottom: 11,
            fontSize: 15,
            color: colors.text,
            backgroundColor: colors.background,
          }}
        />
        <Pressable
          onPress={send}
          disabled={sending || !text.trim()}
          accessibilityRole="button"
          accessibilityLabel={t('Envoyer')}
          style={({ pressed }) => ({
            height: 44,
            paddingHorizontal: 16,
            borderRadius: 22,
            justifyContent: 'center',
            backgroundColor: sending || !text.trim() ? colors.border : colors.prune,
            opacity: pressed ? 0.85 : 1,
          })}
        >
          {sending ? <ActivityIndicator color="#fff" /> : <Text style={{ color: '#fff', fontWeight: '800' }}>{t('Envoyer')}</Text>}
        </Pressable>
      </View>
    </KeyboardAvoidingView>
  );
}
