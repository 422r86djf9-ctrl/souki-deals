// Précommande : le téléphone vérifie s'il est arrivé au commerce (moins de 150 m) pour activer la visite
import * as Location from 'expo-location';
import { errorMessage, supabase } from './supabase';

export type ArriveResult = { ok: true } | { ok: false; message: string; far?: boolean };

export async function tryArrive(checkinId: string, ask = true): Promise<ArriveResult> {
  try {
    const perm = ask ? await Location.requestForegroundPermissionsAsync() : await Location.getForegroundPermissionsAsync();
    if (!perm.granted) return { ok: false, message: 'NO_PERMISSION' };
    const p = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High });
    const { error } = await supabase.rpc('client_arrive', {
      p_id: checkinId,
      p_lat: p.coords.latitude,
      p_lng: p.coords.longitude,
      p_accuracy: p.coords.accuracy ?? null,
    });
    if (error) {
      const far = (error as { hint?: string }).hint === 'TOO_FAR';
      return { ok: false, message: errorMessage(error), far };
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, message: errorMessage(e) };
  }
}
