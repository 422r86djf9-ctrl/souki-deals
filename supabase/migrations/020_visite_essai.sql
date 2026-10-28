-- 020 : le fondateur peut faire une visite d'essai dans la boutique d'essai (suspendue, invisible des clients).
-- Pour lui seul, cette boutique compte comme « visible » : il la voit autour de lui et peut y scanner son QR code. Relançable.
create or replace function public.shop_is_visible(p_shop uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.shops s join public.zones z on z.id = s.zone_id
    where s.id = p_shop
      and (
        (s.status = 'active' and z.open and not public.shop_is_blocked(s.id))
        or (s.owner_id = '00000000-0000-4000-8000-0000000e55a1' and public.is_admin())
      )
  );
$$;
