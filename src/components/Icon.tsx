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
} as const;

export type IconName = keyof typeof NAMES;

export function Icon({ name, color, size = 22 }: { name: IconName; color: string; size?: number }) {
  return <Ionicons name={NAMES[name]} size={size} color={color} />;
}
