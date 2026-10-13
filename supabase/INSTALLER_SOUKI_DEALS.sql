begin;
-- SOUKI DEALS : installateur complet, a coller dans Supabase > SQL Editor > Run.

-- >>> 000_remise_a_zero.sql
-- =====================================================================
-- SOUKI DEALS — 000 : remise à zéro de la base de test
-- Supprime seulement les tables et fonctions de Souki Deals avant réinstallation.
-- Les comptes (Authentication > Users) ne sont PAS supprimés.
-- À installer dans un projet Supabase DÉDIÉ à Souki Deals.
-- =====================================================================

-- Sécurité : ne rien faire dans un projet qui contient d'autres tables
do $$
begin
  if exists (select 1 from information_schema.tables
             where table_schema = 'public'
               and table_name not in ('settings', 'zones', 'profiles', 'shops', 'products',
                                      'vouchers', 'purchases', 'charges', 'reports', 'company', 'invoices', 'checkins', 'promos', 'shop_bank', 'push_tokens', 'notifications')) then
    raise exception 'SOUKI DEALS : ce projet Supabase contient d''autres tables. Installez Souki Deals dans un projet dédié.';
  end if;
end $$;

-- Les factures se conservent 10 ans : pas de remise à zéro une fois la première émise
do $$
declare v_n bigint := 0;
begin
  if to_regclass('public.invoices') is not null then
    execute 'select count(*) from public.invoices' into v_n;
  end if;
  if v_n > 0 then
    raise exception 'SOUKI DEALS : des factures ont été émises. Remise à zéro interdite : utilisez un fichier MISE_A_JOUR.';
  end if;
end $$;

drop table if exists
  public.notifications, public.push_tokens, public.shop_bank, public.promos, public.checkins, public.invoices, public.company, public.reports, public.charges, public.purchases, public.vouchers,
  public.products, public.shops, public.profiles, public.zones, public.settings
cascade;

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'souki_error', 'paris_today', 'week_of', 'norm', 'distance_km', 'is_admin', 'require_admin', 'require_login',
      'my_shop_id', 'shop_is_blocked', 'shop_is_visible', 'launch_slots_left', 'whoami', 'set_my_lang',
      'guard_shops', 'guard_products', 'nearby_shops', 'search_products', 'new_voucher_code', 'create_voucher',
      'cancel_voucher', 'merchant_scan', 'client_answer_purchase', 'merchant_stats', 'report_create',
      'close_week', 'souki_deals_tick', 'admin_summary', 'admin_set_shop_status', 'admin_set_card_ok',
      'admin_resolve_purchase', 'admin_set_charge_status', 'admin_close_report', 'admin_set_zone_open',
      'admin_update_settings', 'guard_invoices', 'company_ready', 'send_invoice', 'issue_invoice',
      'charges_invoice_trigger', 'issue_missing_invoices', 'admin_save_company', 'admin_resend_invoice',
      'merchant_resend_invoice', 'current_terms_version', 'merchant_accept_terms', 'merchant_year_statement',
      'new_shop_code', 'purchases_close_checkin', 'first_name', 'client_checkin', 'client_cancel_checkin',
      'client_answer_checkin', 'merchant_checkins', 'merchant_complete_checkin', 'merchant_dismiss_checkin',
      'admin_shop_scores', 'admin_members', 'welcome_for', 'client_welcome', 'merchant_voucher_info',
      'merchant_save_promo', 'merchant_stop_promo', 'active_promos', 'admin_update_welcome', 'admin_promo_stats',
      'iban_valid', 'merchant_save_bank', 'delete_my_account', 'register_push_token', 'unregister_push_token',
      'set_my_area', 'set_my_notif_promos', 'fmt_euros', 'deals_text', 'deals_notify', 'notify_checkin',
      'notify_purchase', 'notify_promo', 'notify_shop', 'notify_charge')
  loop
    execute format('drop function if exists %s cascade', r.sig);
  end loop;
end $$;

-- >>> 001_schema.sql
-- =====================================================================
-- SOUKI DEALS — 001 : tables
-- Montants en centimes (19,00 € = 1900). Pourcentages en %.
-- =====================================================================

-- Réglages (une seule ligne, modifiables par le fondateur)
create table public.settings (
  id                   int primary key default 1 check (id = 1),
  discount_min         numeric(5,2) not null default 5 check (discount_min between 0 and 50),
  commission_rate      numeric(5,2) not null default 5 check (commission_rate between 0 and 30),
  voucher_hours        int not null default 24 check (voucher_hours between 1 and 168),
  max_active_vouchers  int not null default 5 check (max_active_vouchers between 1 and 50),
  cooldown_minutes     int not null default 120 check (cooldown_minutes between 0 and 1440),
  max_purchase_cents   int not null default 50000 check (max_purchase_cents between 100 and 1000000),
  confirm_hours        int not null default 24 check (confirm_hours between 1 and 168),
  launch_slots         int not null default 150 check (launch_slots between 0 and 100000),
  launch_free_months   int not null default 3 check (launch_free_months between 0 and 24)
);

-- Zones (départements, villes) : seules les zones ouvertes sont visibles des clients
create table public.zones (
  id        serial primary key,
  country   text not null default 'FR',
  currency  text not null default 'EUR',
  name      text not null unique,
  name_en   text,
  name_ar   text,
  open      boolean not null default false,
  sort      int not null default 0
);

create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text check (full_name is null or char_length(full_name) between 2 and 80),
  phone       text check (phone is null or phone ~ '^\+?[0-9 .-]{6,20}$'),
  lang        text not null default 'fr' check (lang in ('fr', 'en', 'ar')),
  created_at  timestamptz not null default now()
);

-- Commerces
--   status : pending (en attente de validation), active, suspended
--   launch_offer : fait partie des premiers inscrits (offre de lancement)
--   free_until : pas de commission jusqu'à cette date (fixée à la validation)
create table public.shops (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null unique references auth.users(id) on delete cascade,
  name          text not null check (char_length(name) between 2 and 60),
  kind          text not null check (kind in ('restaurant', 'boucherie', 'boulangerie', 'supermarche',
                                              'epicerie', 'primeur', 'poissonnerie')),
  zone_id       int not null references public.zones(id),
  address       text not null check (char_length(address) between 5 and 160),
  lat           double precision not null check (lat between -90 and 90),
  lng           double precision not null check (lng between -180 and 180),
  phone         text check (phone is null or phone ~ '^\+?[0-9 .-]{6,20}$'),
  siret         text check (siret is null or siret ~ '^[0-9]{14}$'),
  halal_cert    text check (halal_cert is null or char_length(halal_cert) <= 60),
  hours         text check (hours is null or char_length(hours) <= 200),
  description   text check (description is null or char_length(description) <= 400),
  discount_pct  numeric(5,2) not null default 5 check (discount_pct between 0 and 50),
  status        text not null default 'pending' check (status in ('pending', 'active', 'suspended')),
  launch_offer  boolean not null default false,
  free_until    date,
  card_ok       boolean not null default false,
  created_at    timestamptz not null default now(),
  validated_at  timestamptz
);
create index shops_zone_idx on public.shops (zone_id, status);

-- Produits d'un commerce. discount_pct null = la remise du commerce.
create table public.products (
  id            serial primary key,
  shop_id       uuid not null references public.shops(id) on delete cascade,
  name          text not null check (char_length(name) between 2 and 60),
  category      text check (category is null or char_length(category) <= 40),
  unit          text not null default 'piece' check (unit in ('piece', 'kg')),
  price_cents   int not null check (price_cents between 1 and 10000000),
  discount_pct  numeric(5,2) check (discount_pct is null or discount_pct between 0 and 90),
  in_stock      boolean not null default true,
  active        boolean not null default true,
  updated_at    timestamptz not null default now()
);
create index products_shop_idx on public.products (shop_id) where active;

-- Bons de réduction (QR code) d'un client pour un commerce
create table public.vouchers (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique check (code ~ '^[A-Z2-9]{8}$'),
  client_id   uuid not null references auth.users(id) on delete cascade,
  shop_id     uuid not null references public.shops(id) on delete cascade,
  status      text not null default 'active' check (status in ('active', 'used', 'expired', 'cancelled')),
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null
);
create index vouchers_client_idx on public.vouchers (client_id, status);

-- Achats scannés : la commission est calculée sur le montant payé
--   status : pending (en attente du client), confirmed, disputed, cancelled
create table public.purchases (
  id                uuid primary key default gen_random_uuid(),
  voucher_id        uuid not null unique references public.vouchers(id) on delete cascade,
  shop_id           uuid not null references public.shops(id) on delete cascade,
  client_id         uuid not null references auth.users(id) on delete cascade,
  amount_cents      int not null check (amount_cents > 0),
  discount_pct      numeric(5,2) not null,
  commission_rate   numeric(5,2) not null,
  commission_cents  int not null check (commission_cents >= 0),
  free              boolean not null default false,
  status            text not null default 'pending' check (status in ('pending', 'confirmed', 'disputed', 'cancelled')),
  dispute_reason    text,
  scanned_by        uuid references auth.users(id),
  created_at        timestamptz not null default now(),
  confirmed_at      timestamptz,
  week_start        date not null,
  charge_id         uuid
);
create index purchases_shop_idx on public.purchases (shop_id, created_at desc);
create index purchases_client_idx on public.purchases (client_id, created_at desc);

-- Prélèvements hebdomadaires des commissions (carte bancaire, via Stripe plus tard)
create table public.charges (
  id            uuid primary key default gen_random_uuid(),
  shop_id       uuid not null references public.shops(id) on delete cascade,
  week_start    date not null,
  amount_cents  int not null check (amount_cents >= 0),
  status        text not null default 'pending' check (status in ('pending', 'paid', 'failed', 'waived')),
  created_at    timestamptz not null default now(),
  paid_at       timestamptz,
  unique (shop_id, week_start)
);
alter table public.purchases add constraint purchases_charge_fk foreign key (charge_id) references public.charges(id) on delete set null;

-- Signalements des clients (prix faux, doute sur le halal, achat contesté…)
create table public.reports (
  id           bigserial primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  shop_id      uuid not null references public.shops(id) on delete cascade,
  product_id   int references public.products(id) on delete set null,
  purchase_id  uuid references public.purchases(id) on delete set null,
  kind         text not null check (kind in ('prix', 'halal', 'achat', 'autre')),
  body         text not null check (char_length(body) between 3 and 500),
  status       text not null default 'open' check (status in ('open', 'done')),
  created_at   timestamptz not null default now()
);

-- >>> 002_fonctions.sql
-- =====================================================================
-- SOUKI DEALS — 002 : règles métier
-- Erreurs : message en français + code dans « hint ».
-- =====================================================================

create function public.souki_error(p_message text, p_code text)
returns void language plpgsql as $$
begin
  raise exception '%', p_message using hint = p_code, errcode = 'P0001';
end $$;

create function public.paris_today()
returns date language sql stable as $$
  select (now() at time zone 'Europe/Paris')::date;
$$;

-- Lundi de la semaine (heure de Paris)
create function public.week_of(p_ts timestamptz)
returns date language sql stable as $$
  select date_trunc('week', p_ts at time zone 'Europe/Paris')::date;
$$;

-- Texte sans accents ni majuscules, pour la recherche
create function public.norm(p text)
returns text language sql immutable as $$
  select lower(translate(coalesce(p, ''),
    'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝŸ',
    'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUYY'));
$$;

-- Distance en km entre deux points
create function public.distance_km(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns double precision language sql immutable as $$
  select 6371 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)));
$$;

-- Le fondateur, seul administrateur (e-mail vérifié)
create function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from auth.users u
    where u.id = auth.uid()
      and lower(u.email) = 'demba.sacko20@gmail.com'
      and u.email_confirmed_at is not null
  );
$$;

create function public.require_admin()
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then
    perform public.souki_error('Action réservée au fondateur.', 'NOT_ADMIN');
  end if;
end $$;

create function public.require_login()
returns void language plpgsql stable as $$
begin
  if auth.uid() is null then
    perform public.souki_error('Connectez-vous pour continuer.', 'NOT_AUTHENTICATED');
  end if;
end $$;

create function public.my_shop_id()
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.shops where owner_id = auth.uid();
$$;

-- Commerce masqué : prélèvement refusé, ou en attente depuis plus de 7 jours
create function public.shop_is_blocked(p_shop uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.charges c
    where c.shop_id = p_shop
      and (c.status = 'failed' or (c.status = 'pending' and c.created_at < now() - interval '7 days'))
  );
$$;

-- Visible des clients : validé, zone ouverte, pas masqué
create function public.shop_is_visible(p_shop uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.shops s join public.zones z on z.id = s.zone_id
    where s.id = p_shop and s.status = 'active' and z.open and not public.shop_is_blocked(s.id)
  );
$$;

create function public.launch_slots_left()
returns int language sql stable security definer set search_path = public as $$
  select greatest((select launch_slots from public.settings where id = 1)
                  - (select count(*)::int from public.shops where launch_offer), 0);
$$;

-- ---------------------------------------------------------------------
-- Qui suis-je ?
-- ---------------------------------------------------------------------
create function public.whoami()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('user_id', null, 'is_admin', false);
  end if;
  return jsonb_build_object(
    'user_id', v_uid,
    'email', (select email from auth.users where id = v_uid),
    'is_admin', public.is_admin(),
    'profile', (select jsonb_build_object('full_name', p.full_name, 'phone', p.phone, 'lang', p.lang)
                from public.profiles p where p.id = v_uid),
    'shop', (select jsonb_build_object('id', s.id, 'name', s.name, 'status', s.status,
                                       'launch_offer', s.launch_offer, 'free_until', s.free_until,
                                       'blocked', public.shop_is_blocked(s.id))
             from public.shops s where s.owner_id = v_uid),
    'pending_purchases', (select count(*) from public.purchases where client_id = v_uid and status = 'pending')
  );
end $$;

