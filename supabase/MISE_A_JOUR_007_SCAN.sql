begin;
-- SOUKI DEALS : mise a jour 007 (scan inverse : QR code du magasin). N'efface rien, relancable.
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
create or replace function public.merchant_checkins()
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

commit;
