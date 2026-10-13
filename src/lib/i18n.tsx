// Langues : français, anglais, arabe. Textes écrits en français dans le code, traduits par t('…').
// Un texte sans traduction s'affiche en français.
import AsyncStorage from '@react-native-async-storage/async-storage';
import { createContext, ReactNode, useContext, useEffect, useState } from 'react';
import { Alert, I18nManager } from 'react-native';
import { AR } from './traductions/ar';
import { EN } from './traductions/en';

export type Lang = 'fr' | 'en' | 'ar';

export const LANGS: { code: Lang; label: string }[] = [
  { code: 'fr', label: 'Français' },
  { code: 'en', label: 'English' },
  { code: 'ar', label: 'العربية' },
];

const STORAGE_KEY = 'soukideals.lang';
let current: Lang = 'fr';

export const getLang = () => current;
export const isRTLLang = (l: Lang = current) => l === 'ar';

function lookup(fr: string): string {
  if (current === 'en') return EN[fr] ?? fr;
  if (current === 'ar') return AR[fr] ?? fr;
  return fr;
}

function fill(s: string, params?: Record<string, string | number | null | undefined>) {
  if (!params) return s;
  return s.replace(/\{(\w+)\}/g, (m, k: string) => (params[k] != null ? String(params[k]) : m));
}

export function t(fr: string, params?: Record<string, string | number | null | undefined>): string {
  return fill(lookup(fr), params);
}

// Messages d'erreur du serveur (écrits en français), y compris ceux qui contiennent un nombre
export function translateServerMessage(msg: string): string {
  if (current === 'fr' || !msg) return msg;
  let m = msg.match(/^La remise doit être d'au moins ([\d.,]+) %\.$/);
  if (m) return t("La remise doit être d'au moins {n} %.", { n: m[1] });
  m = msg.match(/^Vous avez déjà (\d+) bons en cours : utilisez-en un ou annulez-le\.$/);
  if (m) return t('Vous avez déjà {n} bons en cours : utilisez-en un ou annulez-le.', { n: m[1] });
  m = msg.match(/^Offre flash : entre 10 % et 90 %, et plus que votre remise de ([\d.,]+) %\.$/);
  if (m) return t('Offre flash : entre 10 % et 90 %, et plus que votre remise de {n} %.', { n: m[1] });
  m = msg.match(/^Montant invalide \(maximum (\d+) €\)\.$/);
  if (m) return t('Montant invalide (maximum {n} €).', { n: m[1] });
  return t(msg);
}

type Ctx = { lang: Lang; setLang: (l: Lang) => Promise<void> };
const LangContext = createContext<Ctx | null>(null);

// Arabe : écrans de droite à gauche, effectif au prochain démarrage
function applyDirection(l: Lang): boolean {
  I18nManager.allowRTL(true);
  const rtl = isRTLLang(l);
  if (I18nManager.isRTL !== rtl) {
    I18nManager.forceRTL(rtl);
    return true;
  }
  return false;
}

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [lang, setLangState] = useState<Lang | null>(null);

  useEffect(() => {
    (async () => {
      let l: Lang = 'fr';
      try {
        const saved = await AsyncStorage.getItem(STORAGE_KEY);
        if (saved === 'fr' || saved === 'en' || saved === 'ar') l = saved;
      } catch {
        // pas de stockage : français
      }
      current = l;
      applyDirection(l);
      setLangState(l);
    })();
  }, []);

  async function setLang(l: Lang) {
    current = l;
    try {
      await AsyncStorage.setItem(STORAGE_KEY, l);
    } catch {
      // le choix ne sera pas gardé, mais l'appli continue
    }
    const restart = applyDirection(l);
    setLangState(l);
    if (restart) {
      Alert.alert(t('Langue changée'), t('Fermez complètement Souki Deals puis rouvrez-la pour mettre les écrans dans le bon sens.'));
    }
  }

  if (!lang) return null;
  return (
    <LangContext.Provider value={{ lang, setLang }} key={lang}>
      {children}
    </LangContext.Provider>
  );
}

export function useLang(): Ctx {
  const ctx = useContext(LangContext);
  if (!ctx) throw new Error('LanguageProvider manquant');
  return ctx;
}

// Nom d'une zone dans la langue choisie
export function zoneLabel(z: { name: string; name_en?: string | null; name_ar?: string | null }): string {
  if (current === 'en') return z.name_en || z.name;
  if (current === 'ar') return z.name_ar || z.name;
  return z.name;
}
