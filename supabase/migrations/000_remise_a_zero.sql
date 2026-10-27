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
                                      'vouchers', 'purchases', 'charges', 'reports', 'company', 'invoices', 'checkins', 'promos', 'shop_bank', 'push_tokens', 'notifications', 'support_messages')) then
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
  public.support_messages, public.notifications, public.push_tokens, public.shop_bank, public.promos, public.checkins, public.invoices, public.company, public.reports, public.charges, public.purchases, public.vouchers,
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
      'notify_purchase', 'notify_promo', 'notify_shop', 'notify_charge', 'admin_remove_product_photo')
  loop
    execute format('drop function if exists %s cascade', r.sig);
  end loop;
end $$;
