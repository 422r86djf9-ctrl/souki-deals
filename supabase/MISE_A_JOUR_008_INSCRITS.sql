begin;
-- SOUKI DEALS : mise a jour 008 (nombre d'inscrits). N'efface rien, relancable.
-- =====================================================================
-- SOUKI DEALS — 008 : nombre d'inscrits (particuliers et commerçants)
-- Pour le fondateur : comptes vérifiés (e-mail confirmé), sans compter le fondateur.
-- Particulier = compte sans commerce. Actif = a pris un bon ou scanné un magasin
-- dans les 30 derniers jours.
-- Ce fichier est relançable : il sert aussi de mise à jour (rien n'est effacé).
-- =====================================================================

create or replace function public.admin_members()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_today timestamptz := (public.paris_today()::timestamp) at time zone 'Europe/Paris';
  v_week timestamptz := (public.week_of(now())::timestamp) at time zone 'Europe/Paris';
  v_month timestamptz := (date_trunc('month', now() at time zone 'Europe/Paris')) at time zone 'Europe/Paris';
begin
  perform public.require_admin();
  return (
    with u as (
      select au.id, au.created_at,
             exists (select 1 from public.shops s where s.owner_id = au.id) as has_shop
      from auth.users au
      where au.email_confirmed_at is not null
        and lower(coalesce(au.email, '')) <> 'demba.sacko20@gmail.com'
    ), c as (select * from u where not has_shop),
    act as (
      select distinct client_id as id from public.vouchers where created_at > now() - interval '30 days'
      union
      select distinct client_id from public.checkins where created_at > now() - interval '30 days'
    ),
    weeks as (
      select generate_series(public.week_of(now()) - 7 * 11, public.week_of(now()), interval '7 days')::date as w
    )
    select jsonb_build_object(
      'clients', jsonb_build_object(
        'total', (select count(*) from c),
        'today', (select count(*) from c where created_at >= v_today),
        'week', (select count(*) from c where created_at >= v_week),
        'month', (select count(*) from c where created_at >= v_month),
        'active_30d', (select count(*) from c where id in (select id from act)),
        'unconfirmed', (select count(*) from auth.users au where au.email_confirmed_at is null)
      ),
      'shops', jsonb_build_object(
        'total', (select count(*) from public.shops),
        'active', (select count(*) from public.shops where status = 'active'),
        'pending', (select count(*) from public.shops where status = 'pending'),
        'suspended', (select count(*) from public.shops where status = 'suspended'),
        'week', (select count(*) from public.shops where created_at >= v_week),
        'month', (select count(*) from public.shops where created_at >= v_month),
        'launch_offer', (select count(*) from public.shops where launch_offer)
      ),
      'by_zone', coalesce((
        select jsonb_agg(jsonb_build_object('zone', z.name, 'shops', z.shops, 'active', z.active) order by z.sort)
        from (select zn.name, zn.sort,
                     count(s.id) as shops, count(s.id) filter (where s.status = 'active') as active
              from public.zones zn left join public.shops s on s.zone_id = zn.id
              group by zn.id) z
        where z.shops > 0), '[]'::jsonb),
      'by_kind', coalesce((
        select jsonb_agg(jsonb_build_object('kind', k.kind, 'shops', k.n) order by k.n desc)
        from (select kind, count(*) as n from public.shops group by kind) k), '[]'::jsonb),
      'weeks', (
        select jsonb_agg(jsonb_build_object(
          'week', w.w,
          'clients', (select count(*) from c where c.created_at >= (w.w::timestamp at time zone 'Europe/Paris')
                                                 and c.created_at < ((w.w + 7)::timestamp at time zone 'Europe/Paris')),
          'shops', (select count(*) from public.shops s where s.created_at >= (w.w::timestamp at time zone 'Europe/Paris')
                                                          and s.created_at < ((w.w + 7)::timestamp at time zone 'Europe/Paris'))
        ) order by w.w)
        from weeks w)
    )
  );
end $$;

revoke execute on function public.admin_members() from public, anon, authenticated;
grant execute on function public.admin_members() to authenticated;

commit;
