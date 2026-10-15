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
  ('stockage photos', exists (select 1 from storage.buckets where id = 'photos')),
  ('extension pg_net', exists (select 1 from pg_extension where extname = 'pg_net')),
  ('taches automatiques', exists (select 1 from pg_extension where extname = 'pg_cron'))
) as v(etape, ok);
