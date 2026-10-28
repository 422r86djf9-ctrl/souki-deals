-- 019 : boutique d'essai pour le fondateur (suspendue : invisible des clients, visible dans l'administration).
-- Sert à vérifier les écrans (fiche du commerce, offre flash, produits). Relançable.
do $$
declare
  v_uid uuid := '00000000-0000-4000-8000-0000000e55a1';
  v_shop uuid;
begin
  insert into auth.users (id, email, created_at) values (v_uid, 'boutique-essai@soukideals.com', now())
  on conflict (id) do nothing;
  insert into public.shops (owner_id, name, kind, zone_id, address, lat, lng, phone, halal_cert, hours, description, discount_pct, status)
  values (v_uid, 'Boutique d''essai', 'boucherie', (select min(id) from public.zones), '1 rue de l''Essai, 75018 Paris',
          48.8925, 2.3487, '01 23 45 67 89', 'AVS', 'Mar–Dim 8 h–20 h',
          'Commerce d''essai pour vérifier l''appli. Invisible des clients.', 10, 'suspended')
  on conflict (owner_id) do update set status = 'suspended'
  returning id into v_shop;
  delete from public.products where shop_id = v_shop;
  insert into public.products (shop_id, name, category, unit, price_cents, discount_pct) values
    (v_shop, 'Gigot d''agneau', 'Agneau', 'kg', 1890, null),
    (v_shop, 'Côtelettes d''agneau', 'Agneau', 'kg', 1690, 25),
    (v_shop, 'Merguez maison', 'Saucisses', 'kg', 1290, null),
    (v_shop, 'Poulet entier', 'Volaille', 'piece', 990, null),
    (v_shop, 'Viande hachée', 'Bœuf', 'kg', 1450, 15),
    (v_shop, 'Dattes Deglet Nour', 'Épicerie', 'piece', 590, null);
  delete from public.promos where shop_id = v_shop;
  insert into public.promos (shop_id, kind, title, discount_pct, ends_at)
  values (v_shop, 'flash', 'Côtelettes d''agneau', 25, now() + interval '30 days');
end $$;
