// Retour de la connexion Google : la session est ouverte par src/lib/social.ts, on repart vers l'accueil
import { Redirect } from 'expo-router';

export default function AuthRetour() {
  return <Redirect href="/" />;
}
