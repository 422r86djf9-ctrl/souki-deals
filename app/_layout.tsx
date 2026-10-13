import * as Notifications from 'expo-notifications';
import { router, Stack } from 'expo-router';
import { useEffect } from 'react';
import { StatusBar } from 'expo-status-bar';
import { AuthProvider } from '../src/lib/auth';
import { LanguageProvider, t } from '../src/lib/i18n';
import { colors } from '../src/lib/theme';

// Toucher une notification ouvre le bon écran
function useNotificationLinks() {
  const last = Notifications.useLastNotificationResponse();
  useEffect(() => {
    const url = last?.notification.request.content.data?.url;
    if (typeof url === 'string' && url.startsWith('/')) setTimeout(() => router.push(url as never), 300);
  }, [last]);
}

export default function RootLayout() {
  useNotificationLinks();
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
