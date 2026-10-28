begin;
-- SOUKI DEALS : mise a jour 021 (compte de la boutique d'essai).
-- AVANT DE LANCER : remplacez ChoisissezUnMotDePasse (plus bas) par le mot de passe de votre choix.
-- 021 : la boutique d'essai peut être « active » (pour tester l'espace commerçant) tout en restant
-- invisible des clients : elle n'est visible que du fondateur. Relançable.
create or replace function public.shop_is_visible(p_shop uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.shops s join public.zones z on z.id = s.zone_id
    where s.id = p_shop
      and (
        (s.status = 'active' and z.open and not public.shop_is_blocked(s.id)
         and s.owner_id <> '00000000-0000-4000-8000-0000000e55a1')
        or (s.owner_id = '00000000-0000-4000-8000-0000000e55a1' and public.is_admin())
      )
  );
$$;

-- Compte de connexion de la boutique d'essai : e-mail boutique-essai@soukideals.com
-- et le mot de passe que vous écrivez ci-dessous (entre les deux $$). La boutique passe « active »
-- mais reste invisible des clients.
do $do$
declare
  v_uid uuid := '00000000-0000-4000-8000-0000000e55a1';
  v_pw text := $$ChoisissezUnMotDePasse$$;
begin
  if v_pw = 'ChoisissezUnMotDePasse' or char_length(v_pw) < 8 then
    raise exception 'Écrivez votre propre mot de passe (8 caractères ou plus) à la place de ChoisissezUnMotDePasse.';
  end if;
  update auth.users set
    encrypted_password = extensions.crypt(v_pw, extensions.gen_salt('bf')),
    email_confirmed_at = coalesce(email_confirmed_at, now()),
    aud = 'authenticated', role = 'authenticated',
    instance_id = '00000000-0000-0000-0000-000000000000',
    raw_app_meta_data = '{"provider":"email","providers":["email"]}'::jsonb,
    raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb),
    confirmation_token = coalesce(confirmation_token, ''), recovery_token = coalesce(recovery_token, ''),
    email_change_token_new = coalesce(email_change_token_new, ''), email_change = coalesce(email_change, ''),
    email_change_token_current = coalesce(email_change_token_current, ''), phone_change = coalesce(phone_change, ''),
    phone_change_token = coalesce(phone_change_token, ''), reauthentication_token = coalesce(reauthentication_token, ''),
    updated_at = now()
  where id = v_uid;
  if not found then
    raise exception 'Boutique d''essai introuvable : lancez d''abord la mise à jour 019.';
  end if;
  insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (v_uid::text, v_uid, jsonb_build_object('sub', v_uid::text, 'email', 'boutique-essai@soukideals.com', 'email_verified', true),
          'email', now(), now(), now())
  on conflict do nothing;
  insert into public.profiles (id, full_name) values (v_uid, 'Boutique d''essai')
  on conflict (id) do update set full_name = coalesce(public.profiles.full_name, excluded.full_name);
  update public.shops set status = 'active', validated_at = coalesce(validated_at, now()) where owner_id = v_uid;
end $do$;

commit;
