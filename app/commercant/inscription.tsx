// Inscrire (ou modifier) son commerce
import { Stack, router } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, KeyboardAvoidingView, Platform, Pressable, ScrollView, Switch, Text, View } from 'react-native';
import { MapPicker } from '../../src/components/MapPicker';
import { Kind, KINDS, kindLabel, Zone } from '../../src/lib/deals';
import { shareConditionsPdf } from '../../src/lib/releve';
import { t, zoneLabel } from '../../src/lib/i18n';
import { errorMessage, PHONE_RE, supabase } from '../../src/lib/supabase';
import { Button, Chip, colors, ErrorText, Field, Muted, styles } from '../../src/lib/theme';

export default function Inscription() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [shopId, setShopId] = useState<string | null>(null);
  const [zones, setZones] = useState<Zone[]>([]);
  const [minDiscount, setMinDiscount] = useState(5);
  const [commission, setCommission] = useState(5);
  const [freeMonths, setFreeMonths] = useState(3);
  const [launchSlots, setLaunchSlots] = useState(150);
  const [slotsLeft, setSlotsLeft] = useState<number | null>(null);
  const [accepted, setAccepted] = useState(false);

  const [name, setName] = useState('');
  const [kind, setKind] = useState<Kind | null>(null);
  const [zoneId, setZoneId] = useState<number | null>(null);
  const [address, setAddress] = useState('');
  const [point, setPoint] = useState<{ lat: number; lng: number } | null>(null);
  const [phone, setPhone] = useState('');
  const [siret, setSiret] = useState('');
  const [halal, setHalal] = useState('');
  const [hours, setHours] = useState('');
  const [description, setDescription] = useState('');
  const [discount, setDiscount] = useState('5');

  useEffect(() => {
    (async () => {
      try {
        const { data: u } = await supabase.auth.getUser();
        const [z, st, slots, mine] = await Promise.all([
          supabase.from('zones').select('id, name, name_en, name_ar, open, sort').order('sort'),
          supabase.from('settings').select('discount_min, commission_rate, launch_free_months, launch_slots').eq('id', 1).single(),
          supabase.rpc('launch_slots_left'),
          supabase
            .from('shops')
            .select('id, name, kind, zone_id, address, lat, lng, phone, siret, halal_cert, hours, description, discount_pct')
            .eq('owner_id', u.user?.id ?? '')
            .maybeSingle(),
        ]);
        setZones((z.data ?? []) as Zone[]);
        if (st.data) {
          setMinDiscount(Number(st.data.discount_min));
          setCommission(Number(st.data.commission_rate));
          setFreeMonths(Number(st.data.launch_free_months));
          setLaunchSlots(Number(st.data.launch_slots));
        }
        setSlotsLeft(typeof slots.data === 'number' ? slots.data : null);
        const s = mine.data;
        if (s) {
          setShopId(s.id);
          setName(s.name);
          setKind(s.kind as Kind);
          setZoneId(s.zone_id);
          setAddress(s.address);
          setPoint({ lat: s.lat, lng: s.lng });
          setPhone(s.phone ?? '');
          setSiret(s.siret ?? '');
          setHalal(s.halal_cert ?? '');
          setHours(s.hours ?? '');
          setDescription(s.description ?? '');
          setDiscount(String(s.discount_pct).replace('.', ','));
          setAccepted(true);
        } else {
          setDiscount(String(st.data?.discount_min ?? 5));
        }
      } catch (e) {
        setError(errorMessage(e));
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  async function save() {
    setError('');
    const pct = Number(discount.replace(',', '.'));
    if (name.trim().length < 2) return setError(t('Indiquez le nom du commerce.'));
    if (!kind) return setError(t('Choisissez le type de commerce.'));
    if (!zoneId) return setError(t('Choisissez le département.'));
    if (address.trim().length < 5) return setError(t("Indiquez l'adresse complète."));
    if (!point) return setError(t('Placez votre commerce sur la carte.'));
    if (phone.trim() && !PHONE_RE.test(phone.trim())) return setError(t('Numéro de téléphone invalide.'));
    if (siret.trim() && !/^[0-9]{14}$/.test(siret.replace(/\s/g, ''))) return setError(t('Le SIRET compte 14 chiffres.'));
    if (!Number.isFinite(pct) || pct < minDiscount || pct > 50) return setError(t('La remise doit être entre {min} % et 50 %.', { min: minDiscount }));
    if (!accepted) return setError(t('Acceptez les conditions pour continuer.'));
    const { data: u } = await supabase.auth.getUser();
    const row = {
      name: name.trim(),
      kind,
      zone_id: zoneId,
      address: address.trim(),
      lat: point.lat,
      lng: point.lng,
      phone: phone.trim() || null,
      siret: siret.replace(/\s/g, '') || null,
      halal_cert: halal.trim() || null,
      hours: hours.trim() || null,
      description: description.trim() || null,
      discount_pct: pct,
    };
    setSaving(true);
    const { error } = shopId
      ? await supabase.from('shops').update(row).eq('id', shopId)
      : await supabase.from('shops').insert({ ...row, owner_id: u.user?.id });
    setSaving(false);
    if (error) return setError(errorMessage(error));
    router.replace('/commercant');
  }

  if (loading) return <ActivityIndicator style={{ marginTop: 40 }} color={colors.prune} />;

  return (
    <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView style={{ backgroundColor: colors.background }} contentContainerStyle={{ padding: 16, paddingBottom: 40 }} keyboardShouldPersistTaps="handled">
        <Stack.Screen options={{ title: shopId ? t('Mes informations') : t('Inscrire mon commerce') }} />
        {!shopId ? (
          <View style={[styles.card, { backgroundColor: colors.prune, borderColor: colors.prune }]}>
            <Text style={{ color: '#fff', fontSize: 18, fontWeight: '800' }}>{t('Des clients en plus, sans rien payer d’avance')}</Text>
            <Text style={{ color: colors.pruneSoft, marginTop: 6 }}>
              {t('Vous offrez au moins {min} % de remise aux clients Souki Deals. Souki Deals touche {c} % de ce qu’ils paient chez vous, et rien si on ne vous amène personne.', {
                min: minDiscount,
                c: commission,
              })}
            </Text>
            {slotsLeft != null && slotsLeft > 0 ? (
              <Text style={{ color: colors.saffron, fontWeight: '800', marginTop: 8 }}>
                {t('Offre de lancement : {m} mois sans commission. Plus que {n} places.', { m: freeMonths, n: slotsLeft })}
              </Text>
            ) : null}
          </View>
        ) : null}

        <Field label={t('Nom du commerce')} value={name} onChangeText={setName} maxLength={60} placeholder="Boucherie Al Baraka" />
        <Text style={styles.label}>{t('Type de commerce')}</Text>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginBottom: 6 }}>
          {KINDS.map((k) => (
            <Chip key={k} label={kindLabel(k)} selected={kind === k} onPress={() => setKind(k)} />
          ))}
        </View>
        <Text style={styles.label}>{t('Département')}</Text>
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', marginBottom: 6 }}>
          {zones.map((z) => (
            <Chip key={z.id} label={zoneLabel(z)} selected={zoneId === z.id} onPress={() => setZoneId(z.id)} />
          ))}
        </View>
        <Field label={t('Adresse')} value={address} onChangeText={setAddress} maxLength={160} placeholder="12 rue de Paris, 93200 Saint-Denis" />
        <MapPicker value={point} onChange={setPoint} hint={t('Placez votre commerce sur la carte : les clients proches le verront.')} />
        <View style={{ height: 14 }} />
        <Field
          label={t('Remise pour les clients Souki Deals (%)')}
          value={discount}
          onChangeText={(v) => setDiscount(v.replace(/[^0-9.,]/g, ''))}
          keyboardType="decimal-pad"
          maxLength={5}
        />
        <Muted>{t('Minimum {min} %. Vous pouvez mettre une remise plus forte sur certains produits.', { min: minDiscount })}</Muted>
        <View style={{ height: 10 }} />
        <Field label={t('Téléphone du commerce')} value={phone} onChangeText={setPhone} keyboardType="phone-pad" placeholder="01 23 45 67 89" />
        <Field label={t('SIRET (14 chiffres)')} value={siret} onChangeText={setSiret} keyboardType="number-pad" maxLength={17} />
        <Field label={t('Organisme de certification halal (facultatif)')} value={halal} onChangeText={setHalal} maxLength={60} placeholder="AVS, Achahada…" />
        <Muted>{t('Souki Deals ne certifie pas : vous déclarez votre organisme et en êtes responsable.')}</Muted>
        <View style={{ height: 10 }} />
        <Field label={t('Horaires (facultatif)')} value={hours} onChangeText={setHours} maxLength={200} placeholder={t('Lun-Sam 8h-20h')} />
        <Field label={t('Présentation (facultatif)')} value={description} onChangeText={setDescription} maxLength={400} multiline />

        {!shopId ? (
          <Pressable
            accessibilityRole="button"
            hitSlop={8}
            onPress={() =>
              shareConditionsPdf({ discountMin: minDiscount, commission, launchSlots, launchMonths: freeMonths }).catch(() =>
                setError(t('Impossible de préparer le fichier.')),
              )
            }
          >
            <Text style={{ color: colors.prune, fontWeight: '700', marginBottom: 8 }}>{t('Lire les conditions complètes (PDF)')}</Text>
          </Pressable>
        ) : null}
        {!shopId ? (
          <View style={[styles.card, { flexDirection: 'row', alignItems: 'center' }]}>
            <Text style={{ flex: 1, color: colors.text }}>
              {t('J’accepte : au moins {min} % de remise aux clients Souki Deals, et {c} % de commission sur le montant payé, prélevée chaque lundi par carte.', {
                min: minDiscount,
                c: commission,
              })}
            </Text>
            <Switch value={accepted} onValueChange={setAccepted} trackColor={{ true: colors.prune, false: colors.border }} thumbColor="#FFFFFF" />
          </View>
        ) : null}

        <View style={{ height: 8 }} />
        <ErrorText>{error}</ErrorText>
        <Button title={shopId ? t('Enregistrer') : t('Envoyer mon inscription')} onPress={save} loading={saving} />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
