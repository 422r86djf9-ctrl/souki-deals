import 'react-native-url-polyfill/auto';
import AsyncStorage from '@react-native-async-storage/async-storage';
import Constants from 'expo-constants';
import { AppState } from 'react-native';
import { createClient } from '@supabase/supabase-js';
import { t, translateServerMessage } from './i18n';

const extra = (Constants.expoConfig?.extra ?? {}) as {
  supabaseUrl?: string;
  supabasePublishableKey?: string;
};

if (!extra.supabaseUrl?.startsWith('https://') || !extra.supabasePublishableKey || extra.supabasePublishableKey === 'A_REMPLIR') {
  throw new Error('Configuration Supabase manquante dans app.json (extra).');
}

export const supabase = createClient(extra.supabaseUrl, extra.supabasePublishableKey, {
  auth: {
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
});

// Rafraîchit la session seulement quand l'application est ouverte
AppState.addEventListener('change', (state) => {
  if (state === 'active') supabase.auth.startAutoRefresh();
  else supabase.auth.stopAutoRefresh();
});

// Ce que renvoie la fonction serveur whoami()
export type Whoami = {
  user_id: string | null;
  email?: string | null;
  is_admin: boolean;
  profile?: { full_name: string | null; phone: string | null; lang?: string | null } | null;
  shop?: { id: string; name: string; status: 'pending' | 'active' | 'suspended'; launch_offer: boolean; free_until: string | null; blocked: boolean } | null;
  pending_purchases?: number;
  visits_to_answer?: number;
};

export async function whoami(): Promise<Whoami> {
  const { data, error } = await supabase.rpc('whoami');
  if (error) throw error;
  return data as Whoami;
}

// Message d'erreur lisible, dans la langue choisie (les erreurs du serveur arrivent en français)
export function errorMessage(e: unknown): string {
  const err = e as { message?: string } | null;
  const msg = err?.message ?? '';
  if (/Invalid login credentials/i.test(msg)) return t('E-mail ou mot de passe incorrect.');
  if (/User already registered/i.test(msg)) return t('Un compte existe déjà avec cet e-mail.');
  if (/Password should be at least/i.test(msg)) return t('Le mot de passe doit faire au moins 6 caractères.');
  if (/Email not confirmed/i.test(msg)) return t("Confirmez d'abord votre e-mail.");
  if (/Network request failed|fetch/i.test(msg)) return t('Pas de connexion internet.');
  return msg ? translateServerMessage(msg) : t('Une erreur est survenue.');
}

// Téléphone : chiffres, espaces, points, tirets, + au début
export const PHONE_RE = /^\+?[0-9 .-]{6,20}$/;