create function public.set_my_lang(p_lang text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_login();
  if p_lang is null or p_lang not in ('fr', 'en', 'ar') then
    perform public.souki_error('Langue inconnue.', 'BAD_LANG');
  end if;
  insert into public.profiles (id, lang) values (auth.uid(), p_lang)
  on conflict (id) do update set lang = excluded.lang;
end $$;

-- ---------------------------------------------------------------------
-- Gardiens : champs protégés et règles de remise
-- ---------------------------------------------------------------------
create function public.guard_shops()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_min numeric;
begin
  select discount_min into v_min from public.settings where id = 1;
  -- Vérifiée seulement quand la remise change (un minimum relevé ne bloque pas les autres modifications)
  if (tg_op = 'INSERT' or new.discount_pct is distinct from old.discount_pct) and new.discount_pct < v_min then
    perform public.souki_error(format('La remise doit être d''au moins %s %%.', v_min), 'DISCOUNT_TOO_LOW');
  end if;
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.owner_id := auth.uid();
    new.status := 'pending';
    new.launch_offer := false;
    new.free_until := null;
    new.card_ok := false;
    new.validated_at := null;
    new.created_at := now();
  else
    new.owner_id := old.owner_id;
    new.status := old.status;
    new.launch_offer := old.launch_offer;
    new.free_until := old.free_until;
    new.card_ok := old.card_ok;
    new.validated_at := old.validated_at;
    new.created_at := old.created_at;
  end if;
  return new;
end $$;
create trigger shops_guard before insert or update on public.shops
  for each row execute function public.guard_shops();

create function public.guard_products()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_min numeric;
begin
  select discount_min into v_min from public.settings where id = 1;
  if new.discount_pct is not null and new.discount_pct < v_min
     and (tg_op = 'INSERT' or new.discount_pct is distinct from old.discount_pct) then
    perform public.souki_error(format('La remise doit être d''au moins %s %%.', v_min), 'DISCOUNT_TOO_LOW');
  end if;
  if tg_op = 'UPDATE' then
    new.shop_id := old.shop_id;
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger products_guard before insert or update on public.products
  for each row execute function public.guard_products();

-- ---------------------------------------------------------------------
-- Clients : autour de moi, recherche
-- ---------------------------------------------------------------------
-- p_lat / p_lng null : pas de tri par distance (liste de la zone choisie)
create function public.nearby_shops(p_lat double precision default null, p_lng double precision default null,
                                    p_radius_km double precision default 5, p_kind text default null,
                                    p_zone int default null)
returns table (id uuid, name text, kind text, address text, lat double precision, lng double precision,
               discount_pct numeric, best_discount numeric, distance_km double precision,
               halal_cert text, hours text, zone_id int, products_count int)
language sql stable security definer set search_path = public as $$
  select s.id, s.name, s.kind, s.address, s.lat, s.lng, s.discount_pct,
         greatest(s.discount_pct, coalesce((select max(p.discount_pct) from public.products p
                                            where p.shop_id = s.id and p.active and p.in_stock), 0)),
         case when p_lat is null or p_lng is null then null
              else round(public.distance_km(p_lat, p_lng, s.lat, s.lng)::numeric, 2)::double precision end,
         s.halal_cert, s.hours, s.zone_id,
         (select count(*)::int from public.products p where p.shop_id = s.id and p.active)
  from public.shops s
  join public.zones z on z.id = s.zone_id
  where s.status = 'active' and z.open and not public.shop_is_blocked(s.id)
    and (p_kind is null or s.kind = p_kind)
    and (p_zone is null or s.zone_id = p_zone)
    and (p_lat is null or p_lng is null
         or public.distance_km(p_lat, p_lng, s.lat, s.lng) <= least(greatest(coalesce(p_radius_km, 5), 0.5), 50))
  order by case when p_lat is null or p_lng is null then 0
                else public.distance_km(p_lat, p_lng, s.lat, s.lng) end, s.name
  limit 200;
$$;

create function public.search_products(p_query text, p_lat double precision default null,
                                       p_lng double precision default null, p_radius_km double precision default 10,
                                       p_zone int default null)
returns table (product_id int, product_name text, category text, unit text, price_cents int,
               discount_pct numeric, final_cents int, in_stock boolean,
               shop_id uuid, shop_name text, kind text, address text, distance_km double precision)
language plpgsql stable security definer set search_path = public as $$
declare v_q text := btrim(public.norm(p_query));
begin
  if char_length(v_q) < 2 then
    return;
  end if;
  return query
  select p.id, p.name, p.category, p.unit, p.price_cents,
         coalesce(p.discount_pct, s.discount_pct),
         round(p.price_cents * (1 - coalesce(p.discount_pct, s.discount_pct) / 100))::int,
         p.in_stock, s.id, s.name, s.kind, s.address,
         case when p_lat is null or p_lng is null then null
              else round(public.distance_km(p_lat, p_lng, s.lat, s.lng)::numeric, 2)::double precision end
  from public.products p
  join public.shops s on s.id = p.shop_id
  join public.zones z on z.id = s.zone_id
  where p.active and s.status = 'active' and z.open and not public.shop_is_blocked(s.id)
    and (public.norm(p.name) like '%' || v_q || '%' or public.norm(coalesce(p.category, '')) like '%' || v_q || '%')
    and (p_zone is null or s.zone_id = p_zone)
    and (p_lat is null or p_lng is null
         or public.distance_km(p_lat, p_lng, s.lat, s.lng) <= least(greatest(coalesce(p_radius_km, 10), 0.5), 50))
  order by p.in_stock desc,
           round(p.price_cents * (1 - coalesce(p.discount_pct, s.discount_pct) / 100)),
           case when p_lat is null or p_lng is null then 0 else public.distance_km(p_lat, p_lng, s.lat, s.lng) end
  limit 100;
end $$;

-- ---------------------------------------------------------------------
-- Bons de réduction (QR code)
-- ---------------------------------------------------------------------
create function public.new_voucher_code()
returns text language plpgsql volatile as $$
declare
  v_alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  loop
    v_code := '';
    for i in 1..8 loop
      v_code := v_code || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1);
    end loop;
    exit when not exists (select 1 from public.vouchers where code = v_code);
  end loop;
  return v_code;
end $$;

