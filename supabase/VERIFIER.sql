-- SOUKI DEALS : verification des mises a jour (ne change rien). Coller dans SQL Editor > Run.
select etape, case when ok then 'OK' else 'MANQUE' end as etat from (values
  ('005 factures', to_regclass('public.invoices') is not null),
  ('006 releve et conditions', exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'shops' and column_name = 'terms_version')),
  ('007 scan inverse', to_regclass('public.checkins') is not null),
  ('008 inscrits', to_regprocedure('public.admin_members()') is not null),
  ('009 promos', to_regclass('public.promos') is not null),
  ('010 iban', to_regclass('public.shop_bank') is not null),
  ('011 compte et notifications', to_regclass('public.push_tokens') is not null),
  ('012 photos', exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'products' and column_name = 'photo_path')),
  ('013 notifications completes', to_regprocedure('public.notify_report()') is not null),
  ('014 e-mails par Resend', to_regprocedure('public.deals_send_auth_email(jsonb)') is not null),
  ('015 bienvenue 1000 places', (select welcome_slots from public.settings where id = 1) >= 1000),
  ('016 bon offre', exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'checkins' and column_name = 'promo_id')),
  ('017 derniers inscrits', to_regprocedure('public.admin_latest_members(integer)') is not null),
  ('018 messagerie', to_regclass('public.support_messages') is not null),
  ('cle Resend dans le coffre-fort', exists (select 1 from vault.decrypted_secrets where name = 'resend_api_key')),
  ('stockage photos', exists (select 1 from storage.buckets where id = 'photos')),
  ('extension pg_net', exists (select 1 from pg_extension where extname = 'pg_net')),
  ('taches automatiques', exists (select 1 from pg_extension where extname = 'pg_cron'))
) as v(etape, ok);
