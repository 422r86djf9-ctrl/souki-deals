begin;
-- SOUKI DEALS : mise a jour 011 (suppression du compte, notifications). N'efface rien, relancable.
-- =====================================================================
-- SOUKI DEALS — 011 : suppression du compte et notifications
-- 1. Chacun peut supprimer son compte depuis l'appli (exigé par Google Play et l'App Store).
--    L'historique des achats est gardé, sans le nom du client (pour les commissions des
--    commerçants). Un commerçant qui doit encore de l'argent, ou à qui Souki Deals en doit,
--    règle d'abord la situation. Les factures sont gardées (copie des informations).
-- 2. Notifications sur le téléphone (service Expo, via pg_net), dans la langue de chacun :
--    client présent, achat à confirmer, achat contesté, offre flash près de chez soi,
--    commerce validé, prélèvement refusé, remboursement versé.
-- Ce fichier est relançable : il sert aussi de mise à jour (rien n'est effacé).
-- =====================================================================

-- ---------- Garder l'historique quand un compte est supprimé ----------
alter table public.vouchers alter column client_id drop not null;
alter table public.purchases alter column client_id drop not null;
alter table public.checkins alter column client_id drop not null;
alter table public.vouchers drop constraint if exists vouchers_client_id_fkey;
alter table public.vouchers add constraint vouchers_client_id_fkey foreign key (client_id) references auth.users(id) on delete set null;
alter table public.purchases drop constraint if exists purchases_client_id_fkey;
alter table public.purchases add constraint purchases_client_id_fkey foreign key (client_id) references auth.users(id) on delete set null;
alter table public.purchases drop constraint if exists purchases_scanned_by_fkey;
alter table public.purchases add constraint purchases_scanned_by_fkey foreign key (scanned_by) references auth.users(id) on delete set null;
alter table public.checkins drop constraint if exists checkins_client_id_fkey;
alter table public.checkins add constraint checkins_client_id_fkey foreign key (client_id) references auth.users(id) on delete set null;

create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_shop uuid;
begin
  perform public.require_login();
  if public.is_admin() then
    perform public.souki_error('Le compte du fondateur ne peut pas être supprimé depuis l''appli.', 'NOT_ALLOWED');
  end if;
  select id into v_shop from public.shops where owner_id = v_uid;
  if v_shop is not null then
    if exists (select 1 from public.charges where shop_id = v_shop and status in ('pending', 'failed') and amount_cents <> 0)
       or exists (select 1 from public.purchases where shop_id = v_shop and status in ('pending', 'confirmed', 'disputed')
                    and charge_id is null and ((not free and commission_cents > 0) or welcome_cents > 0)) then
      perform public.souki_error('Des commissions ou des remboursements sont en cours : contactez Souki Deals pour les régler avant de supprimer votre compte.', 'BALANCE_DUE');
    end if;
  end if;
  -- Bons et visites en cours : annulés
  update public.vouchers set status = 'cancelled' where client_id = v_uid and status = 'active';
  update public.checkins set status = 'cancelled', closed_at = now() where client_id = v_uid and status = 'waiting';
  delete from auth.users where id = v_uid;
end $$;

-- ---------- Notifications ----------
create table if not exists public.push_tokens (
  token       text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  updated_at  timestamptz not null default now()
);
create index if not exists push_tokens_user_idx on public.push_tokens (user_id);

create table if not exists public.notifications (
  id          bigserial primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  key         text not null,
  title       text not null,
  body        text not null,
  data        jsonb not null default '{}'::jsonb,
  sent        boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);

-- Préférences et zone approximative (arrondie à environ 1 km) pour les offres proches
alter table public.profiles add column if not exists notif_promos boolean not null default true;
alter table public.profiles add column if not exists area_lat numeric(6,2);
alter table public.profiles add column if not exists area_lng numeric(6,2);
alter table public.profiles add column if not exists area_at timestamptz;

alter table public.push_tokens enable row level security;
alter table public.notifications enable row level security;
drop policy if exists push_tokens_own on public.push_tokens;
create policy push_tokens_own on public.push_tokens for select to authenticated using (user_id = auth.uid());
drop policy if exists notifications_own on public.notifications;
create policy notifications_own on public.notifications for select to authenticated using (user_id = auth.uid());
grant select on public.push_tokens, public.notifications to authenticated;

create or replace function public.register_push_token(p_token text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_login();
  if p_token is null or p_token !~ '^(Exponent|Expo)PushToken\[.+\]$' then
    perform public.souki_error('Jeton de notification invalide.', 'BAD_TOKEN');
  end if;
  insert into public.push_tokens (token, user_id, updated_at) values (p_token, auth.uid(), now())
  on conflict (token) do update set user_id = excluded.user_id, updated_at = now();
end $$;

create or replace function public.unregister_push_token(p_token text)
returns void language sql security definer set search_path = public as $$
  delete from public.push_tokens where token = p_token and user_id = auth.uid();
$$;

-- Zone du client (arrondie) et choix des notifications d'offres
create or replace function public.set_my_area(p_lat double precision, p_lng double precision)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_login();
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    return;
  end if;
  update public.profiles set area_lat = round(p_lat::numeric, 2), area_lng = round(p_lng::numeric, 2), area_at = now()
  where id = auth.uid();
end $$;

create or replace function public.set_my_notif_promos(p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_login();
  update public.profiles set notif_promos = coalesce(p_on, true) where id = auth.uid();
end $$;

-- « 19,00 € »
create or replace function public.fmt_euros(p_cents int)
returns text language sql immutable as $$
  select replace(to_char(coalesce(p_cents, 0) / 100.0, 'FM999999990.00'), '.', ',') || ' €';
$$;

-- Textes des notifications (fr, en, ar) ; {mot} est remplacé par les paramètres
create or replace function public.deals_text(p_key text, p_lang text)
returns text[] language sql immutable as $$
  select case p_lang
    when 'en' then case p_key
      when 'client_present' then array['Customer in your shop', '{name} scanned your QR code. Enter the amount paid.']
      when 'purchase_to_confirm' then array['Confirm your purchase', 'Did you pay {amount} at {shop}?']
      when 'purchase_disputed' then array['Purchase disputed', 'A customer disputes a purchase of {amount}. Souki Deals will look into it.']
      when 'flash_nearby' then array['Flash offer near you', '{shop}: {title} -{pct}% until tonight']
      when 'shop_validated' then array['Your shop is live', '{shop} is now visible to Souki Deals customers.']
      when 'charge_failed' then array['Payment declined', 'The {amount} commission could not be charged. Your shop is hidden until it is paid.']
      when 'refund_sent' then array['Refund sent', 'Souki Deals has transferred {amount} to your account (welcome offers).']
    end
    when 'ar' then case p_key
      when 'client_present' then array['زبون في متجرك', 'مسح {name} رمزك. أدخل المبلغ المدفوع.']
      when 'purchase_to_confirm' then array['أكّد مشترياتك', 'هل دفعت {amount} في {shop}؟']
      when 'purchase_disputed' then array['شراء مُعترض عليه', 'زبون يعترض على شراء بقيمة {amount}. سيتابع Souki Deals الأمر.']
      when 'flash_nearby' then array['عرض خاطف قربك', '{shop}: {title} -{pct} % حتى هذا المساء']
      when 'shop_validated' then array['متجرك مفعّل', 'أصبح {shop} ظاهرًا لزبائن Souki Deals.']
      when 'charge_failed' then array['تعذّر الاقتطاع', 'لم تُقتطع العمولة {amount}. متجرك مخفي حتى الدفع.']
      when 'refund_sent' then array['تم إرسال التعويض', 'حوّل Souki Deals مبلغ {amount} إلى حسابك (عروض الترحيب).']
    end
    else case p_key
      when 'client_present' then array['Client dans votre magasin', '{name} a scanné votre QR code. Saisissez le montant payé.']
      when 'purchase_to_confirm' then array['Confirmez votre achat', 'Vous avez payé {amount} chez {shop} ?']
      when 'purchase_disputed' then array['Achat contesté', 'Un client conteste un achat de {amount}. Souki Deals va regarder.']
      when 'flash_nearby' then array['Offre flash près de chez vous', '{shop} : {title} à -{pct} % jusqu''à ce soir']
      when 'shop_validated' then array['Votre commerce est en ligne', '{shop} est maintenant visible des clients Souki Deals.']
      when 'charge_failed' then array['Prélèvement refusé', 'La commission de {amount} n''a pas pu être prélevée. Votre commerce est masqué jusqu''au paiement.']
      when 'refund_sent' then array['Remboursement envoyé', 'Souki Deals vous a viré {amount} (offres de bienvenue).']
    end
  end;
$$;

-- Envoie une notification à chacun, dans sa langue. Ne fait jamais échouer l'action qui l'appelle.
create or replace function public.deals_notify(p_users uuid[], p_key text, p_params jsonb, p_data jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_txt text[];
  v_title text;
  v_body text;
  v_messages jsonb;
  k text;
begin
  if p_users is null or cardinality(p_users) = 0 then
    return;
  end if;
  for r in
    select u.id, coalesce(p.lang, 'fr') as lang
    from (select distinct unnest(p_users) as id) u
    join auth.users au on au.id = u.id
    left join public.profiles p on p.id = u.id
  loop
    v_txt := public.deals_text(p_key, r.lang);
    if v_txt is null then
      v_txt := public.deals_text(p_key, 'fr');
    end if;
    continue when v_txt is null;
    v_title := v_txt[1];
    v_body := v_txt[2];
    for k in select jsonb_object_keys(coalesce(p_params, '{}'::jsonb)) loop
      v_body := replace(v_body, '{' || k || '}', coalesce(p_params->>k, ''));
      v_title := replace(v_title, '{' || k || '}', coalesce(p_params->>k, ''));
    end loop;
    select coalesce(jsonb_agg(jsonb_build_object('to', t.token, 'title', v_title, 'body', v_body,
                                                 'data', coalesce(p_data, '{}'::jsonb) || jsonb_build_object('key', p_key),
                                                 'sound', 'default', 'priority', 'high', 'channelId', 'default')), '[]'::jsonb)
      into v_messages
    from public.push_tokens t where t.user_id = r.id;
    insert into public.notifications (user_id, key, title, body, data, sent)
    values (r.id, p_key, v_title, v_body, coalesce(p_data, '{}'::jsonb), jsonb_array_length(v_messages) > 0);
    if jsonb_array_length(v_messages) > 0 then
      begin
        perform net.http_post(url := 'https://exp.host/--/api/v2/push/send', body := v_messages,
                              headers := '{"Content-Type": "application/json", "Accept": "application/json"}'::jsonb);
      exception when others then
        null;
      end;
    end if;
  end loop;
exception when others then
  raise warning 'SOUKI DEALS : notification ignorée (%).', sqlerrm;
end $$;

-- ---------- Qui prévenir, et quand ----------
-- Visite : le commerçant voit qu'un client est là
create or replace function public.notify_checkin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.deals_notify((select array[owner_id] from public.shops where id = new.shop_id), 'client_present',
    jsonb_build_object('name', public.first_name(new.client_id)), jsonb_build_object('url', '/commercant'));
  return new;
end $$;
drop trigger if exists checkins_notify on public.checkins;
create trigger checkins_notify after insert on public.checkins
  for each row execute function public.notify_checkin();

-- Achat : le client confirme ; achat contesté : le commerçant est prévenu
create or replace function public.notify_purchase()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_shop text; v_owner uuid;
begin
  select name, owner_id into v_shop, v_owner from public.shops where id = new.shop_id;
  if tg_op = 'INSERT' and new.status = 'pending' and new.client_id is not null then
    perform public.deals_notify(array[new.client_id], 'purchase_to_confirm',
      jsonb_build_object('amount', public.fmt_euros(new.amount_cents), 'shop', v_shop), jsonb_build_object('url', '/achats'));
  elsif tg_op = 'UPDATE' and new.status = 'disputed' and old.status is distinct from 'disputed' then
    perform public.deals_notify(array[v_owner], 'purchase_disputed',
      jsonb_build_object('amount', public.fmt_euros(new.amount_cents)), jsonb_build_object('url', '/commercant'));
  end if;
  return new;
end $$;
drop trigger if exists purchases_notify on public.purchases;
create trigger purchases_notify after insert or update of status on public.purchases
  for each row execute function public.notify_purchase();

-- Offre flash : clients à moins de 5 km qui acceptent les offres, une seule par jour au plus
create or replace function public.notify_promo()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  s public.shops;
  v_users uuid[];
  v_today timestamptz := (public.paris_today()::timestamp) at time zone 'Europe/Paris';
begin
  if new.kind <> 'flash' or not new.active then
    return new;
  end if;
  select * into s from public.shops where id = new.shop_id;
  if not public.shop_is_visible(s.id) then
    return new;
  end if;
  select coalesce(array_agg(p.id), '{}') into v_users
  from (
    select pr.id from public.profiles pr
    where pr.notif_promos and pr.area_lat is not null and pr.area_at > now() - interval '60 days'
      and pr.id <> s.owner_id
      and public.distance_km(pr.area_lat::double precision, pr.area_lng::double precision, s.lat, s.lng) <= 5
      and not exists (select 1 from public.notifications n
                      where n.user_id = pr.id and n.key = 'flash_nearby' and n.created_at >= v_today)
    limit 1000
  ) p;
  perform public.deals_notify(v_users, 'flash_nearby',
    jsonb_build_object('shop', s.name, 'title', new.title, 'pct', replace(trim(to_char(new.discount_pct, 'FM990.##')), '.', ',')),
    jsonb_build_object('url', '/commerce/' || s.id));
  return new;
end $$;
drop trigger if exists promos_notify on public.promos;
create trigger promos_notify after insert on public.promos
  for each row execute function public.notify_promo();

-- Commerce validé
create or replace function public.notify_shop()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'active' and old.status = 'pending' then
    perform public.deals_notify(array[new.owner_id], 'shop_validated', jsonb_build_object('shop', new.name),
                                jsonb_build_object('url', '/commercant'));
  end if;
  return new;
end $$;
drop trigger if exists shops_notify on public.shops;
create trigger shops_notify after update of status on public.shops
  for each row execute function public.notify_shop();

-- Prélèvement refusé ; remboursement versé
create or replace function public.notify_charge()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_owner uuid;
begin
  if new.status is not distinct from old.status then
    return new;
  end if;
  select owner_id into v_owner from public.shops where id = new.shop_id;
  if new.status = 'failed' and new.amount_cents > 0 then
    perform public.deals_notify(array[v_owner], 'charge_failed', jsonb_build_object('amount', public.fmt_euros(new.amount_cents)),
                                jsonb_build_object('url', '/commercant'));
  elsif new.status = 'paid' and new.amount_cents < 0 then
    perform public.deals_notify(array[v_owner], 'refund_sent', jsonb_build_object('amount', public.fmt_euros(-new.amount_cents)),
                                jsonb_build_object('url', '/commercant'));
  end if;
  return new;
end $$;
drop trigger if exists charges_notify on public.charges;
create trigger charges_notify after update of status on public.charges
  for each row execute function public.notify_charge();

-- ---------- Droits ----------
revoke execute on function
  public.delete_my_account(), public.register_push_token(text), public.unregister_push_token(text),
  public.set_my_area(double precision, double precision), public.set_my_notif_promos(boolean),
  public.fmt_euros(int), public.deals_text(text, text), public.deals_notify(uuid[], text, jsonb, jsonb),
  public.notify_checkin(), public.notify_purchase(), public.notify_promo(), public.notify_shop(), public.notify_charge()
from public, anon, authenticated;
grant execute on function
  public.delete_my_account(), public.register_push_token(text), public.unregister_push_token(text),
  public.set_my_area(double precision, double precision), public.set_my_notif_promos(boolean)
to authenticated;

commit;
