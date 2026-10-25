-- 016 : le « bon » de l'offre choisie. Le client sélectionne une offre (flash ou cadeau) du commerce ;
-- elle s'affiche sur son écran en magasin et sur la tablette du commerçant. Le parcours ne change pas :
-- QR scanné par le client, montant saisi par le commerçant, confirmé par le client. Relançable.

alter table public.checkins add column if not exists promo_id bigint references public.promos(id) on delete set null;

-- Le client choisit (ou retire, p_promo_id = null) l'offre de sa visite en cours
create or replace function public.client_set_checkin_promo(p_id uuid, p_promo_id bigint)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  c public.checkins;
  p public.promos;
begin
  perform public.require_login();
  select * into c from public.checkins where id = p_id and client_id = auth.uid() and status = 'waiting' and expires_at > now() for update;
  if not found then
    perform public.souki_error('Visite introuvable ou déjà terminée.', 'NOT_FOUND');
  end if;
  if p_promo_id is null then
    update public.checkins set promo_id = null where id = c.id;
    return jsonb_build_object('promo_id', null);
  end if;
  select * into p from public.promos where id = p_promo_id;
  if not found or p.shop_id <> c.shop_id or not p.active or p.ends_at <= now() or p.starts_at > now() then
    perform public.souki_error('Cette offre n''est plus valable dans ce commerce.', 'PROMO_INVALID');
  end if;
  update public.checkins set promo_id = p.id where id = c.id;
  return jsonb_build_object('promo_id', p.id, 'kind', p.kind, 'title', p.title, 'discount_pct', p.discount_pct,
                            'min_cents', p.min_cents, 'ends_at', p.ends_at);
end $$;

-- Commerçant : clients présents, avec l'offre qu'ils ont choisie
drop function if exists public.merchant_checkins();
create function public.merchant_checkins()
returns table (id uuid, code text, first_name text, created_at timestamptz, expires_at timestamptz, welcome_cents int, welcome_min_cents int,
               promo_kind text, promo_title text, promo_pct numeric, promo_min_cents int)
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
           public.welcome_for(c.client_id), (select welcome_min_cents from public.settings where settings.id = 1),
           p.kind, p.title, p.discount_pct, p.min_cents
    from public.checkins c join public.vouchers v on v.id = c.voucher_id
    left join public.promos p on p.id = c.promo_id
    where c.shop_id = v_shop and c.status = 'waiting' and c.expires_at > now()
    order by c.created_at;
end $$;

revoke execute on function public.client_set_checkin_promo(uuid, bigint), public.merchant_checkins() from public, anon, authenticated;
grant execute on function public.client_set_checkin_promo(uuid, bigint), public.merchant_checkins() to authenticated;
