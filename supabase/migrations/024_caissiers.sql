-- 024 : caissiers. Le patron d'un commerce ajoute ses caissiers (par e-mail). Chaque caissier se connecte
-- sur l'appareil de sa caisse et ne voit que « Clients présents » et le scanner : il saisit le montant payé.
-- Il ne voit ni l'argent, ni les factures, ni l'IBAN, ni les réglages. Chaque achat garde le caissier
-- qui l'a saisi (purchases.scanned_by). Une visite prise par une caisse disparaît des autres. Relançable.

create table if not exists public.shop_cashiers (
  id           uuid primary key default gen_random_uuid(),
  shop_id      uuid not null references public.shops(id) on delete cascade,
  email        text not null check (email = lower(btrim(email)) and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  display_name text not null check (char_length(display_name) between 1 and 40),
  user_id      uuid references auth.users(id) on delete cascade,
  status       text not null default 'invited' check (status in ('invited', 'active')),
  created_at   timestamptz not null default now(),
  accepted_at  timestamptz,
  unique (shop_id, email)
);
create index if not exists shop_cashiers_email_idx on public.shop_cashiers (email);
-- Un caissier ne travaille que pour un seul commerce à la fois
create unique index if not exists shop_cashiers_one_shop on public.shop_cashiers (user_id) where status = 'active';

alter table public.shop_cashiers enable row level security;
drop policy if exists shop_cashiers_select on public.shop_cashiers;
create policy shop_cashiers_select on public.shop_cashiers for select to authenticated
  using (shop_id = public.my_shop_id() or user_id = auth.uid() or public.is_admin());
grant select on public.shop_cashiers to authenticated;

-- E-mail vérifié du compte connecté (en minuscules)
create or replace function public.my_verified_email()
returns text language sql stable security definer set search_path = public as $$
  select lower(email) from auth.users where id = auth.uid() and email_confirmed_at is not null;
$$;

-- Commerce pour lequel on travaille en caisse : le sien (patron) ou celui où l'on est caissier
create or replace function public.my_counter_shop_id()
returns uuid language sql stable security definer set search_path = public as $$
  select coalesce(
    (select id from public.shops where owner_id = auth.uid()),
    (select shop_id from public.shop_cashiers where user_id = auth.uid() and status = 'active'));
$$;

-- Patron : ajouter un caissier
create or replace function public.merchant_add_cashier(p_email text, p_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_shop uuid := public.my_shop_id(); v_email text := lower(btrim(coalesce(p_email, ''))); v_name text := btrim(coalesce(p_name, '')); v_id uuid;
begin
  perform public.require_login();
  if v_shop is null then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    perform public.souki_error('Adresse e-mail invalide.', 'BAD_EMAIL');
  end if;
  if char_length(v_name) not between 1 and 40 then
    perform public.souki_error('Indiquez le prénom du caissier (40 caractères au plus).', 'BAD_NAME');
  end if;
  if v_email = public.my_verified_email() then
    perform public.souki_error('Vous êtes déjà le patron de ce commerce.', 'SELF');
  end if;
  if exists (select 1 from public.shops s join auth.users u on u.id = s.owner_id where lower(u.email) = v_email) then
    perform public.souki_error('Ce compte a déjà son propre commerce : il ne peut pas être caissier.', 'SHOP_OWNER');
  end if;
  if exists (select 1 from public.shop_cashiers where shop_id = v_shop and email = v_email) then
    perform public.souki_error('Ce caissier est déjà dans votre liste.', 'ALREADY_CASHIER');
  end if;
  if (select count(*) from public.shop_cashiers where shop_id = v_shop) >= 30 then
    perform public.souki_error('30 caissiers au plus par commerce.', 'TOO_MANY');
  end if;
  insert into public.shop_cashiers (shop_id, email, display_name) values (v_shop, v_email, v_name)
  returning id into v_id;
  return v_id;
end $$;

-- Patron : retirer un caissier (il perd l'accès tout de suite)
create or replace function public.merchant_remove_cashier(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_login();
  delete from public.shop_cashiers where id = p_id and shop_id = public.my_shop_id();
  if not found then
    perform public.souki_error('Caissier introuvable.', 'NOT_FOUND');
  end if;
end $$;

-- Patron : ses caissiers et ce que chacun a saisi (aujourd'hui, 30 derniers jours)
create or replace function public.merchant_cashiers()
returns table (id uuid, email text, display_name text, status text, created_at timestamptz, accepted_at timestamptz,
               today_count int, today_cents bigint, month_count int, month_cents bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_shop uuid := public.my_shop_id();
begin
  perform public.require_login();
  if v_shop is null then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  return query
    select k.id, k.email, k.display_name, k.status, k.created_at, k.accepted_at,
           count(p.id) filter (where (p.created_at at time zone 'Europe/Paris')::date = public.paris_today())::int,
           coalesce(sum(p.amount_cents) filter (where (p.created_at at time zone 'Europe/Paris')::date = public.paris_today()), 0)::bigint,
           count(p.id) filter (where p.created_at > now() - interval '30 days')::int,
           coalesce(sum(p.amount_cents) filter (where p.created_at > now() - interval '30 days'), 0)::bigint
    from public.shop_cashiers k
    left join public.purchases p on p.shop_id = k.shop_id and k.user_id is not null and p.scanned_by = k.user_id
                                and p.status <> 'cancelled'
    where k.shop_id = v_shop
    group by k.id
    order by k.status desc, k.display_name;
end $$;

-- Caissier : accepter l'invitation (e-mail vérifié identique)
create or replace function public.cashier_accept(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare k public.shop_cashiers; v_email text := public.my_verified_email();
begin
  perform public.require_login();
  if v_email is null then
    perform public.souki_error('Confirmez d''abord votre adresse e-mail.', 'EMAIL_NOT_VERIFIED');
  end if;
  select * into k from public.shop_cashiers where id = p_id and email = v_email for update;
  if not found then
    perform public.souki_error('Invitation introuvable.', 'NOT_FOUND');
  end if;
  if exists (select 1 from public.shops where owner_id = auth.uid()) then
    perform public.souki_error('Vous avez déjà votre propre commerce : vous ne pouvez pas être caissier.', 'SHOP_OWNER');
  end if;
  if exists (select 1 from public.shop_cashiers where user_id = auth.uid() and status = 'active' and id <> k.id) then
    perform public.souki_error('Vous êtes déjà caissier dans un autre commerce. Quittez-le d''abord.', 'OTHER_SHOP');
  end if;
  update public.shop_cashiers set status = 'active', user_id = auth.uid(), accepted_at = coalesce(accepted_at, now())
  where id = k.id;
  return jsonb_build_object('shop_id', k.shop_id, 'shop_name', (select name from public.shops where id = k.shop_id));
end $$;

-- Caissier : refuser une invitation ou quitter le commerce
create or replace function public.cashier_leave(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_login();
  delete from public.shop_cashiers
  where id = p_id and (user_id = auth.uid() or (status = 'invited' and email = public.my_verified_email()));
  if not found then
    perform public.souki_error('Invitation introuvable.', 'NOT_FOUND');
  end if;
end $$;

-- Interdit à un patron d'ouvrir un commerce s'il est caissier ailleurs (il doit d'abord quitter)
create or replace function public.guard_shop_cashier_owner()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- owner_id est rempli plus tard par guard_shops : on vérifie aussi le compte connecté
  if exists (select 1 from public.shop_cashiers where user_id in (new.owner_id, auth.uid()) and status = 'active') then
    perform public.souki_error('Vous êtes caissier dans un commerce : quittez-le avant d''inscrire le vôtre.', 'IS_CASHIER');
  end if;
  return new;
end $$;
drop trigger if exists shops_cashier_owner on public.shops;
create trigger shops_cashier_owner before insert on public.shops
  for each row execute function public.guard_shop_cashier_owner();

-- Les visites et bons du commerce sont visibles en caisse
drop policy if exists checkins_select on public.checkins;
create policy checkins_select on public.checkins for select to authenticated
  using (client_id = auth.uid() or shop_id = public.my_counter_shop_id() or public.is_admin());

-- Le caissier voit seulement les achats qu'il a saisis ; le patron voit tout son commerce
drop policy if exists purchases_select on public.purchases;
create policy purchases_select on public.purchases for select to authenticated
  using (client_id = auth.uid() or shop_id = public.my_shop_id()
         or (scanned_by = auth.uid() and shop_id = public.my_counter_shop_id()) or public.is_admin());

-- Caisse : clients présents (patron ou caissier)
drop function if exists public.merchant_checkins();
create function public.merchant_checkins()
returns table (id uuid, code text, first_name text, created_at timestamptz, expires_at timestamptz, welcome_cents int, welcome_min_cents int,
               promo_kind text, promo_title text, promo_pct numeric, promo_min_cents int)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_shop uuid := public.my_counter_shop_id();
begin
  perform public.require_login();
  if v_shop is null then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  return query
    select c.id, v.code, public.first_name(c.client_id), c.created_at, c.expires_at,
           public.welcome_for(c.client_id), (select welcome_min_cents from public.settings where settings.id = 1),
           p.kind, p.title, p.discount_pct, p.min_cents
    from public.checkins c join public.vouchers v on v.id = c.voucher_id
    left join public.promos p on p.id = c.promo_id
    where c.shop_id = v_shop and c.status = 'waiting' and c.expires_at > now()
    order by c.created_at;
end $$;

create or replace function public.merchant_complete_checkin(p_id uuid, p_amount_cents int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c public.checkins; v_code text;
begin
  perform public.require_login();
  -- Verrou : si deux caisses touchent le même client, la seconde attend puis voit « déjà terminée »
  select * into c from public.checkins where id = p_id and shop_id = public.my_counter_shop_id() for update;
  if not found then
    perform public.souki_error('Visite introuvable.', 'NOT_FOUND');
  end if;
  if c.status <> 'waiting' then
    perform public.souki_error('Cette visite est déjà terminée.', 'ALREADY_DONE');
  end if;
  select code into v_code from public.vouchers where id = c.voucher_id;
  return public.merchant_scan(v_code, p_amount_cents);
end $$;

create or replace function public.merchant_dismiss_checkin(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.checkins;
begin
  perform public.require_login();
  update public.checkins set status = 'dismissed', closed_at = now()
  where id = p_id and shop_id = public.my_counter_shop_id() and status = 'waiting'
  returning * into c;
  if not found then
    perform public.souki_error('Visite introuvable ou déjà terminée.', 'NOT_FOUND');
  end if;
  update public.vouchers set status = 'cancelled' where id = c.voucher_id and status = 'active';
end $$;

create or replace function public.merchant_voucher_info(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v public.vouchers; st public.settings; v_shop uuid := public.my_counter_shop_id();
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

-- Scan du bon et saisie du montant : patron ou caissier (mêmes règles qu'avant)
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
  select * into s from public.shops where id = public.my_counter_shop_id();
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
  -- Un caissier ne valide pas ses propres achats (ni ceux d'un autre caissier du commerce)
  if v.client_id = auth.uid()
     or exists (select 1 from public.shop_cashiers where shop_id = s.id and user_id = v.client_id and status = 'active') then
    perform public.souki_error('Un caissier ne peut pas valider ses propres achats : demandez à un collègue ou au patron.', 'CASHIER_SELF');
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

  perform pg_advisory_xact_lock(hashtext('welcome:' || v.client_id::text));
  perform pg_advisory_xact_lock(hashtext('welcome-slots'));
  v_welcome := public.welcome_for(v.client_id);
  if v_welcome > 0 and p_amount_cents + v_welcome < st.welcome_min_cents then
    v_welcome := 0;
  end if;
  v_free := s.free_until is not null and public.paris_today() <= s.free_until;
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

-- Le client arrivé est annoncé au patron et à tous les caissiers actifs
create or replace function public.notify_checkin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'waiting' and (tg_op = 'INSERT' or old.status = 'reserved') then
    perform public.deals_notify(
      (select array_agg(u) from (
         select owner_id as u from public.shops where id = new.shop_id
         union select user_id from public.shop_cashiers where shop_id = new.shop_id and status = 'active') x),
      'client_present', jsonb_build_object('name', public.first_name(new.client_id)), jsonb_build_object('url', '/commercant'));
  end if;
  return new;
end $$;

-- Caisse du jour du caissier (ses saisies d'aujourd'hui)
create or replace function public.cashier_today()
returns table (id uuid, first_name text, amount_cents int, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.require_login();
  return query
    select p.id, public.first_name(p.client_id), p.amount_cents, p.created_at
    from public.purchases p
    where p.scanned_by = auth.uid() and p.shop_id = public.my_counter_shop_id() and p.status <> 'cancelled'
      and (p.created_at at time zone 'Europe/Paris')::date = public.paris_today()
    order by p.created_at desc;
end $$;

-- Fondateur : achats d'un commerce par caissier (30 derniers jours)
create or replace function public.admin_shop_cashiers(p_shop uuid)
returns table (scanned_by uuid, name text, is_owner boolean, count int, amount_cents bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform public.require_admin();
  return query
    select p.scanned_by,
           coalesce((select k.display_name from public.shop_cashiers k where k.shop_id = p_shop and k.user_id = p.scanned_by),
                    case when p.scanned_by = s.owner_id then 'Patron' else 'Ancien caissier' end),
           p.scanned_by = s.owner_id, count(*)::int, sum(p.amount_cents)::bigint
    from public.purchases p join public.shops s on s.id = p.shop_id
    where p.shop_id = p_shop and p.status <> 'cancelled' and p.created_at > now() - interval '30 days'
    group by p.scanned_by, s.owner_id
    order by 5 desc;
end $$;

-- Qui suis-je ? (+ commerce où l'on est caissier, invitations reçues)
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
    'cashier', (select jsonb_build_object('id', k.id, 'shop_id', s.id, 'shop_name', s.name, 'shop_status', s.status,
                                          'discount_pct', s.discount_pct, 'display_name', k.display_name)
                from public.shop_cashiers k join public.shops s on s.id = k.shop_id
                where k.user_id = v_uid and k.status = 'active'),
    'cashier_invites', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'shop_name', s.name) order by k.created_at)
                                 from public.shop_cashiers k join public.shops s on s.id = k.shop_id
                                 where k.status = 'invited' and k.email = public.my_verified_email()), '[]'::jsonb),
    'pending_purchases', (select count(*) from public.purchases where client_id = v_uid and status = 'pending'),
    'visits_to_answer', (select count(*) from public.checkins
                         where client_id = v_uid and status in ('expired', 'dismissed') and client_answer is null
                           and created_at > now() - interval '7 days')
  );
end $$;

revoke execute on function
  public.my_verified_email(), public.my_counter_shop_id(), public.merchant_add_cashier(text, text),
  public.merchant_remove_cashier(uuid), public.merchant_cashiers(), public.cashier_accept(uuid), public.cashier_leave(uuid),
  public.guard_shop_cashier_owner(), public.merchant_checkins(), public.merchant_complete_checkin(uuid, int),
  public.merchant_dismiss_checkin(uuid), public.merchant_voucher_info(text), public.merchant_scan(text, int),
  public.notify_checkin(), public.cashier_today(), public.admin_shop_cashiers(uuid), public.whoami()
from public, anon, authenticated;
grant execute on function
  public.my_verified_email(), public.my_counter_shop_id(), public.merchant_add_cashier(text, text),
  public.merchant_remove_cashier(uuid), public.merchant_cashiers(), public.cashier_accept(uuid), public.cashier_leave(uuid),
  public.merchant_checkins(), public.merchant_complete_checkin(uuid, int),
  public.merchant_dismiss_checkin(uuid), public.merchant_voucher_info(text), public.merchant_scan(text, int),
  public.cashier_today(), public.admin_shop_cashiers(uuid), public.whoami()
to authenticated;
grant execute on function public.whoami(), public.my_counter_shop_id() to anon;
