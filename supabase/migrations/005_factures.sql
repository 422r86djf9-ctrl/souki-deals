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
