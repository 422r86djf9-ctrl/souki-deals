begin;
-- SOUKI DEALS : mise a jour 009 (offre de bienvenue, promos des commercants). N'efface rien, relancable.
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

commit;
