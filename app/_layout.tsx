import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { AuthProvider } from '../src/lib/auth';
import { LanguageProvider, t } from '../src/lib/i18n';
import { colors } from '../src/lib/theme';

export default function RootLayout() {
  return (
    <LanguageProvider>
      <AuthProvider>
        <StatusBar style="light" />
        <RootStack />
      </AuthProvider>
    </LanguageProvider>
  );
}

function RootStack() {
  return (
    <Stack
      screenOptions={{
        headerStyle: { backgroundColor: colors.prune },
        headerTintColor: '#fff',
        headerTitleStyle: { fontWeight: '700' },
        contentStyle: { backgroundColor: colors.background },
        headerBackTitle: t('Retour'),
      }}
    >
      <Stack.Screen name="index" options={{ headerShown: false }} />
      <Stack.Screen name="connexion" options={{ title: 'Souki Deals', headerBackVisible: false }} />
      <Stack.Screen name="accueil" options={{ title: 'Souki Deals', headerBackVisible: false }} />
      <Stack.Screen name="profil" options={{ title: t('Mon profil') }} />
    </Stack>
  );
}
