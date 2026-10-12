// Types et petits outils de Souki Deals
import * as Location from 'expo-location';
import { Linking, Platform } from 'react-native';
import { t } from './i18n';

export type Kind = 'restaurant' | 'boucherie' | 'boulangerie' | 'supermarche' | 'epicerie' | 'primeur' | 'poissonnerie';
export const KINDS: Kind[] = ['boucherie', 'restaurant', 'boulangerie', 'supermarche', 'epicerie', 'primeur', 'poissonnerie'];

export function kindLabel(k: Kind | string): string {
  switch (k) {
    case 'restaurant':
      return t('Restaurant');
    case 'boucherie':
      return t('Boucherie');
    case 'boulangerie':
      return t('Boulangerie');
    case 'supermarche':
      return t('Supermarché');
    case 'epicerie':
      return t('Épicerie, market');
    case 'primeur':
      return t('Fruits et légumes');
    case 'poissonnerie':
      return t('Poissonnerie');
    default:
      return String(k);
  }
}

export type Zone = { id: number; name: string; name_en: string | null; name_ar: string | null; open: boolean; sort: number };

export type NearbyShop = {
  id: string;
  name: string;
  kind: Kind;
  address: string;
  lat: number;
  lng: number;
  discount_pct: number;
  best_discount: number;
  distance_km: number | null;
  halal_cert: string | null;
  hours: string | null;
  zone_id: number;
  products_count: number;
};

export type Product = {
  id: number;
  shop_id: string;
  name: string;
  category: string | null;
  unit: 'piece' | 'kg';
  price_cents: number;
  discount_pct: number | null;
  in_stock: boolean;
  active: boolean;
};

// 1900 -> « 19,00 € »
export function euros(cents: number): string {
  return `${(Math.round(cents) / 100).toFixed(2).replace('.', ',')} €`;
}

// « 19,5 » ou « 19.50 » -> 1950 ; null si invalide
export function parseEuros(text: string): number | null {
  const clean = text.replace(/\s|€/g, '').replace(',', '.');
  if (!/^\d+(\.\d{1,2})?$/.test(clean)) return null;
  const cents = Math.round(Number(clean) * 100);
  return cents > 0 ? cents : null;
}

export function finalCents(priceCents: number, pct: number): number {
  return Math.round(priceCents * (1 - pct / 100));
}

export function unitLabel(u: 'piece' | 'kg'): string {
  return u === 'kg' ? t('le kg') : t("l'unité");
}

export function distanceLabel(km: number | null): string {
  if (km == null) return '';
  return km < 1 ? t('{m} m', { m: Math.round(km * 1000) }) : t('{km} km', { km: km.toFixed(1).replace('.', ',') });
}

// Position actuelle du téléphone (null si refus ou indisponible)
export async function currentPosition(): Promise<{ lat: number; lng: number } | null> {
  try {
    const { granted } = await Location.requestForegroundPermissionsAsync();
    if (!granted) return null;
    const p = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
    return { lat: p.coords.latitude, lng: p.coords.longitude };
  } catch {
    return null;
  }
}

export function openDirections(lat: number, lng: number) {
  const url =
    Platform.OS === 'ios'
      ? `https://maps.apple.com/?daddr=${lat},${lng}`
      : `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`;
  Linking.openURL(url);
}

// Code du bon dans un QR code scanné (« SOUKIDEALS:ABCD2345 » ou le code seul)
export function codeFromScan(data: string): string | null {
  const m = data.toUpperCase().match(/([A-Z2-9]{8})\s*$/);
  return m ? m[1] : null;
}

export function shortDate(iso: string): string {
  const d = new Date(iso);
  return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`;
}

export function timeLabel(iso: string): string {
  const d = new Date(iso);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

// Factures des commissions
export type Invoice = {
  id: string;
  number: string;
  charge_id?: string | null;
  issued_at: string;
  period_start: string;
  period_end: string;
  amount_ttc_cents: number;
  email_to: string | null;
  email_status: 'pending' | 'sent' | 'failed';
  email_error?: string | null;
  pdf_path: string | null;
  buyer?: { name?: string | null } | null;
};

export function invoiceEmailLabel(i: Invoice): string {
  if (i.email_status === 'sent') return t('Envoyée à {email}', { email: i.email_to ?? '' });
  if (i.email_status === 'failed') return t('Envoi par e-mail impossible');
  return t('Envoi par e-mail en cours');
}

export function fullDate(iso: string): string {
  const d = /^\d{4}-\d{2}-\d{2}$/.test(iso) ? new Date(`${iso}T12:00:00`) : new Date(iso);
  return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`;
}
