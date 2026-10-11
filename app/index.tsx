import { Redirect } from 'expo-router';
import { ActivityIndicator, View } from 'react-native';
import { useAuth } from '../src/lib/auth';
import { colors } from '../src/lib/theme';

export default function Index() {
  const { session, loading } = useAuth();
  if (loading) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background }}>
        <ActivityIndicator color={colors.prune} size="large" />
      </View>
    );
  }
  return <Redirect href={session ? '/accueil' : '/connexion'} />;
}
