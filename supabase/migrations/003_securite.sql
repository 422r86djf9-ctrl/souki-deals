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
