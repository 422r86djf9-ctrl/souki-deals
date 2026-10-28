-- 022 : précommande. Le client réserve une offre depuis chez lui (« J'y vais ») ; en arrivant,
-- l'appli voit qu'il est à moins de 150 m du commerce et la visite s'active : il apparaît sur la
-- tablette du commerçant sans scanner. Le QR code du comptoir reste possible en secours.
-- Une précommande non utilisée s'annule seule (4 h), sans compter comme une visite sans achat. Relançable.

do $$
declare r record;
begin
  for r in select conname from pg_constraint
           where conrelid = 'public.checkins'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%status%'
  loop
    execute format('alter table public.checkins drop constraint %I', r.conname);
  end loop;
  alter table public.checkins add constraint checkins_status_check
    check (status in ('reserved', 'waiting', 'done', 'expired', 'dismissed', 'cancelled'));
end $$;
create unique index if not exists checkins_one_reserved on public.checkins (client_id) where status = 'reserved';

-- Distance en mètres entre deux points
create or replace function public.deals_distance_m(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 2 * 6371000 * asin(sqrt(power(sin(radians(lat2 - lat1) / 2), 2)
         + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)))
$$;

-- Le commerçant est prévenu quand le client est vraiment là (visite active), pas à la précommande
create or replace function public.notify_checkin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'waiting' and (tg_op = 'INSERT' or old.status = 'reserved') then
    perform public.deals_notify((select array[owner_id] from public.shops where id = new.shop_id), 'client_present',
      jsonb_build_object('name', public.first_name(new.client_id)), jsonb_build_object('url', '/commercant'));
  end if;
  return new;
end $$;
drop trigger if exists checkins_notify on public.checkins;
create trigger checkins_notify after insert on public.checkins
  for each row execute function public.notify_checkin();
drop trigger if exists checkins_arrive_notify on public.checkins;
create trigger checkins_arrive_notify after update of status on public.checkins
  for each row execute function public.notify_checkin();

-- Précommandes oubliées : annulées sans bruit
create or replace function public.deals_expire_reservations()
returns void language plpgsql security definer set search_path = public as $$
begin
  with c as (
    update public.checkins set status = 'cancelled', closed_at = now()
    where status = 'reserved' and expires_at < now()
    returning voucher_id)
  update public.vouchers v set status = 'cancelled' from c where v.id = c.voucher_id and v.status = 'active';
end $$;

-- Client : « J'y vais » (offre facultative)
create or replace function public.client_reserve(p_shop_id uuid, p_promo_id bigint default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  st public.settings;
  c public.checkins;
  p public.promos;
  v record;
begin
  perform public.require_login();
  perform public.deals_expire_reservations();
  select * into st from public.settings where id = 1;
  if p_promo_id is not null then
    select * into p from public.promos where id = p_promo_id;
    if not found or p.shop_id <> p_shop_id or not p.active or p.ends_at <= now() or p.starts_at > now() then
      perform public.souki_error('Cette offre n''est plus valable dans ce commerce.', 'PROMO_INVALID');
    end if;
  end if;
  -- Déjà dans ce magasin : on garde la visite, on change seulement l'offre
  select * into c from public.checkins where client_id = v_uid and shop_id = p_shop_id and status = 'waiting' and expires_at > now();
  if found then
    update public.checkins set promo_id = p_promo_id where id = c.id returning * into c;
    return jsonb_build_object('checkin_id', c.id, 'status', c.status);
  end if;
  -- Une seule précommande à la fois : la précédente est annulée
  with old as (
    update public.checkins set status = 'cancelled', closed_at = now()
    where client_id = v_uid and status = 'reserved' and shop_id <> p_shop_id
    returning voucher_id)
  update public.vouchers vo set status = 'cancelled' from old where vo.id = old.voucher_id and vo.status = 'active';
  select * into c from public.checkins where client_id = v_uid and shop_id = p_shop_id and status = 'reserved';
  if found then
    update public.checkins set promo_id = p_promo_id where id = c.id returning * into c;
    return jsonb_build_object('checkin_id', c.id, 'status', c.status);
  end if;
  if exists (select 1 from public.purchases
             where client_id = v_uid and shop_id = p_shop_id and status <> 'cancelled'
               and created_at > now() - make_interval(mins => st.cooldown_minutes)) then
    perform public.souki_error('Vous avez déjà un achat compté ici il y a peu de temps.', 'TOO_SOON');
  end if;
  select * into v from public.create_voucher(p_shop_id);
  insert into public.checkins (shop_id, client_id, voucher_id, status, expires_at, promo_id)
  values (p_shop_id, v_uid, v.id, 'reserved', least(v.expires_at, now() + interval '4 hours'), p_promo_id)
  returning * into c;
  return jsonb_build_object('checkin_id', c.id, 'status', c.status);
end $$;

-- Client : arrivé au magasin (position du téléphone)
create or replace function public.client_arrive(p_id uuid, p_lat double precision, p_lng double precision, p_accuracy double precision default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  st public.settings;
  c public.checkins;
  s public.shops;
  d double precision;
  v_max double precision;
begin
  perform public.require_login();
  perform public.deals_expire_reservations();
  select * into st from public.settings where id = 1;
  select * into c from public.checkins where id = p_id and client_id = auth.uid() and status = 'reserved' for update;
  if not found then
    perform public.souki_error('Précommande introuvable ou expirée.', 'NOT_FOUND');
  end if;
  select * into s from public.shops where id = c.shop_id;
  if not public.shop_is_visible(s.id) then
    perform public.souki_error('Ce commerce n''est pas disponible.', 'SHOP_UNAVAILABLE');
  end if;
  if p_lat is null or p_lng is null then
    perform public.souki_error('Position introuvable : autorisez la localisation ou scannez le QR code du comptoir.', 'NO_POSITION');
  end if;
  d := public.deals_distance_m(p_lat, p_lng, s.lat, s.lng);
  v_max := 150 + least(greatest(coalesce(p_accuracy, 0), 0), 100);
  if d > v_max then
    perform public.souki_error(format('Vous êtes encore à %s m du commerce.', round(d)::text), 'TOO_FAR');
  end if;
  update public.checkins set status = 'waiting', created_at = now(),
    expires_at = now() + make_interval(mins => st.checkin_minutes)
  where id = c.id returning * into c;
  update public.vouchers set expires_at = greatest(expires_at, c.expires_at) where id = c.voucher_id;
  return jsonb_build_object('checkin_id', c.id, 'status', c.status, 'distance_m', round(d));
end $$;

-- Annulation : visite en cours ou précommande
create or replace function public.client_cancel_checkin(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.checkins;
begin
  perform public.require_login();
  update public.checkins set status = 'cancelled', closed_at = now()
  where id = p_id and client_id = auth.uid() and status in ('waiting', 'reserved')
  returning * into c;
  if not found then
    perform public.souki_error('Visite introuvable ou déjà terminée.', 'NOT_FOUND');
  end if;
  update public.vouchers set status = 'cancelled' where id = c.voucher_id and status = 'active';
end $$;

-- Changer d'offre : aussi pendant la précommande
create or replace function public.client_set_checkin_promo(p_id uuid, p_promo_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c public.checkins;
  p public.promos;
begin
  perform public.require_login();
  select * into c from public.checkins where id = p_id and client_id = auth.uid() and status in ('waiting', 'reserved') and expires_at > now() for update;
  if not found then
    perform public.souki_error('Visite introuvable ou déjà terminée.', 'NOT_FOUND');
  end if;
  if p_promo_id is null then
    update public.checkins set promo_id = null where id = c.id;
    return jsonb_build_object('promo_id', null);
  end if;
  select * into p from public.promos where id = p_promo_id;
  if not found or p.shop_id <> c.shop_id or not p.active or p.ends_at <= now() or p.starts_at > now() then
    perform public.souki_error('Cette offre n''est plus valable dans ce commerce.', 'PROMO_INVALID');
  end if;
  update public.checkins set promo_id = p.id where id = c.id;
  return jsonb_build_object('promo_id', p.id, 'kind', p.kind, 'title', p.title, 'discount_pct', p.discount_pct,
                            'min_cents', p.min_cents, 'ends_at', p.ends_at);
end $$;

-- QR code du comptoir : active aussi la précommande faite pour ce commerce
create or replace function public.client_checkin(p_shop_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  st public.settings;
  s public.shops;
  c public.checkins;
  v record;
  v_code text := upper(btrim(coalesce(p_shop_code, '')));
begin
  perform public.require_login();
  perform public.deals_expire_reservations();
  select * into st from public.settings where id = 1;
  v_code := coalesce(substring(v_code from 'SHOP:([A-Z2-9]{8})$'), v_code);
  select * into s from public.shops where shop_code = v_code;
  if not found then
    perform public.souki_error('QR code inconnu : scannez le QR code Souki Deals du commerce.', 'NOT_FOUND');
  end if;
  if not public.shop_is_visible(s.id) then
    perform public.souki_error('Ce commerce n''est pas disponible.', 'SHOP_UNAVAILABLE');
  end if;
  if s.owner_id = v_uid then
    perform public.souki_error('Impossible de prendre un bon dans votre propre commerce.', 'OWN_SHOP');
  end if;

  update public.checkins set status = 'expired', closed_at = now()
  where client_id = v_uid and status = 'waiting' and expires_at < now();
  update public.vouchers vo set status = 'expired'
  where vo.client_id = v_uid and vo.shop_id = s.id and vo.status = 'active'
    and exists (select 1 from public.checkins ck where ck.voucher_id = vo.id and ck.status not in ('waiting', 'reserved'));
  select * into c from public.checkins where client_id = v_uid and shop_id = s.id and status = 'waiting';
  if not found then
    update public.checkins set status = 'waiting', created_at = now(), expires_at = now() + make_interval(mins => st.checkin_minutes)
    where client_id = v_uid and shop_id = s.id and status = 'reserved'
    returning * into c;
    if found then
      update public.vouchers set expires_at = greatest(expires_at, c.expires_at) where id = c.voucher_id;
    end if;
  end if;
  if c.id is null then
    if exists (select 1 from public.purchases
               where client_id = v_uid and shop_id = s.id and status <> 'cancelled'
                 and created_at > now() - make_interval(mins => st.cooldown_minutes)) then
      perform public.souki_error('Vous avez déjà un achat compté ici il y a peu de temps.', 'TOO_SOON');
    end if;
    select * into v from public.create_voucher(s.id);
    insert into public.checkins (shop_id, client_id, voucher_id, expires_at)
    values (s.id, v_uid, v.id, least(v.expires_at, now() + make_interval(mins => st.checkin_minutes)))
    returning * into c;
  end if;
  return jsonb_build_object(
    'checkin_id', c.id, 'status', c.status, 'expires_at', c.expires_at,
    'voucher_id', c.voucher_id, 'code', (select code from public.vouchers where id = c.voucher_id),
    'shop_id', s.id, 'shop_name', s.name, 'discount_pct', s.discount_pct);
end $$;

revoke execute on function public.client_reserve(uuid, bigint), public.client_arrive(uuid, double precision, double precision, double precision),
  public.deals_expire_reservations() from public, anon, authenticated;
grant execute on function public.client_reserve(uuid, bigint), public.client_arrive(uuid, double precision, double precision, double precision) to authenticated;

do $do$
begin
  perform cron.unschedule('souki-deals-precommandes') where exists (select 1 from cron.job where jobname = 'souki-deals-precommandes');
  perform cron.schedule('souki-deals-precommandes', '*/15 * * * *', 'select public.deals_expire_reservations()');
exception when others then
  raise warning 'SOUKI DEALS : annulation automatique des précommandes non planifiée (%).', sqlerrm;
end $do$;
