// Notifications : autorisation, jeton du téléphone, ouverture du bon écran
import Constants from 'expo-constants';
import * as Device from 'expo-device';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';
import { supabase } from './supabase';

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: true,
    shouldSetBadge: false,
  }),
});

let currentToken: string | null = null;

// Ne lève jamais d'erreur : sans notifications, l'appli continue de marcher
export async function registerForPush(): Promise<void> {
  try {
    if (!Device.isDevice) return;
    if (Platform.OS === 'android') {
      await Notifications.setNotificationChannelAsync('default', {
        name: 'Souki Deals',
        importance: Notifications.AndroidImportance.HIGH,
        vibrationPattern: [0, 250, 250, 250],
        lightColor: '#FF7A1A',
      });
    }
    const current = await Notifications.getPermissionsAsync();
    let granted = current.granted;
    if (!granted && current.canAskAgain) granted = (await Notifications.requestPermissionsAsync()).granted;
    if (!granted) return;
    const projectId =
      (Constants.expoConfig?.extra as { eas?: { projectId?: string } } | undefined)?.eas?.projectId ?? Constants.easConfig?.projectId;
    const { data: token } = await Notifications.getExpoPushTokenAsync({ projectId });
    const { error } = await supabase.rpc('register_push_token', { p_token: token });
    if (!error) currentToken = token;
  } catch {
    // ex. Firebase pas encore configuré : on ignore
  }
}

export async function unregisterPush(): Promise<void> {
  try {
    if (currentToken) await supabase.rpc('unregister_push_token', { p_token: currentToken });
  } catch {
    // ignore
  }
  currentToken = null;
}

// Zone approximative du client (pour les offres flash proches), seulement si la position est déjà autorisée
export async function updateMyArea(): Promise<void> {
  try {
    const perm = await Location.getForegroundPermissionsAsync();
    if (!perm.granted) return;
    const pos = (await Location.getLastKnownPositionAsync()) ?? (await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Low }));
    if (pos) await supabase.rpc('set_my_area', { p_lat: pos.coords.latitude, p_lng: pos.coords.longitude });
  } catch {
    // ignore
  }
}
