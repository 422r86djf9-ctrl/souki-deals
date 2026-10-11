// Couleurs et composants de base de Souki Deals : prune et safran
import { ReactNode } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, TextInput, TextInputProps, View } from 'react-native';

export const colors = {
  prune: '#4A1650',
  pruneSoft: '#F2E7F3',
  saffron: '#F4A300',
  saffronDark: '#8A5A00', // safran lisible sur fond clair
  saffronSoft: '#FFF1D6',
  text: '#2A1630',
  muted: '#6E5D68',
  border: '#E6DCE2',
  background: '#FBF8F3',
  card: '#FFFFFF',
  danger: '#B3261E',
  success: '#1E7B4A',
};

export function Title({ children }: { children: ReactNode }) {
  return <Text style={styles.title}>{children}</Text>;
}

export function Muted({ children }: { children: ReactNode }) {
  return <Text style={styles.muted}>{children}</Text>;
}

export function Field(props: TextInputProps & { label: string }) {
  const { label, style, ...rest } = props;
  return (
    <View style={{ marginBottom: 14 }}>
      <Text style={styles.label}>{label}</Text>
      <TextInput placeholderTextColor={colors.muted} style={[styles.input, style]} {...rest} />
    </View>
  );
}

export function Button({
  title,
  onPress,
  loading,
  variant = 'primary',
  disabled,
}: {
  title: string;
  onPress: () => void;
  loading?: boolean;
  variant?: 'primary' | 'secondary' | 'accent';
  disabled?: boolean;
}) {
  const bg = variant === 'primary' ? colors.prune : variant === 'accent' ? colors.saffron : colors.card;
  const fg = variant === 'primary' ? '#FFFFFF' : colors.prune;
  return (
    <Pressable
      onPress={onPress}
      disabled={loading || disabled}
      accessibilityRole="button"
      style={({ pressed }) => [
        styles.button,
        { backgroundColor: bg },
        variant === 'secondary' && { borderWidth: 1, borderColor: colors.border },
        (pressed || disabled) && { opacity: 0.7 },
      ]}
    >
      {loading ? <ActivityIndicator color={fg} /> : <Text style={[styles.buttonText, { color: fg }]}>{title}</Text>}
    </Pressable>
  );
}

// Pastille sélectionnable (filtres)
export function Chip({ label, selected, onPress }: { label: string; selected: boolean; onPress: () => void }) {
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityState={{ selected }}
      style={{
        paddingHorizontal: 14,
        paddingVertical: 9,
        borderRadius: 99,
        borderWidth: 1,
        borderColor: selected ? colors.prune : colors.border,
        backgroundColor: selected ? colors.pruneSoft : colors.card,
        marginRight: 8,
        marginBottom: 8,
      }}
    >
      <Text style={{ color: selected ? colors.prune : colors.text, fontWeight: selected ? '700' : '500' }}>{label}</Text>
    </Pressable>
  );
}

// Étiquette de remise « -10 % »
export function DiscountTag({ pct, big }: { pct: number; big?: boolean }) {
  return (
    <View
      style={{
        backgroundColor: colors.saffron,
        borderRadius: 8,
        paddingHorizontal: big ? 12 : 8,
        paddingVertical: big ? 6 : 3,
        alignSelf: 'flex-start',
      }}
    >
      <Text style={{ color: colors.prune, fontWeight: '900', fontSize: big ? 18 : 13 }}>{`-${Number(pct).toLocaleString('fr-FR')} %`}</Text>
    </View>
  );
}

export function SectionTitle({ children }: { children: ReactNode }) {
  return <Text style={{ fontSize: 17, fontWeight: '800', color: colors.text, marginTop: 18, marginBottom: 10 }}>{children}</Text>;
}

export function ErrorText({ children }: { children: ReactNode }) {
  if (!children) return null;
  return <Text style={styles.error}>{children}</Text>;
}

export function InfoText({ children }: { children: ReactNode }) {
  if (!children) return null;
  return <Text style={{ color: colors.success, fontWeight: '600', marginVertical: 8 }}>{children}</Text>;
}

export const styles = StyleSheet.create({
  title: { fontSize: 24, fontWeight: '800', color: colors.text, marginBottom: 8 },
  muted: { fontSize: 15, color: colors.muted, lineHeight: 21 },
  label: { fontSize: 14, fontWeight: '600', color: colors.text, marginBottom: 6 },
  input: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
    color: colors.text,
  },
  button: { borderRadius: 14, paddingVertical: 15, alignItems: 'center', marginTop: 8 },
  buttonText: { fontSize: 16, fontWeight: '700' },
  error: { color: colors.danger, fontSize: 14, marginVertical: 8 },
  card: {
    backgroundColor: colors.card,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: colors.border,
    padding: 16,
    marginBottom: 12,
  },
});
