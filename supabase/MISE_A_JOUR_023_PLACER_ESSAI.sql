begin;
-- SOUKI DEALS : mise a jour 023 (placer la boutique d'essai). Relancable.
-- 023 : le fondateur place la boutique d'essai à sa position actuelle (pour tester la détection d'arrivée). Relançable.
create or replace function public.admin_move_test_shop(p_lat double precision, p_lng double precision)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    perform public.souki_error('Position invalide.', 'BAD_POSITION');
  end if;
  update public.shops set lat = p_lat, lng = p_lng
  where owner_id = '00000000-0000-4000-8000-0000000e55a1';
end $$;
revoke execute on function public.admin_move_test_shop(double precision, double precision) from public, anon, authenticated;
grant execute on function public.admin_move_test_shop(double precision, double precision) to authenticated;

commit;
