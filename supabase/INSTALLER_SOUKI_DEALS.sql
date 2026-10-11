-- =====================================================================
-- SOUKI DEALS — INSTALLATEUR COMPLET (à coller dans Supabase > SQL Editor > Run)
-- Réinstalle toute la base de test. Les comptes utilisateurs sont conservés.
-- =====================================================================
begin;

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
                                      'vouchers', 'purchases', 'charges', 'reports')) then
    raise exception 'SOUKI DEALS : ce projet Supabase contient d''autres tables. Installez Souki Deals dans un projet dédié.';
  end if;
end $$;

drop table if exists
  public.reports, public.charges, public.purchases, public.vouchers,
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
      'admin_update_settings')
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

commit;