-- Le client obtient (ou retrouve) son bon pour un commerce
create function public.create_voucher(p_shop_id uuid)
returns table (id uuid, code text, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  st public.settings;
  v public.vouchers;
begin
  perform public.require_login();
  select * into st from public.settings where settings.id = 1;
  if not public.shop_is_visible(p_shop_id) then
    perform public.souki_error('Ce commerce n''est pas disponible.', 'SHOP_UNAVAILABLE');
  end if;
  if exists (select 1 from public.shops where shops.id = p_shop_id and owner_id = v_uid) then
    perform public.souki_error('Impossible de prendre un bon dans votre propre commerce.', 'OWN_SHOP');
  end if;
  update public.vouchers set status = 'expired'
  where client_id = v_uid and status = 'active' and vouchers.expires_at < now();

  select * into v from public.vouchers
  where client_id = v_uid and shop_id = p_shop_id and status = 'active'
  order by created_at desc limit 1;
  if found then
    return query select v.id, v.code, v.expires_at;
    return;
  end if;

  if (select count(*) from public.vouchers where client_id = v_uid and status = 'active') >= st.max_active_vouchers then
    perform public.souki_error(format('Vous avez déjà %s bons en cours : utilisez-en un ou annulez-le.', st.max_active_vouchers), 'TOO_MANY');
  end if;
  insert into public.vouchers (code, client_id, shop_id, expires_at)
  values (public.new_voucher_code(), v_uid, p_shop_id, now() + make_interval(hours => st.voucher_hours))
  returning * into v;
  return query select v.id, v.code, v.expires_at;
end $$;

create function public.cancel_voucher(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_login();
  update public.vouchers set status = 'cancelled'
  where id = p_id and client_id = auth.uid() and status = 'active';
  if not found then
    perform public.souki_error('Bon introuvable ou déjà utilisé.', 'NOT_FOUND');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Commerçant : scan du bon en caisse
-- ---------------------------------------------------------------------
create function public.merchant_scan(p_code text, p_amount_cents int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  st public.settings;
  s public.shops;
  v public.vouchers;
  v_free boolean;
  v_commission int;
  v_id uuid;
begin
  perform public.require_login();
  select * into st from public.settings where id = 1;
  select * into s from public.shops where owner_id = auth.uid();
  if not found then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  if s.status <> 'active' then
    perform public.souki_error('Votre commerce n''est pas encore validé.', 'SHOP_NOT_ACTIVE');
  end if;
  select * into v from public.vouchers where code = upper(btrim(coalesce(p_code, ''))) for update;
  if not found then
    perform public.souki_error('Bon introuvable : vérifiez le code.', 'NOT_FOUND');
  end if;
  if v.shop_id <> s.id then
    perform public.souki_error('Ce bon est pour un autre commerce.', 'WRONG_SHOP');
  end if;
  if v.status = 'used' then
    perform public.souki_error('Ce bon a déjà été utilisé.', 'ALREADY_USED');
  end if;
  if v.status <> 'active' or v.expires_at < now() then
    perform public.souki_error('Ce bon a expiré.', 'EXPIRED');
  end if;
  if p_amount_cents is null or p_amount_cents < 1 or p_amount_cents > st.max_purchase_cents then
    perform public.souki_error(format('Montant invalide (maximum %s €).', st.max_purchase_cents / 100), 'BAD_AMOUNT');
  end if;
  if exists (select 1 from public.purchases
             where client_id = v.client_id and shop_id = s.id and status <> 'cancelled'
               and created_at > now() - make_interval(mins => st.cooldown_minutes)) then
    perform public.souki_error('Ce client a déjà un achat compté ici il y a peu de temps.', 'TOO_SOON');
  end if;

  v_free := s.free_until is not null and public.paris_today() <= s.free_until;
  v_commission := round(p_amount_cents * st.commission_rate / 100);
  insert into public.purchases (voucher_id, shop_id, client_id, amount_cents, discount_pct, commission_rate,
                                commission_cents, free, scanned_by, week_start)
  values (v.id, s.id, v.client_id, p_amount_cents, s.discount_pct, st.commission_rate,
          v_commission, v_free, auth.uid(), public.week_of(now()))
  returning id into v_id;
  update public.vouchers set status = 'used' where id = v.id;
  return jsonb_build_object('purchase_id', v_id, 'amount_cents', p_amount_cents,
                            'commission_cents', v_commission, 'free', v_free);
end $$;

-- Le client confirme le montant, ou le conteste
create function public.client_answer_purchase(p_id uuid, p_ok boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare pu public.purchases;
begin
  perform public.require_login();
  select * into pu from public.purchases where id = p_id and client_id = auth.uid() for update;
  if not found or pu.status <> 'pending' then
    perform public.souki_error('Achat introuvable ou déjà traité.', 'NOT_FOUND');
  end if;
  if p_ok then
    update public.purchases set status = 'confirmed', confirmed_at = now() where id = p_id;
  else
    if p_reason is null or char_length(btrim(p_reason)) < 3 then
      perform public.souki_error('Expliquez en quelques mots ce qui ne va pas.', 'BAD_REASON');
    end if;
    update public.purchases set status = 'disputed', dispute_reason = left(btrim(p_reason), 500) where id = p_id;
    insert into public.reports (user_id, shop_id, purchase_id, kind, body)
    values (auth.uid(), pu.shop_id, p_id, 'achat', left(btrim(p_reason), 500));
  end if;
end $$;

-- Tableau de bord du commerçant
create function public.merchant_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  s public.shops;
  v_today timestamptz := (public.paris_today()::timestamp) at time zone 'Europe/Paris';
  v_week timestamptz := (public.week_of(now())::timestamp) at time zone 'Europe/Paris';
  v_month timestamptz := (date_trunc('month', now() at time zone 'Europe/Paris')) at time zone 'Europe/Paris';
begin
  select * into s from public.shops where owner_id = auth.uid();
  if not found then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  return jsonb_build_object(
    'today_cents', (select coalesce(sum(amount_cents), 0) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed') and created_at >= v_today),
    'today_count', (select count(*) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed') and created_at >= v_today),
    'week_cents', (select coalesce(sum(amount_cents), 0) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed') and created_at >= v_week),
    'week_count', (select count(*) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed') and created_at >= v_week),
    'month_cents', (select coalesce(sum(amount_cents), 0) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed') and created_at >= v_month),
    'month_count', (select count(*) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed') and created_at >= v_month),
    'commission_due_cents', (select coalesce(sum(commission_cents), 0) from public.purchases where shop_id = s.id and status = 'confirmed' and not free and charge_id is null),
    'commission_offered_cents', (select coalesce(sum(commission_cents), 0) from public.purchases where shop_id = s.id and status = 'confirmed' and free),
    'clients_count', (select count(distinct client_id) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed')),
    'status', s.status,
    'launch_offer', s.launch_offer,
    'free_until', s.free_until,
    'card_ok', s.card_ok,
    'blocked', public.shop_is_blocked(s.id),
    'discount_pct', s.discount_pct
  );
end $$;

-- Signalement d'un client
create function public.report_create(p_shop_id uuid, p_kind text, p_body text, p_product_id int default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  perform public.require_login();
  if p_kind not in ('prix', 'halal', 'autre') then
    perform public.souki_error('Type de signalement invalide.', 'BAD_KIND');
  end if;
  if p_body is null or char_length(btrim(p_body)) not between 3 and 500 then
    perform public.souki_error('Décrivez le problème (3 à 500 caractères).', 'BAD_BODY');
  end if;
  if not exists (select 1 from public.shops where id = p_shop_id) then
    perform public.souki_error('Commerce introuvable.', 'NOT_FOUND');
  end if;
  if (select count(*) from public.reports where user_id = auth.uid() and created_at > now() - interval '1 day') >= 10 then
    perform public.souki_error('Trop de signalements aujourd''hui.', 'TOO_MANY');
  end if;
  insert into public.reports (user_id, shop_id, product_id, kind, body)
  values (auth.uid(), p_shop_id,
          (select id from public.products where id = p_product_id and shop_id = p_shop_id),
          p_kind, btrim(p_body))
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Tâches automatiques (pg_cron, toutes les 10 minutes)
--   - achats sans réponse du client : confirmés après confirm_hours
--   - bons périmés : expirés
--   - le lundi : prélèvement des commissions de la semaine passée
-- ---------------------------------------------------------------------
create function public.close_week(p_week date)
returns int language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_charge uuid;
  v_count int := 0;
begin
  for r in
    select shop_id, sum(commission_cents)::int as amount
    from public.purchases
    where status = 'confirmed' and not free and charge_id is null and week_start <= p_week
    group by shop_id
    having sum(commission_cents) > 0
  loop
    v_charge := null;
    -- Un prélèvement déjà payé, refusé ou offert n'est plus modifié :
    -- les achats confirmés en retard partent dans le prélèvement suivant.
    insert into public.charges (shop_id, week_start, amount_cents)
    values (r.shop_id, p_week, r.amount)
    on conflict (shop_id, week_start) do update set amount_cents = public.charges.amount_cents + excluded.amount_cents
      where public.charges.status = 'pending'
    returning id into v_charge;
    continue when v_charge is null;
    update public.purchases set charge_id = v_charge
    where shop_id = r.shop_id and status = 'confirmed' and not free and charge_id is null and week_start <= p_week;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

create function public.souki_deals_tick()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_hours int;
  v_confirmed int;
  v_expired int;
  v_charges int;
begin
  select confirm_hours into v_hours from public.settings where id = 1;
  update public.purchases set status = 'confirmed', confirmed_at = now()
  where status = 'pending' and created_at < now() - make_interval(hours => coalesce(v_hours, 24));
  get diagnostics v_confirmed = row_count;
  update public.vouchers set status = 'expired' where status = 'active' and expires_at < now();
  get diagnostics v_expired = row_count;
  -- Semaine passée (lundi précédent) : clôturée dès le lundi
  v_charges := public.close_week(public.week_of(now()) - 7);
  return jsonb_build_object('confirmed', v_confirmed, 'expired', v_expired, 'charges', v_charges);
end $$;

-- ---------------------------------------------------------------------
-- Administration (fondateur)
-- ---------------------------------------------------------------------
create function public.admin_summary()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_today timestamptz := (public.paris_today()::timestamp) at time zone 'Europe/Paris';
  v_week timestamptz := (public.week_of(now())::timestamp) at time zone 'Europe/Paris';
  v_month timestamptz := (date_trunc('month', now() at time zone 'Europe/Paris')) at time zone 'Europe/Paris';
begin
  perform public.require_admin();
  return jsonb_build_object(
    'today_count', (select count(*) from public.purchases where status in ('pending', 'confirmed') and created_at >= v_today),
    'today_cents', (select coalesce(sum(amount_cents), 0) from public.purchases where status in ('pending', 'confirmed') and created_at >= v_today),
    'today_commission', (select coalesce(sum(commission_cents), 0) from public.purchases where status in ('pending', 'confirmed') and not free and created_at >= v_today),
    'week_count', (select count(*) from public.purchases where status in ('pending', 'confirmed') and created_at >= v_week),
    'week_commission', (select coalesce(sum(commission_cents), 0) from public.purchases where status in ('pending', 'confirmed') and not free and created_at >= v_week),
    'month_commission', (select coalesce(sum(commission_cents), 0) from public.purchases where status in ('pending', 'confirmed') and not free and created_at >= v_month),
    'offered_month', (select coalesce(sum(commission_cents), 0) from public.purchases where status in ('pending', 'confirmed') and free and created_at >= v_month),
    'shops_pending', (select count(*) from public.shops where status = 'pending'),
    'shops_active', (select count(*) from public.shops where status = 'active'),
    'shops_suspended', (select count(*) from public.shops where status = 'suspended'),
    'launch_slots_left', public.launch_slots_left(),
    'disputes_open', (select count(*) from public.purchases where status = 'disputed'),
    'reports_open', (select count(*) from public.reports where status = 'open'),
    'charges_pending_cents', (select coalesce(sum(amount_cents), 0) from public.charges where status in ('pending', 'failed')),
    'users_count', (select count(*) from public.profiles),
    'vouchers_active', (select count(*) from public.vouchers where status = 'active' and expires_at > now())
  );
end $$;

-- À la première validation, le commerce reçoit l'offre de lancement s'il reste des places
-- (les places sont attribuées dans l'ordre des validations).
create function public.admin_set_shop_status(p_shop_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare
  s public.shops;
  st public.settings;
  v_offer boolean;
begin
  perform public.require_admin();
  if p_status not in ('pending', 'active', 'suspended') then
    perform public.souki_error('Statut invalide.', 'BAD_STATUS');
  end if;
  select * into st from public.settings where id = 1 for update; -- une validation à la fois
  select * into s from public.shops where id = p_shop_id for update;
  if not found then
    perform public.souki_error('Commerce introuvable.', 'NOT_FOUND');
  end if;
  v_offer := s.launch_offer;
  if p_status = 'active' and s.validated_at is null and not s.launch_offer then
    v_offer := public.launch_slots_left() > 0;
  end if;
  update public.shops set
    status = p_status,
    validated_at = case when p_status = 'active' and validated_at is null then now() else validated_at end,
    launch_offer = v_offer,
    free_until = case when p_status = 'active' and v_offer and free_until is null
                      then (public.paris_today() + make_interval(months => st.launch_free_months))::date
                      else free_until end
  where id = p_shop_id;
end $$;

create function public.admin_set_card_ok(p_shop_id uuid, p_ok boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  update public.shops set card_ok = coalesce(p_ok, false) where id = p_shop_id;
  if not found then
    perform public.souki_error('Commerce introuvable.', 'NOT_FOUND');
  end if;
end $$;

create function public.admin_resolve_purchase(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  if p_status not in ('confirmed', 'cancelled') then
    perform public.souki_error('Statut invalide.', 'BAD_STATUS');
  end if;
  update public.purchases set status = p_status,
    confirmed_at = case when p_status = 'confirmed' then now() else confirmed_at end
  where id = p_id and status in ('pending', 'disputed');
  if not found then
    perform public.souki_error('Achat introuvable ou déjà traité.', 'NOT_FOUND');
  end if;
  update public.reports set status = 'done' where purchase_id = p_id and status = 'open';
end $$;

create function public.admin_set_charge_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  if p_status not in ('pending', 'paid', 'failed', 'waived') then
    perform public.souki_error('Statut invalide.', 'BAD_STATUS');
  end if;
  update public.charges set status = p_status,
    paid_at = case when p_status = 'paid' then now() else null end
  where id = p_id;
  if not found then
    perform public.souki_error('Prélèvement introuvable.', 'NOT_FOUND');
  end if;
end $$;

create function public.admin_close_report(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  update public.reports set status = 'done' where id = p_id and status = 'open';
  if not found then
    perform public.souki_error('Signalement introuvable.', 'NOT_FOUND');
  end if;
end $$;

create function public.admin_set_zone_open(p_zone int, p_open boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  update public.zones set open = coalesce(p_open, false) where id = p_zone;
  if not found then
    perform public.souki_error('Zone introuvable.', 'NOT_FOUND');
  end if;
end $$;

create function public.admin_update_settings(
  p_discount_min numeric, p_commission_rate numeric, p_voucher_hours int, p_max_active_vouchers int,
  p_cooldown_minutes int, p_max_purchase_cents int, p_confirm_hours int, p_launch_slots int, p_launch_free_months int)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  if p_discount_min is null or p_discount_min not between 0 and 50
     or p_commission_rate is null or p_commission_rate not between 0 and 30
     or p_voucher_hours is null or p_voucher_hours not between 1 and 168
     or p_max_active_vouchers is null or p_max_active_vouchers not between 1 and 50
     or p_cooldown_minutes is null or p_cooldown_minutes not between 0 and 1440
     or p_max_purchase_cents is null or p_max_purchase_cents not between 100 and 1000000
     or p_confirm_hours is null or p_confirm_hours not between 1 and 168
     or p_launch_slots is null or p_launch_slots not between 0 and 100000
     or p_launch_free_months is null or p_launch_free_months not between 0 and 24 then
    perform public.souki_error('Valeurs invalides : vérifiez les paramètres.', 'BAD_SETTINGS');
  end if;
  update public.settings set
    discount_min = p_discount_min, commission_rate = p_commission_rate, voucher_hours = p_voucher_hours,
    max_active_vouchers = p_max_active_vouchers, cooldown_minutes = p_cooldown_minutes,
    max_purchase_cents = p_max_purchase_cents, confirm_hours = p_confirm_hours,
    launch_slots = p_launch_slots, launch_free_months = p_launch_free_months
  where id = 1;
end $$;

-- >>> 003_securite.sql
-- =====================================================================
-- SOUKI DEALS — 003 : sécurité (RLS) et droits
-- Les clients peuvent consulter commerces et produits sans compte.
-- Tout ce qui touche à l'argent passe par des fonctions serveur.
-- =====================================================================

alter table public.settings  enable row level security;
alter table public.zones     enable row level security;
alter table public.profiles  enable row level security;
alter table public.shops     enable row level security;
alter table public.products  enable row level security;
alter table public.vouchers  enable row level security;
alter table public.purchases enable row level security;
alter table public.charges   enable row level security;
alter table public.reports   enable row level security;

create policy settings_read on public.settings for select using (true);
create policy zones_read on public.zones for select using (true);

create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy profiles_insert on public.profiles for insert to authenticated
  with check (id = auth.uid());
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Commerces : visibles s'ils sont validés (zone ouverte) ; le propriétaire et le fondateur voient tout
create policy shops_select on public.shops for select
  using (public.shop_is_visible(id) or owner_id = auth.uid() or public.is_admin());
create policy shops_insert on public.shops for insert to authenticated
  with check (owner_id = auth.uid());
create policy shops_update on public.shops for update to authenticated
  using (owner_id = auth.uid() or public.is_admin())
  with check (owner_id = auth.uid() or public.is_admin());

create policy products_select on public.products for select
  using ((active and public.shop_is_visible(shop_id)) or shop_id = public.my_shop_id() or public.is_admin());
create policy products_insert on public.products for insert to authenticated
  with check (shop_id = public.my_shop_id());
create policy products_update on public.products for update to authenticated
  using (shop_id = public.my_shop_id()) with check (shop_id = public.my_shop_id());
create policy products_delete on public.products for delete to authenticated
  using (shop_id = public.my_shop_id());

create policy vouchers_select on public.vouchers for select to authenticated
  using (client_id = auth.uid() or shop_id = public.my_shop_id() or public.is_admin());
create policy purchases_select on public.purchases for select to authenticated
  using (client_id = auth.uid() or shop_id = public.my_shop_id() or public.is_admin());
create policy charges_select on public.charges for select to authenticated
  using (shop_id = public.my_shop_id() or public.is_admin());
create policy reports_select on public.reports for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- Droits sur les tables
grant select on public.settings, public.zones, public.products to anon, authenticated;
grant select on public.shops to authenticated;
-- Sans compte : seulement les colonnes publiques des commerces
grant select (id, name, kind, zone_id, address, lat, lng, phone, halal_cert, hours, description, discount_pct, status)
  on public.shops to anon;
grant select, insert, update on public.profiles to authenticated;
grant insert, update on public.shops to authenticated;
grant insert, update, delete on public.products to authenticated;
grant usage on sequence public.products_id_seq to authenticated;
grant select on public.vouchers, public.purchases, public.charges, public.reports to authenticated;

-- Droits sur les fonctions : fermées par défaut, puis ouvertes une à une
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function
  public.nearby_shops(double precision, double precision, double precision, text, int),
  public.search_products(text, double precision, double precision, double precision, int),
  public.launch_slots_left(), public.whoami(), public.shop_is_visible(uuid), public.shop_is_blocked(uuid),
  public.is_admin(), public.my_shop_id(), public.norm(text), public.distance_km(double precision, double precision, double precision, double precision),
  public.paris_today(), public.week_of(timestamptz)
to anon, authenticated;
grant execute on function
  public.set_my_lang(text), public.create_voucher(uuid), public.cancel_voucher(uuid),
  public.merchant_scan(text, int), public.client_answer_purchase(uuid, boolean, text),
  public.merchant_stats(), public.report_create(uuid, text, text, int),
  public.admin_summary(), public.admin_set_shop_status(uuid, text), public.admin_set_card_ok(uuid, boolean),
  public.admin_resolve_purchase(uuid, text), public.admin_set_charge_status(uuid, text),
  public.admin_close_report(bigint), public.admin_set_zone_open(int, boolean),
  public.admin_update_settings(numeric, numeric, int, int, int, int, int, int, int),
  public.souki_error(text, text), public.require_login(), public.require_admin()
to authenticated;
-- Les déclencheurs (guard_*) s'exécutent sans droit d'appel direct.

-- Vérifications automatiques toutes les 10 minutes (pg_cron, disponible sur Supabase)
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('souki-deals-taches', '*/10 * * * *', 'select public.souki_deals_tick()');
exception when others then
  raise warning 'SOUKI DEALS : pg_cron indisponible, tâches automatiques NON planifiées (%). Activez pg_cron (Database > Extensions) puis relancez.', sqlerrm;
end $$;

-- >>> 004_donnees.sql
-- =====================================================================
-- SOUKI DEALS — 004 : données de départ
-- Réglages validés le 11 octobre 2026 : remise client 5 % minimum,
-- commission 5 % du montant payé, 3 mois offerts aux 150 premiers commerces.
-- Lancement en Île-de-France (8 départements, ouverts).
-- =====================================================================

insert into public.settings (id) values (1);

insert into public.zones (country, currency, name, name_en, name_ar, open, sort) values
  ('FR', 'EUR', 'Paris (75)',             'Paris (75)',             'باريس (75)', true, 1),
  ('FR', 'EUR', 'Seine-Saint-Denis (93)', 'Seine-Saint-Denis (93)', 'سين سان دوني (93)', true, 2),
  ('FR', 'EUR', 'Val-de-Marne (94)',      'Val-de-Marne (94)',      'فال دو مارن (94)', true, 3),
  ('FR', 'EUR', 'Hauts-de-Seine (92)',    'Hauts-de-Seine (92)',    'أو دو سين (92)', true, 4),
  ('FR', 'EUR', 'Val-d''Oise (95)',       'Val-d''Oise (95)',       'فال دواز (95)', true, 5),
  ('FR', 'EUR', 'Essonne (91)',           'Essonne (91)',           'إيسون (91)', true, 6),
  ('FR', 'EUR', 'Yvelines (78)',          'Yvelines (78)',          'إيفلين (78)', true, 7),
  ('FR', 'EUR', 'Seine-et-Marne (77)',    'Seine-et-Marne (77)',    'سين إي مارن (77)', true, 8);

-- >>> 005_factures.sql
-- =====================================================================
-- SOUKI DEALS — 005 : factures des commissions
-- Dès qu'un prélèvement de commission est payé, une facture numérotée est
-- créée (numérotation continue, sans trou), puis la fonction « envoyer-facture »
-- (Supabase Edge Function) fabrique le PDF et l'envoie au commerçant par e-mail.
-- Une facture émise ne se modifie plus et ne se supprime pas (conservation 10 ans).
-- Ce fichier est relançable : il sert aussi de mise à jour (rien n'est effacé).
-- =====================================================================

-- Envoi des demandes HTTP depuis la base (disponible sur Supabase)
do $$
begin
  create extension if not exists pg_net;
exception when others then
  raise warning 'SOUKI DEALS : pg_net indisponible, les factures ne partiront pas par e-mail (%). Activez pg_net (Database > Extensions) puis relancez.', sqlerrm;
end $$;

-- Informations de la société qui facture (une seule ligne, remplie par le fondateur)
--   vat_rate : TVA comprise dans la commission (20 = 20 % ; 0 = franchise en base, art. 293 B du CGI)
create table if not exists public.company (
  id              int primary key default 1 check (id = 1),
  legal_name      text check (legal_name is null or char_length(legal_name) between 2 and 80),
  legal_form      text check (legal_form is null or char_length(legal_form) <= 40),
  capital         text check (capital is null or char_length(capital) <= 40),
  address         text check (address is null or char_length(address) between 5 and 200),
  siret           text check (siret is null or siret ~ '^[0-9]{14}$'),
  rcs             text check (rcs is null or char_length(rcs) <= 60),
  vat_number      text check (vat_number is null or vat_number ~ '^FR[0-9A-Z]{2}[0-9]{9}$'),
  email           text check (email is null or email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  vat_rate        numeric(5,2) not null default 20 check (vat_rate between 0 and 30),
  invoice_prefix  text not null default 'SD' check (invoice_prefix ~ '^[A-Z0-9]{1,6}$'),
  next_number     int not null default 1 check (next_number >= 1),
  hook_url        text,
  updated_at      timestamptz not null default now()
);
insert into public.company (id, hook_url)
values (1, 'https://rczotdgtkwfbnrbvyjon.supabase.co/functions/v1/envoyer-facture')
on conflict (id) do nothing;

-- Factures émises. seller / buyer : copie des informations au jour de la facture.
--   email_status : pending (à envoyer), sent (envoyée), failed (échec après plusieurs essais)
create table if not exists public.invoices (
  id                uuid primary key default gen_random_uuid(),
  number            text not null unique,
  seq               int not null unique,
  shop_id           uuid references public.shops(id) on delete set null,
  charge_id         uuid unique references public.charges(id) on delete set null,
  issued_at         timestamptz not null default now(),
  paid_at           timestamptz,
  period_start      date not null,
  period_end        date not null,
  purchases_count   int not null,
  sales_cents       int not null,
  commission_rate   numeric(5,2),
  amount_ht_cents   int not null,
  vat_rate          numeric(5,2) not null,
  vat_cents         int not null,
  amount_ttc_cents  int not null check (amount_ttc_cents > 0),
  seller            jsonb not null,
  buyer             jsonb not null,
  email_to          text,
  email_status      text not null default 'pending' check (email_status in ('pending', 'sent', 'failed')),
  email_attempts    int not null default 0,
  email_last_try    timestamptz,
  email_sent_at     timestamptz,
  email_error       text,
  pdf_path          text
);
create index if not exists invoices_shop_idx on public.invoices (shop_id, issued_at desc);

-- Une facture émise est figée : seuls l'envoi et le PDF peuvent changer
create or replace function public.guard_invoices()
returns trigger language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Une facture ne peut pas être supprimée (conservation obligatoire).' using hint = 'INVOICE_LOCKED', errcode = 'P0001';
  end if;
  if new.number is distinct from old.number or new.seq is distinct from old.seq
     or new.issued_at is distinct from old.issued_at or new.paid_at is distinct from old.paid_at
     or new.period_start is distinct from old.period_start or new.period_end is distinct from old.period_end
     or new.purchases_count is distinct from old.purchases_count or new.sales_cents is distinct from old.sales_cents
     or new.commission_rate is distinct from old.commission_rate
     or new.amount_ht_cents is distinct from old.amount_ht_cents or new.vat_rate is distinct from old.vat_rate
     or new.vat_cents is distinct from old.vat_cents or new.amount_ttc_cents is distinct from old.amount_ttc_cents
     or new.seller is distinct from old.seller or new.buyer is distinct from old.buyer
     or (new.shop_id is distinct from old.shop_id and new.shop_id is not null)
     or (new.charge_id is distinct from old.charge_id and new.charge_id is not null) then
    raise exception 'Une facture émise ne peut pas être modifiée.' using hint = 'INVOICE_LOCKED', errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists invoices_guard on public.invoices;
create trigger invoices_guard before update or delete on public.invoices
  for each row execute function public.guard_invoices();

-- Les informations de la société sont-elles suffisantes pour facturer ?
create or replace function public.company_ready()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.company
    where id = 1 and legal_name is not null and address is not null and siret is not null
      and (vat_rate = 0 or vat_number is not null)
  );
$$;

-- Demande l'envoi d'une facture (fonction « envoyer-facture »). Ne fait jamais échouer une action.
create or replace function public.send_invoice(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_url text;
begin
  select hook_url into v_url from public.company where id = 1;
  update public.invoices set email_attempts = email_attempts + 1, email_last_try = now()
  where id = p_id and email_status = 'pending';
  if not found or v_url is null or v_url = '' then
    return;
  end if;
  begin
    perform net.http_post(
      url := v_url,
      body := jsonb_build_object('invoice_id', p_id),
      headers := jsonb_build_object('Content-Type', 'application/json')
    );
  exception when others then
    -- pg_net absent ou indisponible : nouvel essai par la tâche automatique
    null;
  end;
end $$;

-- Crée la facture d'un prélèvement payé. Renvoie son id (null si rien à facturer
-- ou si les informations de la société ne sont pas encore remplies).
create or replace function public.issue_invoice(p_charge uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  c public.charges;
  co public.company;
  s public.shops;
  v_id uuid;
  v_seq int;
  v_ht int;
  v_vat int;
  v_email text;
  v_zone text;
  v_start date;
  v_count int;
  v_sales int;
  v_rate numeric;
begin
  select * into c from public.charges where id = p_charge;
  if not found or c.status <> 'paid' or c.amount_cents <= 0 then
    return null;
  end if;
  select id into v_id from public.invoices where charge_id = p_charge;
  if found then
    return v_id;
  end if;
  if not public.company_ready() then
    return null;
  end if;
  -- Une facture à la fois : numéros continus, sans trou ni doublon
  select * into co from public.company where id = 1 for update;
  v_seq := co.next_number;
  select * into s from public.shops where id = c.shop_id;
  select u.email into v_email from auth.users u where u.id = s.owner_id and u.email_confirmed_at is not null;
  select name into v_zone from public.zones where id = s.zone_id;
  select min(week_start), count(*), coalesce(sum(amount_cents), 0), max(commission_rate)
    into v_start, v_count, v_sales, v_rate
  from public.purchases where charge_id = c.id;
  -- La commission prélevée est TTC : on en déduit le hors taxe
  v_ht := round(c.amount_cents * 100.0 / (100 + co.vat_rate));
  v_vat := c.amount_cents - v_ht;

  insert into public.invoices (number, seq, shop_id, charge_id, paid_at, period_start, period_end,
    purchases_count, sales_cents, commission_rate, amount_ht_cents, vat_rate, vat_cents, amount_ttc_cents,
    seller, buyer, email_to, email_status)
  values (
    format('%s-%s-%s', co.invoice_prefix, to_char(now() at time zone 'Europe/Paris', 'YYYY'), lpad(v_seq::text, 6, '0')),
    v_seq, c.shop_id, c.id, coalesce(c.paid_at, now()),
    least(coalesce(v_start, c.week_start), c.week_start), c.week_start + 6,
    v_count, v_sales, v_rate, v_ht, co.vat_rate, v_vat, c.amount_cents,
    jsonb_build_object('legal_name', co.legal_name, 'legal_form', co.legal_form, 'capital', co.capital,
      'address', co.address, 'siret', co.siret, 'rcs', co.rcs, 'vat_number', co.vat_number, 'email', co.email),
    jsonb_build_object('name', s.name, 'address', s.address, 'zone', v_zone, 'siret', s.siret, 'email', v_email),
    v_email,
    case when v_email is null then 'failed' else 'pending' end
  )
  returning id into v_id;
  update public.company set next_number = v_seq + 1 where id = 1;
  if v_email is null then
    update public.invoices set email_error = 'Aucune adresse e-mail vérifiée pour ce commerce.' where id = v_id;
  else
    perform public.send_invoice(v_id);
  end if;
  return v_id;
end $$;

-- Prélèvement passé à « payé » : facture automatique
create or replace function public.charges_invoice_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'paid' and old.status is distinct from 'paid' then
    perform public.issue_invoice(new.id);
  end if;
  return new;
end $$;
drop trigger if exists charges_invoice on public.charges;
create trigger charges_invoice after update on public.charges
  for each row execute function public.charges_invoice_trigger();

-- Prélèvements payés sans facture (société pas encore remplie) : factures créées dans l'ordre des paiements
create or replace function public.issue_missing_invoices()
returns int language plpgsql security definer set search_path = public as $$
declare r record; v_n int := 0;
begin
  if not public.company_ready() then
    return 0;
  end if;
  for r in
    select c.id from public.charges c
    where c.status = 'paid' and c.amount_cents > 0
      and not exists (select 1 from public.invoices i where i.charge_id = c.id)
    order by c.paid_at nulls first, c.created_at
  loop
    if public.issue_invoice(r.id) is not null then
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $$;

-- ---------------------------------------------------------------------
-- Administration (fondateur)
-- ---------------------------------------------------------------------
create or replace function public.admin_save_company(
  p_legal_name text, p_legal_form text, p_capital text, p_address text, p_siret text,
  p_rcs text, p_vat_number text, p_email text, p_vat_rate numeric, p_invoice_prefix text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_siret text := nullif(regexp_replace(coalesce(p_siret, ''), '\s', '', 'g'), '');
  v_vat text := nullif(upper(regexp_replace(coalesce(p_vat_number, ''), '\s', '', 'g')), '');
  v_prefix text := upper(coalesce(nullif(trim(p_invoice_prefix), ''), 'SD'));
  v_issued int;
begin
  perform public.require_admin();
  if char_length(coalesce(trim(p_legal_name), '')) < 2 then
    perform public.souki_error('Indiquez la raison sociale de la société.', 'BAD_COMPANY');
  end if;
  if char_length(coalesce(trim(p_address), '')) < 5 then
    perform public.souki_error('Indiquez l''adresse du siège.', 'BAD_COMPANY');
  end if;
  if v_siret is null or v_siret !~ '^[0-9]{14}$' then
    perform public.souki_error('Le SIRET doit faire 14 chiffres.', 'BAD_SIRET');
  end if;
  if p_vat_rate is null or p_vat_rate not between 0 and 30 then
    perform public.souki_error('Taux de TVA invalide.', 'BAD_COMPANY');
  end if;
  if p_vat_rate > 0 and (v_vat is null or v_vat !~ '^FR[0-9A-Z]{2}[0-9]{9}$') then
    perform public.souki_error('Numéro de TVA invalide (FR + 11 caractères).', 'BAD_VAT');
  end if;
  if v_prefix !~ '^[A-Z0-9]{1,6}$' then
    perform public.souki_error('Préfixe des factures : 1 à 6 lettres ou chiffres.', 'BAD_COMPANY');
  end if;
  if nullif(trim(p_email), '') is not null and trim(p_email) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    perform public.souki_error('Adresse e-mail invalide.', 'BAD_COMPANY');
  end if;
  -- Le préfixe ne change plus après la première facture (numérotation continue)
  if exists (select 1 from public.invoices) and v_prefix <> (select invoice_prefix from public.company where id = 1) then
    perform public.souki_error('Le préfixe ne peut plus changer : des factures existent déjà.', 'INVOICE_LOCKED');
  end if;
  update public.company set
    legal_name = trim(p_legal_name), legal_form = nullif(trim(p_legal_form), ''),
    capital = nullif(trim(p_capital), ''), address = trim(p_address), siret = v_siret,
    rcs = nullif(trim(p_rcs), ''), vat_number = v_vat, email = nullif(trim(p_email), ''),
    vat_rate = p_vat_rate, invoice_prefix = v_prefix, updated_at = now()
  where id = 1;
  v_issued := public.issue_missing_invoices();
  return jsonb_build_object('issued', v_issued);
end $$;

create or replace function public.admin_resend_invoice(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  update public.invoices set email_status = 'pending', email_attempts = 0, email_error = null
  where id = p_id and email_to is not null;
  if not found then
    perform public.souki_error('Facture introuvable ou sans adresse e-mail.', 'NOT_FOUND');
  end if;
  perform public.send_invoice(p_id);
end $$;

-- Le commerçant redemande sa facture par e-mail (une fois toutes les 10 minutes)
create or replace function public.merchant_resend_invoice(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare i public.invoices; v_email text;
begin
  perform public.require_login();
  select * into i from public.invoices where id = p_id and shop_id = public.my_shop_id();
  if not found then
    perform public.souki_error('Facture introuvable.', 'NOT_FOUND');
  end if;
  if i.email_last_try is not null and i.email_last_try > now() - interval '10 minutes' then
    perform public.souki_error('Facture déjà envoyée il y a moins de 10 minutes : vérifiez vos courriers indésirables.', 'TOO_SOON');
  end if;
  -- Adresse du compte actuelle (si elle a changé depuis l'émission)
  select u.email into v_email from auth.users u where u.id = auth.uid() and u.email_confirmed_at is not null;
  update public.invoices set email_status = 'pending', email_attempts = 0, email_error = null,
    email_to = coalesce(v_email, email_to)
  where id = p_id;
  perform public.send_invoice(p_id);
end $$;

-- Changement de statut d'un prélèvement : impossible une fois facturé
create or replace function public.admin_set_charge_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  if p_status not in ('pending', 'paid', 'failed', 'waived') then
    perform public.souki_error('Statut invalide.', 'BAD_STATUS');
  end if;
  if exists (select 1 from public.invoices where charge_id = p_id) then
    perform public.souki_error('Prélèvement déjà facturé : il ne peut plus changer.', 'INVOICED');
  end if;
  update public.charges set status = p_status,
    paid_at = case when p_status = 'paid' then now() else null end
  where id = p_id;
  if not found then
    perform public.souki_error('Prélèvement introuvable.', 'NOT_FOUND');
  end if;
end $$;

-- Tâches automatiques : en plus, nouvel essai d'envoi des factures (5 essais, toutes les 30 minutes)
create or replace function public.souki_deals_tick()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_hours int;
  v_confirmed int;
  v_expired int;
  v_charges int;
  v_retry int := 0;
  r record;
begin
  select confirm_hours into v_hours from public.settings where id = 1;
  update public.purchases set status = 'confirmed', confirmed_at = now()
  where status = 'pending' and created_at < now() - make_interval(hours => coalesce(v_hours, 24));
  get diagnostics v_confirmed = row_count;
  update public.vouchers set status = 'expired' where status = 'active' and expires_at < now();
  get diagnostics v_expired = row_count;
  v_charges := public.close_week(public.week_of(now()) - 7);
  update public.invoices set email_status = 'failed',
    email_error = coalesce(email_error, 'Envoi impossible après 5 essais.')
  where email_status = 'pending' and email_attempts >= 5 and email_last_try < now() - interval '30 minutes';
  for r in
    select id from public.invoices
    where email_status = 'pending' and email_attempts < 5
      and (email_last_try is null or email_last_try < now() - interval '30 minutes')
    order by seq limit 20
  loop
    perform public.send_invoice(r.id);
    v_retry := v_retry + 1;
  end loop;
  return jsonb_build_object('confirmed', v_confirmed, 'expired', v_expired, 'charges', v_charges, 'invoice_retries', v_retry);
end $$;

create or replace function public.admin_summary()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_today timestamptz := (public.paris_today()::timestamp) at time zone 'Europe/Paris';
  v_week timestamptz := (public.week_of(now())::timestamp) at time zone 'Europe/Paris';
  v_month timestamptz := (date_trunc('month', now() at time zone 'Europe/Paris')) at time zone 'Europe/Paris';
begin
  perform public.require_admin();
  return jsonb_build_object(
    'today_count', (select count(*) from public.purchases where status in ('pending', 'confirmed') and created_at >= v_today),
    'today_cents', (select coalesce(sum(amount_cents), 0) from public.purchases where status in ('pending', 'confirmed') and created_at >= v_today),
    'today_commission', (select coalesce(sum(commission_cents), 0) from public.purchases where status in ('pending', 'confirmed') and not free and created_at >= v_today),
    'week_count', (select count(*) from public.purchases where status in ('pending', 'confirmed') and created_at >= v_week),
    'week_commission', (select coalesce(sum(commission_cents), 0) from public.purchases where status in ('pending', 'confirmed') and not free and created_at >= v_week),
    'month_commission', (select coalesce(sum(commission_cents), 0) from public.purchases where status in ('pending', 'confirmed') and not free and created_at >= v_month),
    'offered_month', (select coalesce(sum(commission_cents), 0) from public.purchases where status in ('pending', 'confirmed') and free and created_at >= v_month),
    'shops_pending', (select count(*) from public.shops where status = 'pending'),
    'shops_active', (select count(*) from public.shops where status = 'active'),
    'shops_suspended', (select count(*) from public.shops where status = 'suspended'),
    'launch_slots_left', public.launch_slots_left(),
    'disputes_open', (select count(*) from public.purchases where status = 'disputed'),
    'reports_open', (select count(*) from public.reports where status = 'open'),
    'charges_pending_cents', (select coalesce(sum(amount_cents), 0) from public.charges where status in ('pending', 'failed')),
    'users_count', (select count(*) from public.profiles),
    'vouchers_active', (select count(*) from public.vouchers where status = 'active' and expires_at > now()),
    'invoices_month', (select count(*) from public.invoices where issued_at >= v_month),
    'invoices_missing', (select count(*) from public.charges c where c.status = 'paid' and c.amount_cents > 0
                          and not exists (select 1 from public.invoices i where i.charge_id = c.id)),
    'invoices_failed', (select count(*) from public.invoices where email_status = 'failed'),
    'company_ready', public.company_ready()
  );
end $$;

-- ---------------------------------------------------------------------
-- Sécurité
-- ---------------------------------------------------------------------
alter table public.company  enable row level security;
alter table public.invoices enable row level security;

drop policy if exists company_select on public.company;
create policy company_select on public.company for select to authenticated using (public.is_admin());
drop policy if exists invoices_select on public.invoices;
create policy invoices_select on public.invoices for select to authenticated
  using (shop_id = public.my_shop_id() or public.is_admin());
grant select on public.company, public.invoices to authenticated;

-- PDF des factures : stockage privé « factures/<commerce>/<numéro>.pdf »
insert into storage.buckets (id, name, public) values ('factures', 'factures', false)
on conflict (id) do nothing;
drop policy if exists factures_read on storage.objects;
create policy factures_read on storage.objects for select to authenticated
  using (bucket_id = 'factures'
         and ((storage.foldername(name))[1] = public.my_shop_id()::text or public.is_admin()));

revoke execute on function
  public.guard_invoices(), public.company_ready(), public.send_invoice(uuid), public.issue_invoice(uuid),
  public.charges_invoice_trigger(), public.issue_missing_invoices(),
  public.admin_save_company(text, text, text, text, text, text, text, text, numeric, text),
  public.admin_resend_invoice(uuid), public.merchant_resend_invoice(uuid)
from public, anon, authenticated;
grant execute on function
  public.company_ready(),
  public.admin_save_company(text, text, text, text, text, text, text, text, numeric, text),
  public.admin_resend_invoice(uuid), public.merchant_resend_invoice(uuid)
to authenticated;

-- >>> 006_releve.sql
-- =====================================================================
-- SOUKI DEALS — 006 : conditions acceptées et relevé annuel du commerçant
-- - Chaque commerce garde la version, la date et les taux des conditions acceptées
--   (preuve du contrat, téléchargeable en PDF dans l'appli).
-- - merchant_year_statement(année) : tout ce que le comptable du commerçant demande
--   (factures, commissions HT/TVA/TTC par mois, ventes amenées et remises accordées).
-- Ce fichier est relançable : il sert aussi de mise à jour (rien n'est effacé).
-- =====================================================================

alter table public.shops add column if not exists terms_version text;
alter table public.shops add column if not exists terms_accepted_at timestamptz;
alter table public.shops add column if not exists terms_commission_rate numeric(5,2);
alter table public.shops add column if not exists terms_discount_min numeric(5,2);

-- Version en vigueur des conditions commerçant (le texte est dans l'appli : src/lib/conditions.ts)
create or replace function public.current_terms_version()
returns text language sql immutable as $$ select '2026-10-12'::text $$;

-- Commerces inscrits avant cette mise à jour : l'inscription exigeait déjà d'accepter
-- la remise minimum et la commission (version du 11 octobre 2026)
update public.shops s set
  terms_version = '2026-10-11',
  terms_accepted_at = s.created_at,
  terms_commission_rate = (select commission_rate from public.settings where id = 1),
  terms_discount_min = (select discount_min from public.settings where id = 1)
where s.terms_accepted_at is null;

-- Gardien des commerces : en plus, les conditions acceptées sont enregistrées par le serveur
create or replace function public.guard_shops()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_min numeric; v_rate numeric;
begin
  select discount_min, commission_rate into v_min, v_rate from public.settings where id = 1;
  if (tg_op = 'INSERT' or new.discount_pct is distinct from old.discount_pct) and new.discount_pct < v_min then
    perform public.souki_error(format('La remise doit être d''au moins %s %%.', v_min), 'DISCOUNT_TOO_LOW');
  end if;
  -- Conditions : fixées à l'inscription, puis seulement par merchant_accept_terms()
  if tg_op = 'INSERT' then
    new.terms_version := public.current_terms_version();
    new.terms_accepted_at := now();
    new.terms_commission_rate := v_rate;
    new.terms_discount_min := v_min;
  elsif coalesce(current_setting('souki.accept_terms', true), '') <> 'on' then
    new.terms_version := old.terms_version;
    new.terms_accepted_at := old.terms_accepted_at;
    new.terms_commission_rate := old.terms_commission_rate;
    new.terms_discount_min := old.terms_discount_min;
  end if;
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.owner_id := auth.uid();
    new.status := 'pending';
    new.launch_offer := false;
    new.free_until := null;
    new.card_ok := false;
    new.validated_at := null;
    new.created_at := now();
  else
    new.owner_id := old.owner_id;
    new.status := old.status;
    new.launch_offer := old.launch_offer;
    new.free_until := old.free_until;
    new.card_ok := old.card_ok;
    new.validated_at := old.validated_at;
    new.created_at := old.created_at;
  end if;
  return new;
end $$;

-- Le commerçant accepte la nouvelle version des conditions
create or replace function public.merchant_accept_terms()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_id uuid := public.my_shop_id();
begin
  perform public.require_login();
  if v_id is null then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  perform set_config('souki.accept_terms', 'on', true);
  update public.shops set
    terms_version = public.current_terms_version(),
    terms_accepted_at = now(),
    terms_commission_rate = (select commission_rate from public.settings where id = 1),
    terms_discount_min = (select discount_min from public.settings where id = 1)
  where id = v_id;
  perform set_config('souki.accept_terms', '', true);
  return jsonb_build_object('version', public.current_terms_version(), 'accepted_at', now());
end $$;

-- Relevé annuel du commerçant (année civile, heure de Paris)
create or replace function public.merchant_year_statement(p_year int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  s public.shops;
  co public.company;
  v_from timestamptz;
  v_to timestamptz;
  v_zone text;
  v_email text;
begin
  perform public.require_login();
  select * into s from public.shops where owner_id = auth.uid();
  if not found then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  if p_year is null or p_year not between 2024 and 2100 then
    perform public.souki_error('Année invalide.', 'BAD_YEAR');
  end if;
  v_from := make_timestamptz(p_year, 1, 1, 0, 0, 0, 'Europe/Paris');
  v_to := make_timestamptz(p_year + 1, 1, 1, 0, 0, 0, 'Europe/Paris');
  select * into co from public.company where id = 1;
  select name into v_zone from public.zones where id = s.zone_id;
  select email into v_email from auth.users where id = s.owner_id;

  return jsonb_build_object(
    'year', p_year,
    'generated_at', now(),
    'shop', jsonb_build_object('name', s.name, 'address', s.address, 'zone', v_zone, 'siret', s.siret, 'email', v_email,
                               'discount_pct', s.discount_pct),
    'terms', jsonb_build_object('version', s.terms_version, 'accepted_at', s.terms_accepted_at,
                                'commission_rate', s.terms_commission_rate, 'discount_min', s.terms_discount_min,
                                'current_version', public.current_terms_version()),
    'seller', jsonb_build_object('legal_name', coalesce(co.legal_name, 'Souki Deals'), 'legal_form', co.legal_form,
                                 'address', co.address, 'siret', co.siret, 'vat_number', co.vat_number),
    -- Factures émises dans l'année
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'number', i.number, 'issued_at', i.issued_at, 'paid_at', i.paid_at,
        'period_start', i.period_start, 'period_end', i.period_end,
        'purchases_count', i.purchases_count, 'sales_cents', i.sales_cents,
        'amount_ht_cents', i.amount_ht_cents, 'vat_rate', i.vat_rate, 'vat_cents', i.vat_cents,
        'amount_ttc_cents', i.amount_ttc_cents) order by i.seq)
      from public.invoices i
      where i.shop_id = s.id and i.issued_at >= v_from and i.issued_at < v_to), '[]'::jsonb),
    -- Achats amenés par l'appli (hors achats annulés)
    'purchases', coalesce((
      select jsonb_agg(jsonb_build_object(
        'date', p.created_at, 'amount_cents', p.amount_cents, 'discount_pct', p.discount_pct,
        'discount_cents', round(p.amount_cents * p.discount_pct / nullif(100 - p.discount_pct, 0))::int,
        'commission_cents', p.commission_cents, 'free', p.free, 'status', p.status,
        'invoice', (select i.number from public.invoices i where i.charge_id = p.charge_id)) order by p.created_at)
      from public.purchases p
      where p.shop_id = s.id and p.status <> 'cancelled' and p.created_at >= v_from and p.created_at < v_to), '[]'::jsonb),
    -- Mois par mois
    'months', (
      select jsonb_agg(jsonb_build_object(
        'month', m,
        'purchases_count', (select count(*) from public.purchases p where p.shop_id = s.id and p.status <> 'cancelled'
                              and p.created_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and p.created_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month'),
        'sales_cents', (select coalesce(sum(p.amount_cents), 0) from public.purchases p where p.shop_id = s.id and p.status <> 'cancelled'
                              and p.created_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and p.created_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month'),
        'discount_cents', (select coalesce(sum(round(p.amount_cents * p.discount_pct / nullif(100 - p.discount_pct, 0))), 0)::int
                              from public.purchases p where p.shop_id = s.id and p.status <> 'cancelled'
                              and p.created_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and p.created_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month'),
        'invoices_count', (select count(*) from public.invoices i where i.shop_id = s.id
                              and i.issued_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and i.issued_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month'),
        'ht_cents', (select coalesce(sum(i.amount_ht_cents), 0) from public.invoices i where i.shop_id = s.id
                              and i.issued_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and i.issued_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month'),
        'vat_cents', (select coalesce(sum(i.vat_cents), 0) from public.invoices i where i.shop_id = s.id
                              and i.issued_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and i.issued_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month'),
        'ttc_cents', (select coalesce(sum(i.amount_ttc_cents), 0) from public.invoices i where i.shop_id = s.id
                              and i.issued_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and i.issued_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month')
      ) order by m)
      from generate_series(1, 12) m),
    -- Commission de l'année pas encore facturée (achats confirmés en attente du prochain prélèvement)
    'unbilled_cents', (select coalesce(sum(p.commission_cents), 0) from public.purchases p
                       where p.shop_id = s.id and p.status = 'confirmed' and not p.free and p.charge_id is null
                         and p.created_at >= v_from and p.created_at < v_to),
    'offered_cents', (select coalesce(sum(p.commission_cents), 0) from public.purchases p
                      where p.shop_id = s.id and p.status in ('pending', 'confirmed') and p.free
                        and p.created_at >= v_from and p.created_at < v_to)
  );
end $$;

revoke execute on function public.current_terms_version(), public.merchant_accept_terms(), public.merchant_year_statement(int)
  from public, anon, authenticated;
grant execute on function public.current_terms_version() to anon, authenticated;
grant execute on function public.merchant_accept_terms(), public.merchant_year_statement(int) to authenticated;

-- >>> 007_scan_inverse.sql
-- =====================================================================
-- SOUKI DEALS — 007 : scan inversé (le client scanne le QR code du magasin)
-- - Chaque commerce a un code fixe (shops.shop_code) imprimé en QR code sur un
--   autocollant collé sur la tablette du comptoir : « SOUKIDEALS:SHOP:<code> ».
-- - En entrant, le client le scanne : sa visite (checkin) apparaît sur la tablette,
--   le commerçant n'a plus qu'à saisir le montant payé. Il ne peut plus « oublier ».
-- - Visite sans montant (expirée, ou « pas d'achat » du commerçant) : on demande au
--   client s'il a acheté. Un « oui » devient un signalement.
-- - Score de méfiance par commerce pour le fondateur.
-- Ce fichier est relançable : il sert aussi de mise à jour (rien n'est effacé).
-- =====================================================================

alter table public.settings add column if not exists checkin_minutes int not null default 120
  check (checkin_minutes between 10 and 1440);

-- Code fixe du commerce (8 caractères sans 0/O/1/I)
create or replace function public.new_shop_code()
returns text language plpgsql volatile as $$
declare
  v_alpha text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code text;
begin
  loop
    v_code := '';
    for i in 1..8 loop
      v_code := v_code || substr(v_alpha, 1 + floor(random() * length(v_alpha))::int, 1);
    end loop;
    exit when not exists (select 1 from public.shops where shop_code = v_code);
  end loop;
  return v_code;
end $$;

alter table public.shops add column if not exists shop_code text;
update public.shops set shop_code = public.new_shop_code() where shop_code is null;
do $$
begin
  alter table public.shops alter column shop_code set not null;
  if not exists (select 1 from pg_constraint where conname = 'shops_shop_code_key') then
    alter table public.shops add constraint shops_shop_code_key unique (shop_code);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'shops_shop_code_check') then
    alter table public.shops add constraint shops_shop_code_check check (shop_code ~ '^[A-Z2-9]{8}$');
  end if;
end $$;

-- Gardien des commerces (version 006) + code fixe donné par le serveur
create or replace function public.guard_shops()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_min numeric; v_rate numeric;
begin
  select discount_min, commission_rate into v_min, v_rate from public.settings where id = 1;
  if (tg_op = 'INSERT' or new.discount_pct is distinct from old.discount_pct) and new.discount_pct < v_min then
    perform public.souki_error(format('La remise doit être d''au moins %s %%.', v_min), 'DISCOUNT_TOO_LOW');
  end if;
  if tg_op = 'INSERT' then
    new.shop_code := public.new_shop_code();
    new.terms_version := public.current_terms_version();
    new.terms_accepted_at := now();
    new.terms_commission_rate := v_rate;
    new.terms_discount_min := v_min;
  else
    new.shop_code := old.shop_code;
    if coalesce(current_setting('souki.accept_terms', true), '') <> 'on' then
      new.terms_version := old.terms_version;
      new.terms_accepted_at := old.terms_accepted_at;
      new.terms_commission_rate := old.terms_commission_rate;
      new.terms_discount_min := old.terms_discount_min;
    end if;
  end if;
  if auth.uid() is null or public.is_admin() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.owner_id := auth.uid();
    new.status := 'pending';
    new.launch_offer := false;
    new.free_until := null;
    new.card_ok := false;
    new.validated_at := null;
    new.created_at := now();
  else
    new.owner_id := old.owner_id;
    new.status := old.status;
    new.launch_offer := old.launch_offer;
    new.free_until := old.free_until;
    new.card_ok := old.card_ok;
    new.validated_at := old.validated_at;
    new.created_at := old.created_at;
  end if;
  return new;
end $$;

-- Visites : le client a scanné le QR code du magasin
--   status : waiting (en attente du montant), done (achat enregistré), expired (sans montant à temps),
--            dismissed (« pas d'achat » selon le commerçant), cancelled (annulée par le client)
--   client_answer : réponse du client pour une visite expirée ou « pas d'achat » (bought / not_bought)
create table if not exists public.checkins (
  id             uuid primary key default gen_random_uuid(),
  shop_id        uuid not null references public.shops(id) on delete cascade,
  client_id      uuid not null references auth.users(id) on delete cascade,
  voucher_id     uuid not null unique references public.vouchers(id) on delete cascade,
  status         text not null default 'waiting' check (status in ('waiting', 'done', 'expired', 'dismissed', 'cancelled')),
  created_at     timestamptz not null default now(),
  expires_at     timestamptz not null,
  closed_at      timestamptz,
  purchase_id    uuid references public.purchases(id) on delete set null,
  client_answer  text check (client_answer in ('bought', 'not_bought')),
  answered_at    timestamptz
);
create index if not exists checkins_shop_idx on public.checkins (shop_id, status, created_at desc);
create index if not exists checkins_client_idx on public.checkins (client_id, created_at desc);
create unique index if not exists checkins_one_waiting on public.checkins (client_id, shop_id) where status = 'waiting';

alter table public.checkins enable row level security;
drop policy if exists checkins_select on public.checkins;
create policy checkins_select on public.checkins for select to authenticated
  using (client_id = auth.uid() or shop_id = public.my_shop_id() or public.is_admin());
grant select on public.checkins to authenticated;

-- Un achat enregistré (par le scan de la visite ou celui du bon) clôt la visite
create or replace function public.purchases_close_checkin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.checkins set status = 'done', closed_at = now(), purchase_id = new.id
  where voucher_id = new.voucher_id and status in ('waiting', 'expired', 'dismissed');
  return new;
end $$;
drop trigger if exists purchases_checkin on public.purchases;
create trigger purchases_checkin after insert on public.purchases
  for each row execute function public.purchases_close_checkin();

-- Prénom affiché sur la tablette (pas le nom complet)
create or replace function public.first_name(p_uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(split_part(btrim(p.full_name), ' ', 1), ''), 'Client')
  from (select 1) x left join public.profiles p on p.id = p_uid;
$$;

-- Client : il scanne le QR code du magasin
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
  select * into st from public.settings where id = 1;
  -- QR code complet ou code seul
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
  -- Le bon d'une visite terminée ne resert pas
  update public.vouchers vo set status = 'expired'
  where vo.client_id = v_uid and vo.shop_id = s.id and vo.status = 'active'
    and exists (select 1 from public.checkins ck where ck.voucher_id = vo.id and ck.status <> 'waiting');
  select * into c from public.checkins where client_id = v_uid and shop_id = s.id and status = 'waiting';
  if not found then
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

create or replace function public.client_cancel_checkin(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.checkins;
begin
  perform public.require_login();
  update public.checkins set status = 'cancelled', closed_at = now()
  where id = p_id and client_id = auth.uid() and status = 'waiting'
  returning * into c;
  if not found then
    perform public.souki_error('Visite introuvable ou déjà terminée.', 'NOT_FOUND');
  end if;
  update public.vouchers set status = 'cancelled' where id = c.voucher_id and status = 'active';
end $$;

-- Client : visite sans achat enregistré → « avez-vous acheté ? »
create or replace function public.client_answer_checkin(p_id uuid, p_bought boolean)
returns void language plpgsql security definer set search_path = public as $$
declare c public.checkins;
begin
  perform public.require_login();
  select * into c from public.checkins where id = p_id and client_id = auth.uid() for update;
  if not found or c.status not in ('expired', 'dismissed') or c.client_answer is not null then
    perform public.souki_error('Visite introuvable ou déjà traitée.', 'NOT_FOUND');
  end if;
  if p_bought is null then
    perform public.souki_error('Répondez oui ou non.', 'BAD_ANSWER');
  end if;
  update public.checkins set client_answer = case when p_bought then 'bought' else 'not_bought' end, answered_at = now()
  where id = p_id;
  if p_bought then
    insert into public.reports (user_id, shop_id, kind, body)
    values (auth.uid(), c.shop_id, 'achat',
            format('Achat sans scan : le client dit avoir acheté lors de sa visite du %s, mais le montant n''a pas été saisi.',
                   to_char(c.created_at at time zone 'Europe/Paris', 'DD/MM/YYYY à HH24:MI')));
  end if;
end $$;

-- Commerçant : clients présents (visites en attente)
drop function if exists public.merchant_checkins();
create function public.merchant_checkins()
returns table (id uuid, code text, first_name text, created_at timestamptz, expires_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_shop uuid := public.my_shop_id();
begin
  perform public.require_login();
  if v_shop is null then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  return query
    select c.id, v.code, public.first_name(c.client_id), c.created_at, c.expires_at
    from public.checkins c join public.vouchers v on v.id = c.voucher_id
    where c.shop_id = v_shop and c.status = 'waiting' and c.expires_at > now()
    order by c.created_at;
end $$;

-- Commerçant : il saisit le montant payé (remise déduite) pour la visite
create or replace function public.merchant_complete_checkin(p_id uuid, p_amount_cents int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c public.checkins; v_code text;
begin
  perform public.require_login();
  select * into c from public.checkins where id = p_id and shop_id = public.my_shop_id() for update;
  if not found then
    perform public.souki_error('Visite introuvable.', 'NOT_FOUND');
  end if;
  if c.status <> 'waiting' then
    perform public.souki_error('Cette visite est déjà terminée.', 'ALREADY_DONE');
  end if;
  select code into v_code from public.vouchers where id = c.voucher_id;
  -- Mêmes règles que le scan du bon (validation du commerce, montant, délai…)
  return public.merchant_scan(v_code, p_amount_cents);
end $$;

-- Commerçant : le client est reparti sans acheter (le client pourra le confirmer ou non)
create or replace function public.merchant_dismiss_checkin(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.checkins;
begin
  perform public.require_login();
  update public.checkins set status = 'dismissed', closed_at = now()
  where id = p_id and shop_id = public.my_shop_id() and status = 'waiting'
  returning * into c;
  if not found then
    perform public.souki_error('Visite introuvable ou déjà terminée.', 'NOT_FOUND');
  end if;
  update public.vouchers set status = 'cancelled' where id = c.voucher_id and status = 'active';
end $$;

-- Fondateur : score de méfiance par commerce (90 derniers jours)
--   level : ok, orange, rouge
create or replace function public.admin_shop_scores()
returns table (shop_id uuid, name text, visits int, done int, without_amount int, claimed int,
               vouchers int, vouchers_used int, done_rate int, level text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.require_admin();
  return query
  with c as (
    select c.shop_id,
           count(*) filter (where c.status <> 'cancelled')::int as visits,
           count(*) filter (where c.status = 'done')::int as done,
           count(*) filter (where c.status in ('expired', 'dismissed'))::int as without_amount,
           count(*) filter (where c.client_answer = 'bought')::int as claimed
    from public.checkins c where c.created_at > now() - interval '90 days' group by c.shop_id
  ), v as (
    select v.shop_id, count(*) filter (where v.status <> 'cancelled')::int as vouchers,
           count(*) filter (where v.status = 'used')::int as used
    from public.vouchers v where v.created_at > now() - interval '90 days' group by v.shop_id
  )
  select s.id, s.name, coalesce(c.visits, 0), coalesce(c.done, 0), coalesce(c.without_amount, 0), coalesce(c.claimed, 0),
         coalesce(v.vouchers, 0), coalesce(v.used, 0),
         case when coalesce(c.visits, 0) = 0 then null else round(100.0 * c.done / c.visits)::int end,
         case
           when coalesce(c.claimed, 0) >= 3 or (coalesce(c.visits, 0) >= 5 and c.done * 100 < c.visits * 40) then 'rouge'
           when coalesce(c.claimed, 0) >= 1 or (coalesce(c.visits, 0) >= 5 and c.done * 100 < c.visits * 60) then 'orange'
           else 'ok'
         end
  from public.shops s
  left join c on c.shop_id = s.id
  left join v on v.shop_id = s.id
  where s.status <> 'pending'
  order by case
             when coalesce(c.claimed, 0) >= 3 or (coalesce(c.visits, 0) >= 5 and c.done * 100 < c.visits * 40) then 0
             when coalesce(c.claimed, 0) >= 1 or (coalesce(c.visits, 0) >= 5 and c.done * 100 < c.visits * 60) then 1
             else 2 end,
           coalesce(c.claimed, 0) desc, s.name;
end $$;

-- Tâches automatiques : en plus, visites sans montant à temps → expirées
create or replace function public.souki_deals_tick()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_hours int;
  v_confirmed int;
  v_expired int;
  v_charges int;
  v_visits int;
  v_retry int := 0;
  r record;
begin
  select confirm_hours into v_hours from public.settings where id = 1;
  update public.purchases set status = 'confirmed', confirmed_at = now()
  where status = 'pending' and created_at < now() - make_interval(hours => coalesce(v_hours, 24));
  get diagnostics v_confirmed = row_count;
  update public.checkins set status = 'expired', closed_at = now() where status = 'waiting' and expires_at < now();
  get diagnostics v_visits = row_count;
  update public.vouchers vo set status = 'expired'
  where vo.status = 'active' and exists (select 1 from public.checkins ck where ck.voucher_id = vo.id and ck.status = 'expired');
  update public.vouchers set status = 'expired' where status = 'active' and expires_at < now();
  get diagnostics v_expired = row_count;
  v_charges := public.close_week(public.week_of(now()) - 7);
  update public.invoices set email_status = 'failed',
    email_error = coalesce(email_error, 'Envoi impossible après 5 essais.')
  where email_status = 'pending' and email_attempts >= 5 and email_last_try < now() - interval '30 minutes';
  for r in
    select id from public.invoices
    where email_status = 'pending' and email_attempts < 5
      and (email_last_try is null or email_last_try < now() - interval '30 minutes')
    order by seq limit 20
  loop
    perform public.send_invoice(r.id);
    v_retry := v_retry + 1;
  end loop;
  return jsonb_build_object('confirmed', v_confirmed, 'expired', v_expired, 'charges', v_charges,
                            'visits_expired', v_visits, 'invoice_retries', v_retry);
end $$;

-- Qui suis-je ? (+ visites sans achat enregistré auxquelles répondre)
create or replace function public.whoami()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('user_id', null, 'is_admin', false);
  end if;
  return jsonb_build_object(
    'user_id', v_uid,
    'email', (select email from auth.users where id = v_uid),
    'is_admin', public.is_admin(),
    'profile', (select jsonb_build_object('full_name', p.full_name, 'phone', p.phone, 'lang', p.lang)
                from public.profiles p where p.id = v_uid),
    'shop', (select jsonb_build_object('id', s.id, 'name', s.name, 'status', s.status,
                                       'launch_offer', s.launch_offer, 'free_until', s.free_until,
                                       'blocked', public.shop_is_blocked(s.id))
             from public.shops s where s.owner_id = v_uid),
    'pending_purchases', (select count(*) from public.purchases where client_id = v_uid and status = 'pending'),
    'visits_to_answer', (select count(*) from public.checkins
                         where client_id = v_uid and status in ('expired', 'dismissed') and client_answer is null
                           and created_at > now() - interval '7 days')
  );
end $$;

revoke execute on function
  public.new_shop_code(), public.purchases_close_checkin(), public.first_name(uuid),
  public.client_checkin(text), public.client_cancel_checkin(uuid), public.client_answer_checkin(uuid, boolean),
  public.merchant_checkins(), public.merchant_complete_checkin(uuid, int), public.merchant_dismiss_checkin(uuid),
  public.admin_shop_scores()
from public, anon, authenticated;
grant execute on function
  public.client_checkin(text), public.client_cancel_checkin(uuid), public.client_answer_checkin(uuid, boolean),
  public.merchant_checkins(), public.merchant_complete_checkin(uuid, int), public.merchant_dismiss_checkin(uuid),
  public.admin_shop_scores()
to authenticated;

-- >>> 008_inscrits.sql
-- =====================================================================
-- SOUKI DEALS — 008 : nombre d'inscrits (particuliers et commerçants)
-- Pour le fondateur : comptes vérifiés (e-mail confirmé), sans compter le fondateur.
-- Particulier = compte sans commerce. Actif = a pris un bon ou scanné un magasin
-- dans les 30 derniers jours.
-- Ce fichier est relançable : il sert aussi de mise à jour (rien n'est effacé).
-- =====================================================================

create or replace function public.admin_members()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_today timestamptz := (public.paris_today()::timestamp) at time zone 'Europe/Paris';
  v_week timestamptz := (public.week_of(now())::timestamp) at time zone 'Europe/Paris';
  v_month timestamptz := (date_trunc('month', now() at time zone 'Europe/Paris')) at time zone 'Europe/Paris';
begin
  perform public.require_admin();
  return (
    with u as (
      select au.id, au.created_at,
             exists (select 1 from public.shops s where s.owner_id = au.id) as has_shop
      from auth.users au
      where au.email_confirmed_at is not null
        and lower(coalesce(au.email, '')) <> 'demba.sacko20@gmail.com'
    ), c as (select * from u where not has_shop),
    act as (
      select distinct client_id as id from public.vouchers where created_at > now() - interval '30 days'
      union
      select distinct client_id from public.checkins where created_at > now() - interval '30 days'
    ),
    weeks as (
      select generate_series(public.week_of(now()) - 7 * 11, public.week_of(now()), interval '7 days')::date as w
    )
    select jsonb_build_object(
      'clients', jsonb_build_object(
        'total', (select count(*) from c),
        'today', (select count(*) from c where created_at >= v_today),
        'week', (select count(*) from c where created_at >= v_week),
        'month', (select count(*) from c where created_at >= v_month),
        'active_30d', (select count(*) from c where id in (select id from act)),
        'unconfirmed', (select count(*) from auth.users au where au.email_confirmed_at is null)
      ),
      'shops', jsonb_build_object(
        'total', (select count(*) from public.shops),
        'active', (select count(*) from public.shops where status = 'active'),
        'pending', (select count(*) from public.shops where status = 'pending'),
        'suspended', (select count(*) from public.shops where status = 'suspended'),
        'week', (select count(*) from public.shops where created_at >= v_week),
        'month', (select count(*) from public.shops where created_at >= v_month),
        'launch_offer', (select count(*) from public.shops where launch_offer)
      ),
      'by_zone', coalesce((
        select jsonb_agg(jsonb_build_object('zone', z.name, 'shops', z.shops, 'active', z.active) order by z.sort)
        from (select zn.name, zn.sort,
                     count(s.id) as shops, count(s.id) filter (where s.status = 'active') as active
              from public.zones zn left join public.shops s on s.zone_id = zn.id
              group by zn.id) z
        where z.shops > 0), '[]'::jsonb),
      'by_kind', coalesce((
        select jsonb_agg(jsonb_build_object('kind', k.kind, 'shops', k.n) order by k.n desc)
        from (select kind, count(*) as n from public.shops group by kind) k), '[]'::jsonb),
      'weeks', (
        select jsonb_agg(jsonb_build_object(
          'week', w.w,
          'clients', (select count(*) from c where c.created_at >= (w.w::timestamp at time zone 'Europe/Paris')
                                                 and c.created_at < ((w.w + 7)::timestamp at time zone 'Europe/Paris')),
          'shops', (select count(*) from public.shops s where s.created_at >= (w.w::timestamp at time zone 'Europe/Paris')
                                                          and s.created_at < ((w.w + 7)::timestamp at time zone 'Europe/Paris'))
        ) order by w.w)
        from weeks w)
    )
  );
end $$;

revoke execute on function public.admin_members() from public, anon, authenticated;
grant execute on function public.admin_members() to authenticated;

-- >>> 009_promos.sql
-- =====================================================================
-- SOUKI DEALS — 009 : promotions
-- 1. Offre de bienvenue payée par Souki Deals : -10 € sur le premier achat dès 30 €,
--    dans la limite d'un nombre de places (budget). Le commerçant la déduit en caisse ;
--    Souki Deals la lui rembourse en la déduisant de sa commission de la semaine.
--    Si la semaine est en faveur du commerçant (offre de lancement…), le prélèvement est
--    négatif : Souki Deals lui doit la somme (virement, marqué « payé » par le fondateur).
-- 2. Promos au choix du commerçant, à ses frais : offre flash (produit à -X %) et
--    produit offert dès un montant. 3 promos actives au plus.
-- Ce fichier est relançable : il sert aussi de mise à jour (rien n'est effacé).
-- =====================================================================

-- ---------- Réglages de la bienvenue ----------
alter table public.settings add column if not exists welcome_enabled boolean not null default true;
alter table public.settings add column if not exists welcome_amount_cents int not null default 1000 check (welcome_amount_cents between 100 and 5000);
alter table public.settings add column if not exists welcome_min_cents int not null default 3000 check (welcome_min_cents between 0 and 100000);
alter table public.settings add column if not exists welcome_slots int not null default 100 check (welcome_slots between 0 and 100000);

alter table public.purchases add column if not exists welcome_cents int not null default 0 check (welcome_cents >= 0);

-- Prélèvement = commission − bienvenue à rembourser (peut être négatif : Souki Deals doit la somme)
alter table public.charges add column if not exists commission_cents int;
alter table public.charges add column if not exists welcome_cents int not null default 0;
update public.charges set commission_cents = amount_cents where commission_cents is null;
alter table public.charges drop constraint if exists charges_amount_cents_check;

alter table public.invoices add column if not exists welcome_cents int not null default 0;
alter table public.invoices add column if not exists net_cents int;

-- Conditions commerçant : nouvelle version (offre de bienvenue)
create or replace function public.current_terms_version()
returns text language sql immutable as $$ select '2026-10-13'::text $$;

-- Montant de bienvenue auquel ce client a droit (0 s'il n'y a plus droit)
create or replace function public.welcome_for(p_client uuid)
returns int language plpgsql stable security definer set search_path = public as $$
declare
  st public.settings;
  v_phone text;
begin
  select * into st from public.settings where id = 1;
  if not st.welcome_enabled or st.welcome_amount_cents <= 0 then
    return 0;
  end if;
  if (select count(distinct client_id) from public.purchases where welcome_cents > 0 and status <> 'cancelled') >= st.welcome_slots then
    return 0;
  end if;
  if exists (select 1 from public.purchases where client_id = p_client and welcome_cents > 0 and status <> 'cancelled') then
    return 0;
  end if;
  -- Un seul bienvenue par numéro de téléphone (contre les comptes en double)
  select regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g') into v_phone from public.profiles where id = p_client;
  if coalesce(v_phone, '') <> '' and exists (
       select 1 from public.purchases pu join public.profiles pr on pr.id = pu.client_id
       where pu.welcome_cents > 0 and pu.status <> 'cancelled' and pu.client_id <> p_client
         and regexp_replace(coalesce(pr.phone, ''), '[^0-9]', '', 'g') = v_phone) then
    return 0;
  end if;
  return st.welcome_amount_cents;
end $$;

-- Client : son offre de bienvenue
create or replace function public.client_welcome()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st public.settings; v int;
begin
  perform public.require_login();
  select * into st from public.settings where id = 1;
  v := case when exists (select 1 from public.shops where owner_id = auth.uid()) then 0 else public.welcome_for(auth.uid()) end;
  return jsonb_build_object('amount_cents', v, 'min_cents', st.welcome_min_cents);
end $$;

-- Commerçant : avant de saisir le montant, ce qu'il doit déduire pour ce bon
create or replace function public.merchant_voucher_info(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v public.vouchers; st public.settings; v_shop uuid := public.my_shop_id();
begin
  perform public.require_login();
  select * into st from public.settings where id = 1;
  select * into v from public.vouchers where code = upper(btrim(coalesce(p_code, '')));
  if not found or v_shop is null or v.shop_id <> v_shop then
    perform public.souki_error('Bon introuvable : vérifiez le code.', 'NOT_FOUND');
  end if;
  return jsonb_build_object('first_name', public.first_name(v.client_id), 'status', v.status,
                            'welcome_cents', public.welcome_for(v.client_id), 'welcome_min_cents', st.welcome_min_cents);
end $$;

create or replace function public.merchant_scan(p_code text, p_amount_cents int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  st public.settings;
  s public.shops;
  v public.vouchers;
  v_free boolean;
  v_commission int;
  v_id uuid;
  v_welcome int := 0;
begin
  perform public.require_login();
  select * into st from public.settings where id = 1;
  select * into s from public.shops where owner_id = auth.uid();
  if not found then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  if s.status <> 'active' then
    perform public.souki_error('Votre commerce n''est pas encore validé.', 'SHOP_NOT_ACTIVE');
  end if;
  select * into v from public.vouchers where code = upper(btrim(coalesce(p_code, ''))) for update;
  if not found then
    perform public.souki_error('Bon introuvable : vérifiez le code.', 'NOT_FOUND');
  end if;
  if v.shop_id <> s.id then
    perform public.souki_error('Ce bon est pour un autre commerce.', 'WRONG_SHOP');
  end if;
  if v.status = 'used' then
    perform public.souki_error('Ce bon a déjà été utilisé.', 'ALREADY_USED');
  end if;
  if v.status <> 'active' or v.expires_at < now() then
    perform public.souki_error('Ce bon a expiré.', 'EXPIRED');
  end if;
  if p_amount_cents is null or p_amount_cents < 1 or p_amount_cents > st.max_purchase_cents then
    perform public.souki_error(format('Montant invalide (maximum %s €).', st.max_purchase_cents / 100), 'BAD_AMOUNT');
  end if;
  if exists (select 1 from public.purchases
             where client_id = v.client_id and shop_id = s.id and status <> 'cancelled'
               and created_at > now() - make_interval(mins => st.cooldown_minutes)) then
    perform public.souki_error('Ce client a déjà un achat compté ici il y a peu de temps.', 'TOO_SOON');
  end if;

  -- Offre de bienvenue (payée par Souki Deals) : un seul achat par client, dans la limite des places
  perform pg_advisory_xact_lock(hashtext('welcome:' || v.client_id::text));
  perform pg_advisory_xact_lock(hashtext('welcome-slots'));
  v_welcome := public.welcome_for(v.client_id);
  if v_welcome > 0 and p_amount_cents + v_welcome < st.welcome_min_cents then
    v_welcome := 0;
  end if;
  v_free := s.free_until is not null and public.paris_today() <= s.free_until;
  -- Commission sur le montant réel de l'achat (payé par le client + bienvenue remboursée)
  v_commission := round((p_amount_cents + v_welcome) * st.commission_rate / 100);
  insert into public.purchases (voucher_id, shop_id, client_id, amount_cents, discount_pct, commission_rate,
                                commission_cents, free, scanned_by, week_start, welcome_cents)
  values (v.id, s.id, v.client_id, p_amount_cents, s.discount_pct, st.commission_rate,
          v_commission, v_free, auth.uid(), public.week_of(now()), v_welcome)
  returning id into v_id;
  update public.vouchers set status = 'used' where id = v.id;
  return jsonb_build_object('purchase_id', v_id, 'amount_cents', p_amount_cents,
                            'commission_cents', v_commission, 'free', v_free, 'welcome_cents', v_welcome);
end $$;

create or replace function public.merchant_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  s public.shops;
  v_today timestamptz := (public.paris_today()::timestamp) at time zone 'Europe/Paris';
  v_week timestamptz := (public.week_of(now())::timestamp) at time zone 'Europe/Paris';
  v_month timestamptz := (date_trunc('month', now() at time zone 'Europe/Paris')) at time zone 'Europe/Paris';
begin
  select * into s from public.shops where owner_id = auth.uid();
  if not found then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  return jsonb_build_object(
    'today_cents', (select coalesce(sum(amount_cents), 0) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed') and created_at >= v_today),
    'today_count', (select count(*) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed') and created_at >= v_today),
    'week_cents', (select coalesce(sum(amount_cents), 0) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed') and created_at >= v_week),
    'week_count', (select count(*) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed') and created_at >= v_week),
    'month_cents', (select coalesce(sum(amount_cents), 0) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed') and created_at >= v_month),
    'month_count', (select count(*) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed') and created_at >= v_month),
    'commission_due_cents', (select coalesce(sum(commission_cents) filter (where not free), 0) - coalesce(sum(welcome_cents), 0)
                             from public.purchases where shop_id = s.id and status = 'confirmed' and charge_id is null),
    'commission_gross_cents', (select coalesce(sum(commission_cents), 0) from public.purchases where shop_id = s.id and status = 'confirmed' and not free and charge_id is null),
    'welcome_credit_cents', (select coalesce(sum(welcome_cents), 0) from public.purchases where shop_id = s.id and status = 'confirmed' and charge_id is null),
    'commission_offered_cents', (select coalesce(sum(commission_cents), 0) from public.purchases where shop_id = s.id and status = 'confirmed' and free),
    'clients_count', (select count(distinct client_id) from public.purchases where shop_id = s.id and status in ('pending', 'confirmed')),
    'status', s.status,
    'launch_offer', s.launch_offer,
    'free_until', s.free_until,
    'card_ok', s.card_ok,
    'blocked', public.shop_is_blocked(s.id),
    'discount_pct', s.discount_pct
  );
end $$;

-- Clients présents : + la bienvenue à déduire
drop function if exists public.merchant_checkins();
create function public.merchant_checkins()
returns table (id uuid, code text, first_name text, created_at timestamptz, expires_at timestamptz, welcome_cents int, welcome_min_cents int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_shop uuid := public.my_shop_id();
begin
  perform public.require_login();
  if v_shop is null then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  return query
    select c.id, v.code, public.first_name(c.client_id), c.created_at, c.expires_at,
           public.welcome_for(c.client_id), (select welcome_min_cents from public.settings where settings.id = 1)
    from public.checkins c join public.vouchers v on v.id = c.voucher_id
    where c.shop_id = v_shop and c.status = 'waiting' and c.expires_at > now()
    order by c.created_at;
end $$;

-- Commerce masqué : seulement pour un prélèvement à payer par le commerçant
create or replace function public.shop_is_blocked(p_shop uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.charges c
    where c.shop_id = p_shop and c.amount_cents > 0
      and (c.status = 'failed' or (c.status = 'pending' and c.created_at < now() - interval '7 days'))
  );
$$;

-- Prélèvement de la semaine : commission − bienvenue
create or replace function public.close_week(p_week date)
returns int language plpgsql security definer set search_path = public as $$
declare
  r record;
  v_charge uuid;
  v_count int := 0;
begin
  for r in
    select shop_id,
           coalesce(sum(commission_cents) filter (where not free), 0)::int as comm,
           coalesce(sum(welcome_cents), 0)::int as welcome
    from public.purchases
    where status = 'confirmed' and charge_id is null and week_start <= p_week
      and ((not free and commission_cents > 0) or welcome_cents > 0)
    group by shop_id
  loop
    continue when r.comm = 0 and r.welcome = 0;
    v_charge := null;
    -- Un prélèvement déjà payé, refusé ou offert n'est plus modifié
    insert into public.charges (shop_id, week_start, amount_cents, commission_cents, welcome_cents)
    values (r.shop_id, p_week, r.comm - r.welcome, r.comm, r.welcome)
    on conflict (shop_id, week_start) do update set
      amount_cents = public.charges.amount_cents + excluded.amount_cents,
      commission_cents = coalesce(public.charges.commission_cents, 0) + excluded.commission_cents,
      welcome_cents = public.charges.welcome_cents + excluded.welcome_cents
      where public.charges.status = 'pending'
    returning id into v_charge;
    continue when v_charge is null;
    update public.purchases set charge_id = v_charge
    where shop_id = r.shop_id and status = 'confirmed' and charge_id is null and week_start <= p_week
      and ((not free and commission_cents > 0) or welcome_cents > 0);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;

-- Facture : sur la commission ; la bienvenue remboursée figure en déduction
create or replace function public.issue_invoice(p_charge uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  c public.charges;
  co public.company;
  s public.shops;
  v_id uuid;
  v_seq int;
  v_comm int;
  v_ht int;
  v_vat int;
  v_email text;
  v_zone text;
  v_start date;
  v_count int;
  v_sales int;
  v_rate numeric;
begin
  select * into c from public.charges where id = p_charge;
  v_comm := coalesce(c.commission_cents, c.amount_cents);
  if c.id is null or c.status <> 'paid' or coalesce(v_comm, 0) <= 0 then
    return null;
  end if;
  select id into v_id from public.invoices where charge_id = p_charge;
  if found then
    return v_id;
  end if;
  if not public.company_ready() then
    return null;
  end if;
  select * into co from public.company where id = 1 for update;
  v_seq := co.next_number;
  select * into s from public.shops where id = c.shop_id;
  select u.email into v_email from auth.users u where u.id = s.owner_id and u.email_confirmed_at is not null;
  select name into v_zone from public.zones where id = s.zone_id;
  select min(week_start), count(*), coalesce(sum(amount_cents), 0), max(commission_rate)
    into v_start, v_count, v_sales, v_rate
  from public.purchases where charge_id = c.id;
  v_ht := round(v_comm * 100.0 / (100 + co.vat_rate));
  v_vat := v_comm - v_ht;

  insert into public.invoices (number, seq, shop_id, charge_id, paid_at, period_start, period_end,
    purchases_count, sales_cents, commission_rate, amount_ht_cents, vat_rate, vat_cents, amount_ttc_cents,
    welcome_cents, net_cents, seller, buyer, email_to, email_status)
  values (
    format('%s-%s-%s', co.invoice_prefix, to_char(now() at time zone 'Europe/Paris', 'YYYY'), lpad(v_seq::text, 6, '0')),
    v_seq, c.shop_id, c.id, coalesce(c.paid_at, now()),
    least(coalesce(v_start, c.week_start), c.week_start), c.week_start + 6,
    v_count, v_sales, v_rate, v_ht, co.vat_rate, v_vat, v_comm,
    coalesce(c.welcome_cents, 0), c.amount_cents,
    jsonb_build_object('legal_name', co.legal_name, 'legal_form', co.legal_form, 'capital', co.capital,
      'address', co.address, 'siret', co.siret, 'rcs', co.rcs, 'vat_number', co.vat_number, 'email', co.email),
    jsonb_build_object('name', s.name, 'address', s.address, 'zone', v_zone, 'siret', s.siret, 'email', v_email),
    v_email,
    case when v_email is null then 'failed' else 'pending' end
  )
  returning id into v_id;
  update public.company set next_number = v_seq + 1 where id = 1;
  if v_email is null then
    update public.invoices set email_error = 'Aucune adresse e-mail vérifiée pour ce commerce.' where id = v_id;
  else
    perform public.send_invoice(v_id);
  end if;
  return v_id;
end $$;

create or replace function public.issue_missing_invoices()
returns int language plpgsql security definer set search_path = public as $$
declare r record; v_n int := 0;
begin
  if not public.company_ready() then
    return 0;
  end if;
  for r in
    select c.id from public.charges c
    where c.status = 'paid' and coalesce(c.commission_cents, c.amount_cents) > 0
      and not exists (select 1 from public.invoices i where i.charge_id = c.id)
    order by c.paid_at nulls first, c.created_at
  loop
    if public.issue_invoice(r.id) is not null then
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $$;

create or replace function public.merchant_year_statement(p_year int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  s public.shops;
  co public.company;
  v_from timestamptz;
  v_to timestamptz;
  v_zone text;
  v_email text;
begin
  perform public.require_login();
  select * into s from public.shops where owner_id = auth.uid();
  if not found then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  if p_year is null or p_year not between 2024 and 2100 then
    perform public.souki_error('Année invalide.', 'BAD_YEAR');
  end if;
  v_from := make_timestamptz(p_year, 1, 1, 0, 0, 0, 'Europe/Paris');
  v_to := make_timestamptz(p_year + 1, 1, 1, 0, 0, 0, 'Europe/Paris');
  select * into co from public.company where id = 1;
  select name into v_zone from public.zones where id = s.zone_id;
  select email into v_email from auth.users where id = s.owner_id;

  return jsonb_build_object(
    'year', p_year,
    'generated_at', now(),
    'shop', jsonb_build_object('name', s.name, 'address', s.address, 'zone', v_zone, 'siret', s.siret, 'email', v_email,
                               'discount_pct', s.discount_pct),
    'terms', jsonb_build_object('version', s.terms_version, 'accepted_at', s.terms_accepted_at,
                                'commission_rate', s.terms_commission_rate, 'discount_min', s.terms_discount_min,
                                'current_version', public.current_terms_version()),
    'seller', jsonb_build_object('legal_name', coalesce(co.legal_name, 'Souki Deals'), 'legal_form', co.legal_form,
                                 'address', co.address, 'siret', co.siret, 'vat_number', co.vat_number),
    -- Factures émises dans l'année
    'invoices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'number', i.number, 'issued_at', i.issued_at, 'paid_at', i.paid_at,
        'period_start', i.period_start, 'period_end', i.period_end,
        'purchases_count', i.purchases_count, 'sales_cents', i.sales_cents,
        'amount_ht_cents', i.amount_ht_cents, 'vat_rate', i.vat_rate, 'vat_cents', i.vat_cents,
        'amount_ttc_cents', i.amount_ttc_cents) order by i.seq)
      from public.invoices i
      where i.shop_id = s.id and i.issued_at >= v_from and i.issued_at < v_to), '[]'::jsonb),
    -- Achats amenés par l'appli (hors achats annulés)
    'purchases', coalesce((
      select jsonb_agg(jsonb_build_object(
        'date', p.created_at, 'amount_cents', p.amount_cents, 'discount_pct', p.discount_pct,
        'discount_cents', round(p.amount_cents * p.discount_pct / nullif(100 - p.discount_pct, 0))::int,
        'commission_cents', p.commission_cents, 'welcome_cents', p.welcome_cents, 'free', p.free, 'status', p.status,
        'invoice', (select i.number from public.invoices i where i.charge_id = p.charge_id)) order by p.created_at)
      from public.purchases p
      where p.shop_id = s.id and p.status <> 'cancelled' and p.created_at >= v_from and p.created_at < v_to), '[]'::jsonb),
    -- Mois par mois
    'months', (
      select jsonb_agg(jsonb_build_object(
        'month', m,
        'purchases_count', (select count(*) from public.purchases p where p.shop_id = s.id and p.status <> 'cancelled'
                              and p.created_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and p.created_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month'),
        'sales_cents', (select coalesce(sum(p.amount_cents), 0) from public.purchases p where p.shop_id = s.id and p.status <> 'cancelled'
                              and p.created_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and p.created_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month'),
        'discount_cents', (select coalesce(sum(round(p.amount_cents * p.discount_pct / nullif(100 - p.discount_pct, 0))), 0)::int
                              from public.purchases p where p.shop_id = s.id and p.status <> 'cancelled'
                              and p.created_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and p.created_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month'),
        'invoices_count', (select count(*) from public.invoices i where i.shop_id = s.id
                              and i.issued_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and i.issued_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month'),
        'ht_cents', (select coalesce(sum(i.amount_ht_cents), 0) from public.invoices i where i.shop_id = s.id
                              and i.issued_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and i.issued_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month'),
        'vat_cents', (select coalesce(sum(i.vat_cents), 0) from public.invoices i where i.shop_id = s.id
                              and i.issued_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and i.issued_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month'),
        'ttc_cents', (select coalesce(sum(i.amount_ttc_cents), 0) from public.invoices i where i.shop_id = s.id
                              and i.issued_at >= make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris')
                              and i.issued_at < make_timestamptz(p_year, m, 1, 0, 0, 0, 'Europe/Paris') + interval '1 month')
      ) order by m)
      from generate_series(1, 12) m),
    -- Offre de bienvenue Souki Deals remboursée au commerçant
    'welcome_cents', (select coalesce(sum(p.welcome_cents), 0) from public.purchases p
                      where p.shop_id = s.id and p.status <> 'cancelled'
                        and p.created_at >= v_from and p.created_at < v_to),
    -- Commission de l'année pas encore facturée (achats confirmés en attente du prochain prélèvement)
    'unbilled_cents', (select coalesce(sum(p.commission_cents), 0) from public.purchases p
                       where p.shop_id = s.id and p.status = 'confirmed' and not p.free and p.charge_id is null
                         and p.created_at >= v_from and p.created_at < v_to),
    'offered_cents', (select coalesce(sum(p.commission_cents), 0) from public.purchases p
                      where p.shop_id = s.id and p.status in ('pending', 'confirmed') and p.free
                        and p.created_at >= v_from and p.created_at < v_to)
  );
end $$;

-- ---------- Promos du commerçant ----------
create table if not exists public.promos (
  id            bigserial primary key,
  shop_id       uuid not null references public.shops(id) on delete cascade,
  kind          text not null check (kind in ('flash', 'gift')),
  title         text not null check (char_length(title) between 2 and 60),
  discount_pct  numeric(5,2) check (discount_pct is null or discount_pct between 0 and 90),
  min_cents     int check (min_cents is null or min_cents between 0 and 1000000),
  starts_at     timestamptz not null default now(),
  ends_at       timestamptz not null,
  active        boolean not null default true,
  created_at    timestamptz not null default now()
);
create index if not exists promos_shop_idx on public.promos (shop_id, active, ends_at);

alter table public.promos enable row level security;
drop policy if exists promos_select on public.promos;
create policy promos_select on public.promos for select
  using ((active and ends_at > now() and public.shop_is_visible(shop_id)) or shop_id = public.my_shop_id() or public.is_admin());
grant select on public.promos to anon, authenticated;

-- Créer une promo. Flash : produit à -X % jusqu'à ce soir (p_days = 0) ou quelques jours.
-- Cadeau : « <title> offert dès <min> € », valable p_days jours.
create or replace function public.merchant_save_promo(p_kind text, p_title text, p_pct numeric, p_min_cents int, p_days int)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  s public.shops;
  v_end timestamptz;
  v_id bigint;
begin
  perform public.require_login();
  select * into s from public.shops where owner_id = auth.uid();
  if not found then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  if s.status <> 'active' then
    perform public.souki_error('Votre commerce n''est pas encore validé.', 'SHOP_NOT_ACTIVE');
  end if;
  if p_kind not in ('flash', 'gift') then
    perform public.souki_error('Type de promo inconnu.', 'BAD_PROMO');
  end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 2 and 60 then
    perform public.souki_error('Indiquez le produit (2 à 60 caractères).', 'BAD_PROMO');
  end if;
  if p_kind = 'flash' and (p_pct is null or p_pct < 10 or p_pct > 90 or p_pct <= s.discount_pct) then
    perform public.souki_error(format('Offre flash : entre 10 %% et 90 %%, et plus que votre remise de %s %%.', s.discount_pct), 'BAD_PROMO');
  end if;
  if p_kind = 'gift' and (p_min_cents is null or p_min_cents < 100 or p_min_cents > 100000) then
    perform public.souki_error('Indiquez le montant d''achat minimum (1 à 1 000 €).', 'BAD_PROMO');
  end if;
  if p_days is null or p_days not between 0 and 30 or (p_kind = 'flash' and p_days > 7) then
    perform public.souki_error('Durée invalide.', 'BAD_PROMO');
  end if;
  if (select count(*) from public.promos where shop_id = s.id and active and ends_at > now()) >= 3 then
    perform public.souki_error('3 promos en cours au maximum : arrêtez-en une d''abord.', 'TOO_MANY');
  end if;
  -- Fin : ce soir à minuit (heure de Paris) + p_days jours
  v_end := ((public.paris_today() + 1 + p_days)::timestamp) at time zone 'Europe/Paris';
  insert into public.promos (shop_id, kind, title, discount_pct, min_cents, ends_at)
  values (s.id, p_kind, btrim(p_title),
          case when p_kind = 'flash' then p_pct end,
          case when p_kind = 'gift' then p_min_cents end, v_end)
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.merchant_stop_promo(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_login();
  update public.promos set active = false where id = p_id and shop_id = public.my_shop_id() and active;
  if not found then
    perform public.souki_error('Promo introuvable.', 'NOT_FOUND');
  end if;
end $$;

-- Promos en cours autour du client (ou partout si pas de position)
create or replace function public.active_promos(p_lat double precision default null, p_lng double precision default null,
                                                p_radius_km double precision default 15)
returns table (id bigint, shop_id uuid, shop_name text, kind text, title text, discount_pct numeric, min_cents int,
               ends_at timestamptz, distance_km double precision)
language sql stable security definer set search_path = public as $$
  select p.id, s.id, s.name, p.kind, p.title, p.discount_pct, p.min_cents, p.ends_at,
         case when p_lat is null or p_lng is null then null else public.distance_km(p_lat, p_lng, s.lat, s.lng) end
  from public.promos p join public.shops s on s.id = p.shop_id
  where p.active and p.ends_at > now() and public.shop_is_visible(s.id)
    and (p_lat is null or p_lng is null or public.distance_km(p_lat, p_lng, s.lat, s.lng) <= least(coalesce(p_radius_km, 15), 50))
  order by (p.kind = 'flash') desc,
           case when p_lat is null or p_lng is null then 0 else public.distance_km(p_lat, p_lng, s.lat, s.lng) end,
           p.ends_at
  limit 100;
$$;

-- ---------- Administration ----------
create or replace function public.admin_update_welcome(p_enabled boolean, p_amount_cents int, p_min_cents int, p_slots int)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  if p_enabled is null or p_amount_cents is null or p_amount_cents not between 100 and 5000
     or p_min_cents is null or p_min_cents not between 0 and 100000
     or p_slots is null or p_slots not between 0 and 100000 then
    perform public.souki_error('Valeurs invalides : vérifiez les paramètres.', 'BAD_SETTINGS');
  end if;
  update public.settings set welcome_enabled = p_enabled, welcome_amount_cents = p_amount_cents,
    welcome_min_cents = p_min_cents, welcome_slots = p_slots
  where id = 1;
end $$;

create or replace function public.admin_promo_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare st public.settings;
  v_month timestamptz := (date_trunc('month', now() at time zone 'Europe/Paris')) at time zone 'Europe/Paris';
begin
  perform public.require_admin();
  select * into st from public.settings where id = 1;
  return jsonb_build_object(
    'welcome_enabled', st.welcome_enabled,
    'welcome_amount_cents', st.welcome_amount_cents,
    'welcome_min_cents', st.welcome_min_cents,
    'welcome_slots', st.welcome_slots,
    'welcome_used', (select count(distinct client_id) from public.purchases where welcome_cents > 0 and status <> 'cancelled'),
    'welcome_cost_cents', (select coalesce(sum(welcome_cents), 0) from public.purchases where status <> 'cancelled'),
    'welcome_cost_month_cents', (select coalesce(sum(welcome_cents), 0) from public.purchases where status <> 'cancelled' and created_at >= v_month),
    'refunds_due_cents', (select coalesce(sum(-amount_cents), 0) from public.charges where amount_cents < 0 and status = 'pending'),
    'promos_active', (select count(*) from public.promos where active and ends_at > now())
  );
end $$;

revoke execute on function
  public.welcome_for(uuid), public.client_welcome(), public.merchant_voucher_info(text),
  public.merchant_checkins(), public.merchant_save_promo(text, text, numeric, int, int), public.merchant_stop_promo(bigint),
  public.active_promos(double precision, double precision, double precision),
  public.admin_update_welcome(boolean, int, int, int), public.admin_promo_stats()
from public, anon, authenticated;
grant execute on function public.active_promos(double precision, double precision, double precision) to anon, authenticated;
grant execute on function
  public.client_welcome(), public.merchant_voucher_info(text), public.merchant_checkins(),
  public.merchant_save_promo(text, text, numeric, int, int), public.merchant_stop_promo(bigint),
  public.admin_update_welcome(boolean, int, int, int), public.admin_promo_stats()
to authenticated;

-- >>> 010_iban.sql
-- =====================================================================
-- SOUKI DEALS — 010 : IBAN du commerçant (pour lui rembourser les offres de bienvenue)
-- Table à part, lisible seulement par le commerçant et le fondateur.
-- L'IBAN est vérifié (clé de contrôle) et sa date de changement est gardée :
-- le fondateur est alerté si l'IBAN vient de changer avant un virement.
-- Ce fichier est relançable : il sert aussi de mise à jour (rien n'est effacé).
-- =====================================================================

create table if not exists public.shop_bank (
  shop_id     uuid primary key references public.shops(id) on delete cascade,
  holder      text not null check (char_length(holder) between 2 and 70),
  iban        text not null check (iban ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$'),
  bic         text check (bic is null or bic ~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$'),
  updated_at  timestamptz not null default now()
);
alter table public.shop_bank enable row level security;
drop policy if exists shop_bank_select on public.shop_bank;
create policy shop_bank_select on public.shop_bank for select to authenticated
  using (shop_id = public.my_shop_id() or public.is_admin());
grant select on public.shop_bank to authenticated;

-- Clé de contrôle de l'IBAN (norme ISO 13616, modulo 97)
create or replace function public.iban_valid(p_iban text)
returns boolean language plpgsql immutable as $$
declare
  s text;
  digits text := '';
  ch text;
  r int := 0;
  i int;
  v_len int;
begin
  s := upper(regexp_replace(coalesce(p_iban, ''), '\s', '', 'g'));
  if s !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$' then
    return false;
  end if;
  -- Longueurs connues des pays proches (les autres pays : longueur libre)
  v_len := case left(s, 2) when 'FR' then 27 when 'BE' then 16 when 'DE' then 22 when 'ES' then 24
                           when 'IT' then 27 when 'NL' then 18 when 'LU' then 20 when 'CH' then 21
                           when 'MC' then 27 when 'GB' then 22 when 'PT' then 25 else null end;
  if v_len is not null and length(s) <> v_len then
    return false;
  end if;
  s := substr(s, 5) || left(s, 4);
  for i in 1..length(s) loop
    ch := substr(s, i, 1);
    if ch ~ '[A-Z]' then
      digits := digits || (ascii(ch) - 55)::text;
    else
      digits := digits || ch;
    end if;
  end loop;
  for i in 1..length(digits) loop
    r := (r * 10 + substr(digits, i, 1)::int) % 97;
  end loop;
  return r = 1;
end $$;

create or replace function public.merchant_save_bank(p_holder text, p_iban text, p_bic text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_shop uuid := public.my_shop_id();
  v_iban text := upper(regexp_replace(coalesce(p_iban, ''), '\s', '', 'g'));
  v_bic text := nullif(upper(regexp_replace(coalesce(p_bic, ''), '\s', '', 'g')), '');
begin
  perform public.require_login();
  if v_shop is null then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  if char_length(btrim(coalesce(p_holder, ''))) not between 2 and 70 then
    perform public.souki_error('Indiquez le titulaire du compte.', 'BAD_BANK');
  end if;
  if not public.iban_valid(v_iban) then
    perform public.souki_error('IBAN invalide : vérifiez-le sur votre RIB.', 'BAD_IBAN');
  end if;
  if v_bic is not null and v_bic !~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$' then
    perform public.souki_error('BIC invalide (8 ou 11 caractères).', 'BAD_BANK');
  end if;
  insert into public.shop_bank (shop_id, holder, iban, bic, updated_at)
  values (v_shop, btrim(p_holder), v_iban, v_bic, now())
  on conflict (shop_id) do update set holder = excluded.holder, iban = excluded.iban, bic = excluded.bic,
    updated_at = case when public.shop_bank.iban is distinct from excluded.iban then now() else public.shop_bank.updated_at end;
end $$;

revoke execute on function public.iban_valid(text), public.merchant_save_bank(text, text, text) from public, anon, authenticated;
grant execute on function public.merchant_save_bank(text, text, text) to authenticated;

-- >>> 011_compte_notifications.sql
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
