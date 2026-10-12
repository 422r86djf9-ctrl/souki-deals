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
