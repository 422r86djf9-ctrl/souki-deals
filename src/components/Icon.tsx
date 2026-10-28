// Icônes de l'appli (Ionicons, fournies avec Expo)
import { Ionicons } from '@expo/vector-icons';

const NAMES = {
  home: 'home-outline',
  pin: 'location-outline',
  ticket: 'ticket-outline',
  user: 'person-outline',
  search: 'search-outline',
  chat: 'chatbubble-ellipses-outline',
  scan: 'scan-outline',
  back: 'chevron-back',
  navigate: 'navigate-outline',
  call: 'call-outline',
  tag: 'pricetag-outline',
  flash: 'flash-outline',
  time: 'time-outline',
  shield: 'shield-checkmark-outline',
  flag: 'flag-outline',
  qr: 'qr-code-outline',
  bag: 'bag-handle-outline',
  store: 'storefront-outline',
  doc: 'document-text-outline',
} as const;

export type IconName = keyof typeof NAMES;

export function Icon({ name, color, size = 22 }: { name: IconName; color: string; size?: number }) {
  return <Ionicons name={NAMES[name]} size={size} color={color} />;
}
