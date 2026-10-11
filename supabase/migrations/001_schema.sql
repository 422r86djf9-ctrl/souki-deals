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
