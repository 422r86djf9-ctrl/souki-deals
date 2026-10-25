// Promos des commerçants : offre flash (produit à -X %) et produit offert dès un montant
import { euros, timeLabel } from './deals';
import { t } from './i18n';

export type Promo = {
  id: number;
  shop_id: string;
  shop_name?: string;
  kind: 'flash' | 'gift';
  title: string;
  discount_pct: number | null;
  min_cents: number | null;
  ends_at: string;
  distance_km?: number | null;
  active?: boolean;
};

export function promoLabel(p: Promo): string {
  if (p.kind === 'flash') return t('{title} : -{pct} %', { title: p.title, pct: String(p.discount_pct ?? 0).replace('.', ',') });
  return t('{title} offert dès {min}', { title: p.title, min: euros(p.min_cents ?? 0) });
}

// « Jusqu'à ce soir » ou « jusqu'au 15/10 »
export function promoUntil(p: Promo): string {
  const end = new Date(p.ends_at);
  const now = new Date();
  const lastMinute = new Date(end.getTime() - 60000);
  if (lastMinute.toDateString() === now.toDateString()) return t('jusqu’à ce soir');
  if (end.getTime() - now.getTime() < 3600000) return t('jusqu’à {time}', { time: timeLabel(p.ends_at) });
  return t('jusqu’au {date}', {
    date: `${String(lastMinute.getDate()).padStart(2, '0')}/${String(lastMinute.getMonth() + 1).padStart(2, '0')}`,
  });
}

// Offre choisie par le client avant d'entrer dans le magasin (gardée le temps de la visite)
let chosen: Promo | null = null;
export const getChosenPromo = () => chosen;
export function setChosenPromo(p: Promo | null) {
  chosen = p;
}
