// Choix de la langue : Français, English, العربية
import { View } from 'react-native';
import { Lang, LANGS, useLang } from '../lib/i18n';
import { supabase } from '../lib/supabase';
import { Chip } from '../lib/theme';

export function LanguagePicker() {
  const { lang, setLang } = useLang();

  async function choose(l: Lang) {
    if (l === lang) return;
    // Les notifications seront envoyées dans cette langue (sans effet si non connecté)
    const { data } = await supabase.auth.getSession();
    if (data.session) await supabase.rpc('set_my_lang', { p_lang: l });
    await setLang(l);
  }

  return (
    <View style={{ flexDirection: 'row', flexWrap: 'wrap' }}>
      {LANGS.map((l) => (
        <Chip key={l.code} label={l.label} selected={lang === l.code} onPress={() => choose(l.code)} />
      ))}
    </View>
  );
}
