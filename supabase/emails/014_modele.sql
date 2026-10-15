-- 014 : e-mails d'inscription, mot de passe oublié, lien de connexion et changement d'adresse,
-- envoyés directement par Resend aux couleurs de Souki Deals (fr, en, ar ; particulier ou commerçant).
-- Supabase appelle public.deals_send_auth_email grâce au « Send Email Hook »
-- (Authentication > Hooks > Send Email > Postgres > public.deals_send_auth_email).
-- La clé Resend est rangée dans le coffre-fort de Supabase (Vault) sous le nom resend_api_key.
-- Fichier généré par supabase/emails/generer.py : ne pas modifier à la main. N'efface rien, relançable.

-- Encode une valeur pour une adresse web (redirect_to)
create or replace function public.deals_urlencode(p text)
returns text language plpgsql immutable as $$
declare
  r text := '';
  b bytea := convert_to(coalesce(p, ''), 'UTF8');
  i int;
  c int;
begin
  for i in 0 .. length(b) - 1 loop
    c := get_byte(b, i);
    if (c between 48 and 57) or (c between 65 and 90) or (c between 97 and 122) or c in (45, 46, 95, 126) then
      r := r || chr(c);
    else
      r := r || '%' || upper(lpad(to_hex(c), 2, '0'));
    end if;
  end loop;
  return r;
end $$;

-- Échappe un texte pour l'insérer dans du HTML
create or replace function public.deals_html_escape(p text)
returns text language sql immutable as $$
  select replace(replace(replace(replace(coalesce(p, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;');
$$;

-- Objet et contenu de chaque e-mail (%%URL%% et %%NEW%% sont remplacés à l'envoi)
create or replace function public.deals_auth_email_text(p_key text, p_lang text)
returns text[] language sql immutable as $fn$
  select case p_key || ':' || p_lang
--@TEXTES@
  end;
$fn$;

-- Le hook : Supabase lui donne l'utilisateur et le lien à envoyer ; on envoie par Resend.
create or replace function public.deals_send_auth_email(event jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  u jsonb := event->'user';
  d jsonb := event->'email_data';
  v_action text := d->>'email_action_type';
  v_lang text := coalesce(nullif(u->'user_metadata'->>'lang', ''), 'fr');
  v_espace text := coalesce(u->'user_metadata'->>'espace', 'particulier');
  v_redirect text := coalesce(nullif(d->>'redirect_to', ''), nullif(d->>'site_url', ''), 'https://soukideals.com/compte-confirme.html');
  v_key text;
  v_kind text;
  v_sends jsonb := '[]'::jsonb;
  s jsonb;
  v_txt text[];
  v_url text;
begin
  if v_lang not in ('fr', 'en', 'ar') then
    v_lang := 'fr';
  end if;
  begin
    select decrypted_secret into v_key from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
  exception when others then
    v_key := null;
  end;
  if v_key is null or v_key = '' then
    return jsonb_build_object('error', jsonb_build_object('http_code', 500,
      'message', 'Envoi des e-mails non configuré : clé Resend absente du coffre-fort (resend_api_key).'));
  end if;

  if v_action = 'signup' or v_action = 'invite' then
    v_kind := case when v_espace = 'commercant' then 'signup_pro' else 'signup_client' end;
    v_sends := jsonb_build_array(jsonb_build_object('to', u->>'email', 'hash', d->>'token_hash', 'type', v_action));
  elsif v_action = 'recovery' then
    v_kind := 'recovery';
    v_sends := jsonb_build_array(jsonb_build_object('to', u->>'email', 'hash', d->>'token_hash', 'type', 'recovery'));
  elsif v_action = 'magiclink' then
    v_kind := 'magiclink';
    v_sends := jsonb_build_array(jsonb_build_object('to', u->>'email', 'hash', d->>'token_hash', 'type', 'magiclink'));
  elsif v_action = 'email_change' then
    v_kind := 'email_change';
    -- Nouvelle adresse : token_hash ; adresse actuelle (double confirmation) : token_hash_new
    if coalesce(u->>'new_email', '') <> '' and coalesce(d->>'token_hash', '') <> '' then
      v_sends := v_sends || jsonb_build_array(jsonb_build_object('to', u->>'new_email', 'hash', d->>'token_hash', 'type', 'email_change'));
    end if;
    if coalesce(d->>'token_hash_new', '') <> '' then
      v_sends := v_sends || jsonb_build_array(jsonb_build_object('to', u->>'email', 'hash', d->>'token_hash_new', 'type', 'email_change'));
    end if;
  else
    -- Autres cas (code de réauthentification…) : rien à envoyer de notre côté
    return '{}'::jsonb;
  end if;

  v_txt := public.deals_auth_email_text(v_kind, v_lang);
  for s in select * from jsonb_array_elements(v_sends) loop
    continue when coalesce(s->>'to', '') = '' or coalesce(s->>'hash', '') = '';
    v_url := 'https://rczotdgtkwfbnrbvyjon.supabase.co/auth/v1/verify?token=' || (s->>'hash')
             || '&type=' || (s->>'type') || '&redirect_to=' || public.deals_urlencode(v_redirect);
    perform net.http_post(
      url := 'https://api.resend.com/emails',
      body := jsonb_build_object(
        'from', 'Souki Deals <noreply@soukideals.com>',
        'to', jsonb_build_array(s->>'to'),
        'subject', v_txt[1],
        'html', replace(replace(v_txt[2], '%%URL%%', public.deals_html_escape(v_url)), '%%NEW%%', public.deals_html_escape(u->>'new_email'))),
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'));
  end loop;
  return '{}'::jsonb;
exception when others then
  return jsonb_build_object('error', jsonb_build_object('http_code', 500, 'message', 'Envoi de l''e-mail impossible : ' || sqlerrm));
end $$;

-- Seul Supabase Auth peut appeler le hook
revoke execute on function public.deals_send_auth_email(jsonb) from public, anon, authenticated;
grant usage on schema public to supabase_auth_admin;
grant execute on function public.deals_send_auth_email(jsonb) to supabase_auth_admin;
revoke execute on function public.deals_auth_email_text(text, text), public.deals_urlencode(text), public.deals_html_escape(text)
  from public, anon, authenticated;
