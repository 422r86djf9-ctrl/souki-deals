// Espace choisi avant la connexion : particulier ou commerçant.
// Le particulier ne voit pas les conditions des commerçants.
import AsyncStorage from '@react-native-async-storage/async-storage';

export type Espace = 'particulier' | 'commercant';

const KEY = 'soukideals.espace';

export async function getEspace(): Promise<Espace | null> {
  try {
    const v = await AsyncStorage.getItem(KEY);
    return v === 'particulier' || v === 'commercant' ? v : null;
  } catch {
    return null;
  }
}

export async function setEspace(e: Espace | null): Promise<void> {
  try {
    if (e) await AsyncStorage.setItem(KEY, e);
    else await AsyncStorage.removeItem(KEY);
  } catch {
    // sans stockage, on redemandera simplement le choix
  }
}
