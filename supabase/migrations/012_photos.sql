-- =====================================================================
-- SOUKI DEALS — 012 : photos des produits
-- Le commerçant ajoute une photo à ses produits frais ou faits maison (viande, pâtisseries,
-- plats…). Les produits emballés de marque (lait, jus en bouteille, conserves…) n'en ont pas :
-- tout le monde les connaît déjà.
-- Photos dans le stockage public « photos » : products/<commerce>/<fichier>.jpg
-- Les clients peuvent signaler une photo ; le fondateur peut la retirer.
-- Ce fichier est relançable : il sert aussi de mise à jour (rien n'est effacé).
-- =====================================================================

alter table public.products add column if not exists packaged boolean not null default false;
alter table public.products add column if not exists photo_path text;

-- Gardien des produits : remise minimum, et photo seulement pour les produits non emballés
create or replace function public.guard_products()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_min numeric;
begin
  select discount_min into v_min from public.settings where id = 1;
  if new.discount_pct is not null and new.discount_pct < v_min
     and (tg_op = 'INSERT' or new.discount_pct is distinct from old.discount_pct) then
    perform public.souki_error(format('La remise doit être d''au moins %s %%.', v_min), 'DISCOUNT_TOO_LOW');
  end if;
  if tg_op = 'UPDATE' then
    new.shop_id := old.shop_id;
  end if;
  if new.packaged then
    new.photo_path := null;
  elsif new.photo_path is not null and new.photo_path !~ ('^products/' || new.shop_id::text || '/[A-Za-z0-9_-]+\.jpg$') then
    perform public.souki_error('Photo invalide.', 'BAD_PHOTO');
  end if;
  new.updated_at := now();
  return new;
end $$;

-- Stockage des photos : lisible par tous, chaque commerçant écrit seulement dans son dossier
insert into storage.buckets (id, name, public) values ('photos', 'photos', true)
on conflict (id) do update set public = true;
drop policy if exists photos_insert on storage.objects;
create policy photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = 'products'
              and (storage.foldername(name))[2] = public.my_shop_id()::text);
drop policy if exists photos_delete on storage.objects;
create policy photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (((storage.foldername(name))[1] = 'products'
              and (storage.foldername(name))[2] = public.my_shop_id()::text) or public.is_admin()));
drop policy if exists photos_select on storage.objects;
create policy photos_select on storage.objects for select
  using (bucket_id = 'photos');

-- Signalement d'une photo
alter table public.reports drop constraint if exists reports_kind_check;
alter table public.reports add constraint reports_kind_check check (kind in ('prix', 'halal', 'achat', 'photo', 'autre'));
create or replace function public.report_create(p_shop_id uuid, p_kind text, p_body text, p_product_id int default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  perform public.require_login();
  if p_kind not in ('prix', 'halal', 'photo', 'autre') then
    perform public.souki_error('Type de signalement invalide.', 'BAD_KIND');
  end if;
  if p_body is null or char_length(btrim(p_body)) not between 3 and 500 then
    perform public.souki_error('Décrivez le problème (3 à 500 caractères).', 'BAD_BODY');
  end if;
  if not exists (select 1 from public.shops where id = p_shop_id) then
    perform public.souki_error('Commerce introuvable.', 'NOT_FOUND');
  end if;
  if (select count(*) from public.reports where user_id = auth.uid() and created_at > now() - interval '1 day') >= 10 then
    perform public.souki_error('Trop de signalements aujourd''hui.', 'TOO_MANY');
  end if;
  insert into public.reports (user_id, shop_id, product_id, kind, body)
  values (auth.uid(), p_shop_id,
          (select id from public.products where id = p_product_id and shop_id = p_shop_id),
          p_kind, btrim(p_body))
  returning id into v_id;
  return v_id;
end $$;

-- Le fondateur retire une photo (trompeuse ou choquante)
create or replace function public.admin_remove_product_photo(p_product_id int)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  update public.products set photo_path = null where id = p_product_id and photo_path is not null;
  if not found then
    perform public.souki_error('Photo introuvable.', 'NOT_FOUND');
  end if;
  update public.reports set status = 'done' where product_id = p_product_id and kind = 'photo' and status = 'open';
end $$;

revoke execute on function public.admin_remove_product_photo(int) from public, anon, authenticated;
grant execute on function public.admin_remove_product_photo(int) to authenticated;
