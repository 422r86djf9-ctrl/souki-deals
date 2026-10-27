-- =====================================================================
-- SOUKI DEALS — tests automatiques (PostgreSQL local + simulation Supabase)
-- =====================================================================
\set ON_ERROR_STOP on
\set QUIET on
\o /dev/null

-- ---------- Outils de test ----------
create schema t;
create table t.results (n serial, label text, passed boolean);
grant usage on schema t to anon, authenticated;
grant all on t.results to anon, authenticated;
grant usage on sequence t.results_n_seq to anon, authenticated;

create function t.ok(p_cond boolean, p_label text) returns void language plpgsql as $$
begin
  insert into t.results (label, passed) values (p_label, coalesce(p_cond, false));
  if not coalesce(p_cond, false) then raise warning 'ÉCHEC : %', p_label; end if;
end $$;

create function t.throws(p_sql text, p_code text, p_label text) returns void language plpgsql as $$
declare v_hint text; v_msg text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint, v_msg = message_text;
    perform t.ok(coalesce(v_hint, '') = p_code,
                 p_label || case when coalesce(v_hint, '') = p_code then ''
                            else ' [reçu : ' || coalesce(v_hint, '-') || ' / ' || v_msg || ']' end);
    return;
  end;
  perform t.ok(false, p_label || ' [aucune erreur]');
end $$;

create function t.fails(p_sql text, p_label text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    perform t.ok(true, p_label);
    return;
  end;
  perform t.ok(false, p_label || ' [aucune erreur]');
end $$;

create function t.login(p_uid uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
$$;
create function t.z(p_name text) returns int language sql stable as $$
  select id from public.zones where name = p_name;
$$;
grant execute on all functions in schema t to anon, authenticated;

-- ---------- Comptes ----------
insert into auth.users (id, email, email_confirmed_at) values
  ('bbbbbbbb-0000-0000-0000-000000000001', 'Demba.sacko20@gmail.com', now()),  -- fondateur
  ('bbbbbbbb-0000-0000-0000-000000000002', 'demba.sacko20@gmail.com', null),   -- faux, non vérifié
  ('bbbbbbbb-0000-0000-0000-000000000011', 'boucherie@test.fr', now()),
  ('bbbbbbbb-0000-0000-0000-000000000012', 'resto@test.fr', now()),
  ('bbbbbbbb-0000-0000-0000-000000000021', 'client1@test.fr', now()),
  ('bbbbbbbb-0000-0000-0000-000000000022', 'client2@test.fr', now());

\set admin 'bbbbbbbb-0000-0000-0000-000000000001'
\set fake 'bbbbbbbb-0000-0000-0000-000000000002'
\set m1 'bbbbbbbb-0000-0000-0000-000000000011'
\set m2 'bbbbbbbb-0000-0000-0000-000000000012'
\set c1 'bbbbbbbb-0000-0000-0000-000000000021'
\set c2 'bbbbbbbb-0000-0000-0000-000000000022'

-- ---------- Données de départ ----------
select t.ok((select count(*) from zones where open) = 8, '8 départements d''Île-de-France ouverts');
select t.ok((select discount_min = 5 and commission_rate = 5 and launch_slots = 150 and launch_free_months = 3 from settings), 'Réglages validés : 5 %, 5 %, 150 commerces, 3 mois');
select t.ok(norm('Méchoui ÉPICÉ') = 'mechoui epice', 'Recherche sans accents');
select t.ok(round(distance_km(48.8566, 2.3522, 48.9362, 2.3574)::numeric, 1) between 8.7 and 8.9, 'Distance Paris - Saint-Denis ≈ 8,8 km');

-- Bienvenue désactivée pour les tests historiques (testée plus bas)
update settings set welcome_enabled = false;
set role authenticated;

-- ---------- Fondateur ----------
select t.login(:'admin');
select t.ok(is_admin() and (whoami()->>'is_admin')::boolean, 'Le fondateur est administrateur');
select t.login(:'fake');
select t.ok(not is_admin(), 'Même e-mail non vérifié : pas administrateur');
select t.throws($$select admin_summary()$$, 'NOT_ADMIN', 'Résumé réservé au fondateur');

-- ---------- Profils et langue ----------
select t.login(:'c1');
insert into profiles (id, full_name, phone) values (auth.uid(), 'Karim B.', '06 12 34 56 78');
select set_my_lang('ar');
select t.ok((whoami()->'profile'->>'lang') = 'ar', 'Le client choisit l''arabe');
select t.throws($$select set_my_lang('dz')$$, 'BAD_LANG', 'Langue inconnue refusée');
select set_my_lang('fr');

-- ---------- Inscription d'un commerce ----------
select t.login(:'m1');
select t.throws(format($$insert into shops (owner_id, name, kind, zone_id, address, lat, lng, discount_pct) values (%L, 'Boucherie Test', 'boucherie', %s, '12 rue de Paris, Saint-Denis', 48.936, 2.357, 3)$$, :'m1', t.z('Seine-Saint-Denis (93)')),
                'DISCOUNT_TOO_LOW', 'Remise de 3 % refusée (minimum 5 %)');
insert into shops (owner_id, name, kind, zone_id, address, lat, lng, siret, halal_cert, status, free_until)
values (:'m1', 'Boucherie Al Baraka', 'boucherie', t.z('Seine-Saint-Denis (93)'), '12 rue de Paris, Saint-Denis', 48.9362, 2.3574,
        '12345678901234', 'AVS', 'active', '2099-01-01');
select id as m1shop from shops where owner_id = :'m1' \gset
select t.ok((select status = 'pending' and not launch_offer and free_until is null and discount_pct = 5 from shops where id = :'m1shop'),
            'Nouveau commerce : en attente, champs protégés (offre attribuée à la validation)');
update shops set status = 'active', free_until = '2099-01-01', card_ok = true where id = :'m1shop';
select t.ok((select status = 'pending' and not card_ok from shops where id = :'m1shop'), 'Le commerçant ne peut pas se valider lui-même');
select t.ok(launch_slots_left() = 150, 'Inscription seule : aucune place de lancement prise');

select t.login(:'c1');
select t.ok((select count(*) from nearby_shops(48.93, 2.35, 5)) = 0, 'Commerce en attente : invisible des clients');
select t.throws(format($$select * from create_voucher(%L)$$, :'m1shop'), 'SHOP_UNAVAILABLE', 'Pas de bon dans un commerce en attente');
update shops set name = 'Pirate' where id = :'m1shop';
select t.ok((select name from shops where owner_id = :'m1') is null, 'Un client ne voit pas un commerce en attente');

-- ---------- Validation par le fondateur ----------
select t.login(:'admin');
select t.ok((select name from shops where id = :'m1shop') = 'Boucherie Al Baraka', 'Un client ne modifie pas un commerce');
select admin_set_shop_status(:'m1shop', 'active');
select t.ok((select status = 'active' and launch_offer and free_until = (paris_today() + interval '3 months')::date and validated_at is not null from shops where id = :'m1shop'),
            'Commerce validé : offre de lancement, 3 mois sans commission à partir de la validation');
select t.ok(launch_slots_left() = 149, 'Places de lancement : 149 restantes');
-- Minimum relevé : le commerçant peut toujours modifier le reste
reset role;
update settings set discount_min = 10;
set role authenticated;
select t.login(:'m1');
update shops set hours = 'Lun-Sam 8h-20h' where id = :'m1shop';
select t.ok((select hours from shops where id = :'m1shop') = 'Lun-Sam 8h-20h', 'Minimum relevé : les autres modifications restent possibles');
reset role;
update settings set discount_min = 5;
set role authenticated;
select t.login(:'admin');
select t.throws(format($$select admin_set_shop_status(%L, 'ferme')$$, :'m1shop'), 'BAD_STATUS', 'Statut inconnu refusé');

-- ---------- Produits ----------
select t.login(:'m1');
insert into products (shop_id, name, category, unit, price_cents) values (:'m1shop', 'Merguez maison', 'Saucisses', 'kg', 1290);
insert into products (shop_id, name, category, unit, price_cents, discount_pct) values (:'m1shop', 'Gigot d''agneau', 'Agneau', 'kg', 1990, 10);
select t.throws(format($$insert into products (shop_id, name, unit, price_cents, discount_pct) values (%L, 'Poulet', 'kg', 690, 2)$$, :'m1shop'),
                'DISCOUNT_TOO_LOW', 'Remise produit sous 5 % refusée');
select t.login(:'m2');
select t.fails(format($$insert into products (shop_id, name, unit, price_cents) values (%L, 'Intrus', 'piece', 100)$$, :'m1shop'), 'Personne d''autre n''ajoute de produit');

-- ---------- Client : autour de moi et recherche ----------
select t.login(:'c1');
select t.ok((select count(*) from nearby_shops(48.93, 2.35, 5)) = 1, 'Le commerce validé apparaît autour du client');
select t.ok((select distance_km between 0.5 and 1.5 and best_discount = 10 from nearby_shops(48.93, 2.35, 5)), 'Distance et meilleure remise affichées');
select t.ok((select count(*) from nearby_shops(48.80, 2.20, 5)) = 0, 'Trop loin : pas affiché');
select t.ok((select count(*) from nearby_shops(48.93, 2.35, 5, 'restaurant')) = 0, 'Filtre par type de commerce');
select t.ok((select count(*) from nearby_shops(null, null, null, null, t.z('Seine-Saint-Denis (93)'))) = 1, 'Liste par département sans position');
select t.ok((select final_cents from search_products('AGNEAU', 48.93, 2.35)) = 1791, 'Recherche : gigot à 19,90 € moins 10 % = 17,91 €');
select t.ok((select count(*) from search_products('merguéz')) = 1, 'Recherche sans accents');
select t.ok((select count(*) from search_products('m')) = 0, 'Recherche trop courte ignorée');
select t.login(null);
set role anon;
select t.ok((select count(*) from nearby_shops(48.93, 2.35, 5)) = 1, 'Sans compte : on peut voir les commerces');
select t.ok((select name from shops where id = :'m1shop') = 'Boucherie Al Baraka', 'Sans compte : fiche publique lisible');
select t.fails(format($$select siret from shops where id = %L$$, :'m1shop'), 'Sans compte : SIRET et champs internes non lisibles');
select t.fails(format($$select * from create_voucher(%L)$$, :'m1shop'), 'Sans compte : pas de bon');
set role authenticated;

-- ---------- Bon de réduction ----------
select t.login(:'m1');
select t.throws(format($$select * from create_voucher(%L)$$, :'m1shop'), 'OWN_SHOP', 'Pas de bon dans son propre commerce');
select t.login(:'c1');
select id as v1, code as v1code from create_voucher(:'m1shop') \gset
select t.ok(:'v1code' ~ '^[A-Z2-9]{8}$', 'Code du bon : 8 caractères faciles à lire');
select t.ok((select id from create_voucher(:'m1shop')) = :'v1', 'Redemander un bon : le même est rendu');
select t.ok((select expires_at between now() + interval '23 hours' and now() + interval '25 hours' from vouchers where id = :'v1'), 'Bon valable 24 h');
select t.fails(format($$insert into vouchers (code, client_id, shop_id, expires_at) values ('ABCDEFGH', %L, %L, now() + interval '1 day')$$, :'c1', :'m1shop'), 'Pas de bon créé à la main');

-- ---------- Scan en caisse ----------
select t.login(:'m2');
select t.throws(format($$select merchant_scan(%L, 1000)$$, :'v1code'), 'NO_SHOP', 'Sans commerce : pas de scan');
insert into shops (owner_id, name, kind, zone_id, address, lat, lng) values (:'m2', 'Resto Le Bosphore', 'restaurant', t.z('Paris (75)'), '5 rue du Faubourg, Paris', 48.87, 2.35);
select id as m2shop from shops where owner_id = :'m2' \gset
select t.throws(format($$select merchant_scan(%L, 1000)$$, :'v1code'), 'SHOP_NOT_ACTIVE', 'Commerce non validé : pas de scan');
select t.login(:'admin');
select admin_set_shop_status(:'m2shop', 'active');
select t.login(:'m2');
select t.throws(format($$select merchant_scan(%L, 1000)$$, :'v1code'), 'WRONG_SHOP', 'Bon d''un autre commerce refusé');
select t.login(:'m1');
select t.throws($$select merchant_scan('ZZZZZZZZ', 1000)$$, 'NOT_FOUND', 'Code inconnu refusé');
select t.throws(format($$select merchant_scan(%L, 0)$$, :'v1code'), 'BAD_AMOUNT', 'Montant nul refusé');
select t.throws(format($$select merchant_scan(%L, 9000000)$$, :'v1code'), 'BAD_AMOUNT', 'Montant trop élevé refusé');
select merchant_scan(lower(:'v1code'), 1900) as scan1 \gset
select t.ok((:'scan1'::jsonb->>'commission_cents')::int = 95 and (:'scan1'::jsonb->>'free')::boolean,
            'Achat de 19,00 € : commission 0,95 €, offerte pendant le lancement');
select t.ok((select status from vouchers where id = :'v1') = 'used', 'Bon utilisé');
select t.throws(format($$select merchant_scan(%L, 1900)$$, :'v1code'), 'ALREADY_USED', 'Un bon ne sert qu''une fois');
select t.login(:'c1');
select id as v2code from create_voucher(:'m1shop') \gset
select code as v2code from vouchers where id = :'v2code' \gset
select t.login(:'m1');
select t.throws(format($$select merchant_scan(%L, 500)$$, :'v2code'), 'TOO_SOON', 'Deux achats du même client en 2 h : refusé');

-- ---------- Confirmation par le client ----------
select t.login(:'c2');
select t.ok((select count(*) from purchases) = 0, 'Un autre client ne voit pas l''achat');
select t.login(:'c1');
select id as p1 from purchases where client_id = :'c1' \gset
select t.ok((whoami()->>'pending_purchases')::int = 1, 'Le client a un achat à confirmer');
select client_answer_purchase(:'p1', true);
select t.ok((select status from purchases where id = :'p1') = 'confirmed', 'Le client confirme le montant');
select t.throws(format($$select client_answer_purchase(%L, true)$$, :'p1'), 'NOT_FOUND', 'Déjà confirmé');
select t.fails(format($$update purchases set amount_cents = 1 where id = %L$$, :'p1'), 'Le client ne modifie pas le montant');

-- ---------- Après l'offre de lancement : commission due ----------
select t.login(:'admin');
update shops set free_until = paris_today() - 1 where id = :'m1shop';
select t.login(:'c2');
select code as v3code from create_voucher(:'m1shop') \gset
select t.login(:'m1');
select merchant_scan(:'v3code', 4000) as scan3 \gset
select t.ok((:'scan3'::jsonb->>'commission_cents')::int = 200 and not (:'scan3'::jsonb->>'free')::boolean, 'Achat de 40,00 € : commission 2,00 € due');
select t.login(:'c2');
select id as p3 from purchases where client_id = :'c2' \gset
select t.throws(format($$select client_answer_purchase(%L, false, 'x')$$, :'p3'), 'BAD_REASON', 'Contestation sans explication refusée');
select client_answer_purchase(:'p3', false, 'J''ai payé 30 €, pas 40 €');
select t.ok((select status from purchases where id = :'p3') = 'disputed' and exists (select 1 from reports where purchase_id = :'p3'), 'Contestation enregistrée et signalée');
select t.login(:'admin');
select t.ok((admin_summary()->>'disputes_open')::int = 1, 'Le fondateur voit la contestation');
select admin_resolve_purchase(:'p3', 'confirmed');
select t.ok((select status from purchases where id = :'p3') = 'confirmed' and not exists (select 1 from reports where purchase_id = :'p3' and status = 'open'),
            'Le fondateur tranche : achat confirmé, signalement clos');

select t.login(:'m1');
select t.ok((merchant_stats()->>'commission_due_cents')::int = 200 and (merchant_stats()->>'commission_offered_cents')::int = 95
            and (merchant_stats()->>'today_cents')::int = 5900 and (merchant_stats()->>'clients_count')::int = 2,
            'Compte du commerçant : ventes du jour, commission due et offerte');

-- ---------- Tâches automatiques et prélèvement de la semaine ----------
reset role;
select t.login(:'c1');
-- Un achat sans réponse depuis 25 h est confirmé tout seul
update purchases set created_at = now() - interval '3 hours' where id = :'p1';
insert into vouchers (id, code, client_id, shop_id, expires_at, status) values ('cccccccc-0000-0000-0000-000000000001', 'AUTOAUTO', :'c1', :'m2shop', now() + interval '1 day', 'used');
insert into purchases (id, voucher_id, shop_id, client_id, amount_cents, discount_pct, commission_rate, commission_cents, free, week_start, created_at)
values ('cccccccc-0000-0000-0000-0000000000a1', 'cccccccc-0000-0000-0000-000000000001', :'m2shop', :'c1', 1000, 5, 5, 50, false, week_of(now()) - 7, now() - interval '25 hours');
update vouchers set expires_at = now() - interval '1 minute' where code = :'v2code';
update purchases set week_start = week_of(now()) - 7 where id = :'p3';
select souki_deals_tick() as tick1 \gset
select t.ok((select status from purchases where id = 'cccccccc-0000-0000-0000-0000000000a1') = 'confirmed', 'Sans réponse en 24 h : achat confirmé automatiquement');
select t.ok((select count(*) from vouchers where status = 'expired') >= 1, 'Bons périmés expirés');
select t.ok((select amount_cents from charges where shop_id = :'m1shop') = 200 and (select amount_cents from charges where shop_id = :'m2shop') = 50,
            'Lundi : prélèvement de la semaine passée par commerce');
select souki_deals_tick();
select t.ok((select count(*) from charges) = 2 and (select amount_cents from charges where shop_id = :'m1shop') = 200, 'Pas de double prélèvement');
select t.ok((select charge_id is not null from purchases where id = :'p3'), 'Achat rattaché à son prélèvement');
-- Un prélèvement déjà payé n'est plus modifié : l'achat confirmé en retard attend le suivant
update charges set status = 'paid' where shop_id = :'m2shop';
insert into vouchers (id, code, client_id, shop_id, expires_at, status) values ('cccccccc-0000-0000-0000-000000000002', 'LATELATE', :'c2', :'m2shop', now() + interval '1 day', 'used');
insert into purchases (id, voucher_id, shop_id, client_id, amount_cents, discount_pct, commission_rate, commission_cents, free, status, week_start)
values ('cccccccc-0000-0000-0000-0000000000a2', 'cccccccc-0000-0000-0000-000000000002', :'m2shop', :'c2', 2000, 5, 5, 100, false, 'confirmed', week_of(now()) - 7);
select souki_deals_tick();
select t.ok((select amount_cents from charges where shop_id = :'m2shop') = 50 and (select charge_id is null from purchases where id = 'cccccccc-0000-0000-0000-0000000000a2'),
            'Prélèvement payé : non modifié, l''achat en retard attend le prochain');
update charges set status = 'pending' where shop_id = :'m2shop';
set role authenticated;

select t.login(:'m1');
select t.ok((select count(*) from charges) = 1, 'Le commerçant voit son prélèvement, pas celui des autres');
select t.ok((merchant_stats()->>'commission_due_cents')::int = 0, 'Commission due remise à zéro après prélèvement');
select t.login(:'c1');
select t.ok((select count(*) from charges) = 0, 'Un client ne voit aucun prélèvement');

-- Prélèvement refusé : commerce masqué jusqu'au paiement
select t.login(:'admin');
select id as ch1 from charges where shop_id = :'m1shop' \gset
select admin_set_charge_status(:'ch1', 'failed');
select t.login(:'c1');
select t.ok(not exists (select 1 from nearby_shops(48.93, 2.35, 5) where id = :'m1shop'), 'Prélèvement refusé : commerce masqué');
select t.throws(format($$select * from create_voucher(%L)$$, :'m1shop'), 'SHOP_UNAVAILABLE', 'Commerce masqué : pas de nouveau bon');
select t.login(:'admin');
select admin_set_charge_status(:'ch1', 'paid');
select t.login(:'c1');
select t.ok(exists (select 1 from nearby_shops(48.93, 2.35, 5) where id = :'m1shop'), 'Payé : commerce de nouveau visible');

-- ---------- Factures des commissions ----------
select t.login(:'admin');
select t.ok((admin_summary()->>'invoices_missing')::int = 1 and not (admin_summary()->>'company_ready')::boolean,
            'Prélèvement payé sans infos de la société : facture en attente');
select t.ok((select count(*) from invoices) = 0, 'Aucune facture tant que la société n''est pas renseignée');
select t.throws($$select admin_save_company('Souki Deals', 'SAS', null, '10 rue de la Paix, 75002 Paris', '123', null, null, null, 20, 'SD')$$,
                'BAD_SIRET', 'SIRET de la société vérifié');
select t.throws($$select admin_save_company('Souki Deals', 'SAS', null, '10 rue de la Paix, 75002 Paris', '98765432100012', null, null, null, 20, 'SD')$$,
                'BAD_VAT', 'TVA à 20 % : numéro de TVA obligatoire');
select t.login(:'m1');
select t.throws($$select admin_save_company('Pirate', 'SAS', null, '10 rue de la Paix, 75002 Paris', '98765432100012', null, null, null, 0, 'SD')$$,
                'NOT_ADMIN', 'Infos de la société réservées au fondateur');
select t.ok((select count(*) from company) = 0, 'Un commerçant ne lit pas les infos de la société');
select t.login(:'admin');
select t.ok((admin_save_company('Souki Deals', 'SAS', '1 000 €', '10 rue de la Paix, 75002 Paris', '987 654 321 00012',
             'RCS Paris 987 654 321', 'fr12987654321', 'factures@soukideals.fr', 20, 'SD')->>'issued')::int = 1,
            'Infos de la société enregistrées : la facture en attente est créée');
select id as inv1id, number as inv1 from invoices where charge_id = :'ch1' \gset
select t.ok(:'inv1' = 'SD-' || to_char(now() at time zone 'Europe/Paris', 'YYYY') || '-000001', 'Première facture numérotée SD-année-000001');
select t.ok((select amount_ttc_cents = 200 and amount_ht_cents = 167 and vat_cents = 33 and vat_rate = 20 from invoices where id = :'inv1id'),
            'Commission TTC 2,00 € = 1,67 € HT + 0,33 € de TVA');
select t.ok((select email_to = 'boucherie@test.fr' and email_status = 'pending' and email_attempts = 1
                    and buyer->>'siret' = '12345678901234' and seller->>'vat_number' = 'FR12987654321' and seller->>'siret' = '98765432100012'
                    and purchases_count = 1 and sales_cents = 4000 from invoices where id = :'inv1id'),
            'Facture : e-mail du commerçant, SIRET, TVA, ventes de la période');
select t.ok((admin_summary()->>'invoices_missing')::int = 0 and (admin_summary()->>'company_ready')::boolean, 'Plus de facture en attente');
select t.throws(format($$select admin_set_charge_status(%L, 'failed')$$, :'ch1'), 'INVOICED', 'Prélèvement facturé : statut figé');
-- Prélèvement payé : facture créée tout de suite, numéro suivant
select id as ch2 from charges where shop_id = :'m2shop' \gset
select admin_set_charge_status(:'ch2', 'paid');
select t.ok((select number = 'SD-' || to_char(now() at time zone 'Europe/Paris', 'YYYY') || '-000002' and amount_ttc_cents = 50
                    and amount_ht_cents = 42 and vat_cents = 8 and email_to = 'resto@test.fr' from invoices where charge_id = :'ch2'),
            'Paiement marqué : facture n° 2 créée automatiquement');
select id as inv2id from invoices where charge_id = :'ch2' \gset
select t.throws($$select admin_save_company('Souki Deals', 'SAS', null, '10 rue de la Paix, 75002 Paris', '98765432100012', null, 'FR12987654321', null, 20, 'FAC')$$,
                'INVOICE_LOCKED', 'Préfixe figé après la première facture');
select t.fails(format($$update invoices set amount_ttc_cents = 1 where id = %L$$, :'inv1id'), 'Une facture ne se modifie pas depuis l''appli');
-- Qui voit quoi
select t.login(:'m1');
select t.ok((select count(*) from invoices) = 1 and (select id from invoices) = :'inv1id', 'Le commerçant voit sa facture, pas celles des autres');
select t.throws(format($$select merchant_resend_invoice(%L)$$, :'inv1id'), 'TOO_SOON', 'Renvoi limité : une fois toutes les 10 minutes');
select t.throws(format($$select merchant_resend_invoice(%L)$$, :'inv2id'), 'NOT_FOUND', 'Pas de renvoi de la facture d''un autre');
select t.login(:'c1');
select t.ok((select count(*) from invoices) = 0, 'Un client ne voit aucune facture');
reset role;
-- Facture figée, même pour la base
select t.throws(format($$update invoices set amount_ttc_cents = 1 where id = %L$$, :'inv1id'), 'INVOICE_LOCKED', 'Montant d''une facture figé');
select t.throws(format($$delete from invoices where id = %L$$, :'inv1id'), 'INVOICE_LOCKED', 'Une facture ne se supprime pas');
select t.ok((select count(*) from net.calls where body->>'invoice_id' in (:'inv1id', :'inv2id')) = 2, 'Envoi par e-mail demandé pour chaque facture');
-- La fonction d'envoi marque la facture envoyée
update invoices set email_status = 'sent', email_sent_at = now(), pdf_path = :'m1shop' || '/' || number || '.pdf' where id = :'inv1id';
select t.ok((select email_status = 'sent' from invoices where id = :'inv1id'), 'Facture marquée envoyée par la fonction d''envoi');
update invoices set email_last_try = now() - interval '1 hour' where id = :'inv1id';
set role authenticated;
select t.login(:'m1');
select merchant_resend_invoice(:'inv1id');
select t.ok((select email_status = 'pending' and email_attempts = 1 from invoices where id = :'inv1id'), 'Le commerçant redemande sa facture par e-mail');
reset role;
-- Tâche automatique : nouvel essai, puis échec après 5 essais
update invoices set email_last_try = now() - interval '1 hour' where id = :'inv2id';
select souki_deals_tick();
select t.ok((select email_attempts = 2 from invoices where id = :'inv2id'), 'Nouvel essai d''envoi par la tâche automatique');
update invoices set email_attempts = 5, email_last_try = now() - interval '1 hour' where id = :'inv2id';
select souki_deals_tick();
select t.ok((select email_status = 'failed' from invoices where id = :'inv2id'), 'Après 5 essais : envoi en échec, visible du fondateur');
set role authenticated;
select t.login(:'admin');
select t.ok((admin_summary()->>'invoices_failed')::int = 1, 'Le fondateur voit l''échec d''envoi');
select admin_resend_invoice(:'inv2id');
select t.ok((select email_status = 'pending' and email_attempts = 1 from invoices where id = :'inv2id'), 'Le fondateur relance l''envoi');
-- Franchise en base de TVA : pas de TVA sur les factures suivantes
select admin_save_company('Souki Deals', 'SASU', null, '10 rue de la Paix, 75002 Paris', '98765432100012', null, null, null, 0, 'SD');
reset role;
insert into charges (shop_id, week_start, amount_cents) values (:'m1shop', week_of(now()) - 14, 300);
set role authenticated;
select t.login(:'admin');
select admin_set_charge_status((select id from charges where shop_id = :'m1shop' and amount_cents = 300), 'paid');
select t.ok((select number like '%-000003' and amount_ht_cents = 300 and vat_cents = 0 and vat_rate = 0 from invoices
             where charge_id = (select id from charges where shop_id = :'m1shop' and amount_cents = 300)),
            'Sans TVA (franchise) : HT = TTC');
select t.ok((select seller->>'vat_number' = 'FR12987654321' from invoices where id = :'inv1id'), 'Les anciennes factures gardent les infos du jour d''émission');

-- ---------- Conditions et relevé annuel ----------
select t.login(:'m1');
select t.ok((select terms_version = current_terms_version() and terms_accepted_at is not null and terms_commission_rate = 5 and terms_discount_min = 5
             from shops where id = :'m1shop'), 'Inscription : version, date et taux des conditions enregistrés par le serveur');
update shops set terms_version = 'faux', terms_accepted_at = '2000-01-01', terms_commission_rate = 0 where id = :'m1shop';
select t.ok((select terms_version = current_terms_version() and terms_commission_rate = 5 from shops where id = :'m1shop'),
            'Le commerçant ne modifie pas ses conditions à la main');
reset role;
select set_config('souki.accept_terms', 'on', false);
update shops set terms_version = '2026-10-11' where id = :'m1shop';
select set_config('souki.accept_terms', '', false);
select t.ok((select terms_version = '2026-10-11' from shops where id = :'m1shop'), 'Ancienne version (simulée)');
set role authenticated;
select t.login(:'m1');
select merchant_accept_terms();
select t.ok((select terms_version = current_terms_version() from shops where id = :'m1shop'), 'Le commerçant accepte la nouvelle version');
select merchant_year_statement(extract(year from now() at time zone 'Europe/Paris')::int) as st1 \gset
select t.ok((:'st1'::jsonb->>'year')::int = extract(year from now() at time zone 'Europe/Paris')::int
            and :'st1'::jsonb->'shop'->>'siret' = '12345678901234'
            and :'st1'::jsonb->'seller'->>'legal_name' = 'Souki Deals', 'Relevé : commerce et société');
select t.ok(jsonb_array_length(:'st1'::jsonb->'invoices') = 2
            and (select sum((x->>'amount_ttc_cents')::int) from jsonb_array_elements(:'st1'::jsonb->'invoices') x) = 500
            and (select sum((x->>'vat_cents')::int) from jsonb_array_elements(:'st1'::jsonb->'invoices') x) = 33,
            'Relevé : les 2 factures du commerce (5,00 € TTC dont 0,33 € de TVA)');
select t.ok(jsonb_array_length(:'st1'::jsonb->'months') = 12
            and (select sum((x->>'ttc_cents')::int) from jsonb_array_elements(:'st1'::jsonb->'months') x) = 500,
            'Relevé : 12 mois, total des mois = total des factures');
select t.ok(not exists (select 1 from jsonb_array_elements(:'st1'::jsonb->'purchases') x where x->>'status' = 'cancelled')
            and (select bool_and((x->>'discount_cents')::int >= 0) from jsonb_array_elements(:'st1'::jsonb->'purchases') x),
            'Relevé : achats sans les annulés, remise calculée');
select t.ok((select (x->>'discount_cents')::int from jsonb_array_elements(:'st1'::jsonb->'purchases') x where (x->>'amount_cents')::int = 1900 limit 1) = 100,
            'Remise : 19,00 € payés avec 5 % = 1,00 € de remise');
select t.ok((select x->>'invoice' from jsonb_array_elements(:'st1'::jsonb->'purchases') x where (x->>'amount_cents')::int = 4000) = :'inv1',
            'Chaque achat facturé indique son n° de facture');
select t.throws($$select merchant_year_statement(1990)$$, 'BAD_YEAR', 'Année invalide refusée');
select t.login(:'m2');
select t.ok(jsonb_array_length(merchant_year_statement(extract(year from now() at time zone 'Europe/Paris')::int)->'invoices') = 1,
            'Chaque commerçant ne voit que son relevé');
select t.login(:'c1');
select t.throws($$select merchant_year_statement(2026)$$, 'NO_SHOP', 'Un client n''a pas de relevé');
select t.throws($$select merchant_accept_terms()$$, 'NO_SHOP', 'Un client n''accepte pas de conditions commerçant');

-- ---------- Scan inversé : le client scanne le QR code du magasin ----------
select t.login(:'m2');
select shop_code as m2code from shops where id = :'m2shop' \gset
select t.ok(:'m2code' ~ '^[A-Z2-9]{8}$' and (select count(distinct shop_code) = count(*) from shops), 'Chaque commerce a un code fixe et unique');
update shops set shop_code = 'AAAAAAAA' where id = :'m2shop';
select t.ok((select shop_code from shops where id = :'m2shop') = :'m2code', 'Le commerçant ne change pas son code');
select t.throws($$select client_checkin('SOUKIDEALS:SHOP:' || shop_code) from shops where owner_id = auth.uid()$$, 'OWN_SHOP', 'Pas de visite dans son propre commerce');
select t.login(:'c1');
select t.throws($$select client_checkin('SOUKIDEALS:SHOP:ZZZZZZZZ')$$, 'NOT_FOUND', 'QR code inconnu refusé');
select client_checkin('SOUKIDEALS:SHOP:' || :'m2code') as ck1 \gset
select (:'ck1'::jsonb->>'checkin_id') as ck1id, (:'ck1'::jsonb->>'code') as ck1code \gset
select t.ok(:'ck1'::jsonb->>'status' = 'waiting' and (:'ck1'::jsonb->>'discount_pct')::numeric = 5, 'Visite enregistrée, en attente du montant');
select t.ok((client_checkin(lower(:'m2code'))->>'checkin_id') = :'ck1id', 'Rescanner : même visite (code seul accepté)');
select t.login(:'m2');
select t.ok((select count(*) = 1 and min(first_name) = 'Karim' and min(code) = :'ck1code' from merchant_checkins()), 'La tablette voit le client présent (prénom seulement)');
select t.login(:'m1');
select t.ok((select count(*) from merchant_checkins()) = 0, 'Un autre commerce ne voit pas ce client');
select t.throws(format($$select merchant_complete_checkin(%L, 1000)$$, :'ck1id'), 'NOT_FOUND', 'Un autre commerce ne saisit pas le montant');
select t.login(:'m2');
select t.throws(format($$select merchant_complete_checkin(%L, 0)$$, :'ck1id'), 'BAD_AMOUNT', 'Montant vérifié comme au scan');
select merchant_complete_checkin(:'ck1id', 2500);
select t.ok((select status = 'done' and purchase_id is not null from checkins where id = :'ck1id')
            and (select status = 'used' from vouchers where code = :'ck1code')
            and (select amount_cents = 2500 and status = 'pending' and client_id = :'c1' from purchases where id = (select purchase_id from checkins where id = :'ck1id')),
            'Montant saisi : achat créé, bon utilisé, le client doit confirmer');
select t.throws(format($$select merchant_complete_checkin(%L, 2500)$$, :'ck1id'), 'ALREADY_DONE', 'Pas deux fois le même achat');
select t.login(:'c1');
select t.throws(format($$select client_checkin(%L)$$, :'m2code'), 'TOO_SOON', 'Nouvelle visite trop tôt après un achat');
-- Le commerçant dit « pas d'achat » : le client répond
select shop_code as m1code from shops where id = :'m1shop' \gset
select (client_checkin(:'m1code')->>'checkin_id') as ck2id \gset
select t.login(:'m1');
select merchant_dismiss_checkin(:'ck2id');
select t.login(:'c1');
select t.ok((whoami()->>'visits_to_answer')::int = 1, 'Le client doit dire s''il a acheté');
select client_answer_checkin(:'ck2id', true);
select t.ok((select client_answer = 'bought' from checkins where id = :'ck2id'), 'Le client dit avoir acheté');
select t.throws(format($$select client_answer_checkin(%L, false)$$, :'ck2id'), 'NOT_FOUND', 'Une seule réponse');
select t.login(:'admin');
select t.ok(exists (select 1 from reports where shop_id = :'m1shop' and kind = 'achat' and body like 'Achat sans scan%' and status = 'open'),
            'Achat sans scan : signalement pour le fondateur');
select t.ok((select level = 'orange' and claimed = 1 from admin_shop_scores() where shop_id = :'m1shop'), 'Score de méfiance : commerce en orange');
select t.ok((select level = 'ok' from admin_shop_scores() where shop_id = :'m2shop'), 'Commerce sans souci : ok');
select admin_close_report((select id from reports where body like 'Achat sans scan%' and status = 'open'));
-- Visite sans montant à temps : expirée, le bon ne resert pas
select t.login(:'c1');
select (client_checkin(:'m1code')->>'checkin_id') as ck3id \gset
select t.ok(:'ck3id' <> :'ck2id', 'Nouvelle visite après un « pas d''achat »');
reset role;
update checkins set expires_at = now() - interval '1 minute' where id = :'ck3id';
select souki_deals_tick();
select t.ok((select status = 'expired' from checkins where id = :'ck3id')
            and (select v.status = 'expired' from vouchers v join checkins c on c.voucher_id = v.id where c.id = :'ck3id'),
            'Visite sans montant à temps : expirée avec son bon');
set role authenticated;
select t.login(:'c1');
select client_answer_checkin(:'ck3id', false);
select t.ok((select count(*) from reports where shop_id = :'m1shop' and body like 'Achat sans scan%') = 1, '« Pas acheté » : aucun signalement');
-- Le client annule ; puis le scan classique du bon clôt la visite
select (client_checkin(:'m1code')->>'checkin_id') as ck4id \gset
select client_cancel_checkin(:'ck4id');
select t.ok((select status = 'cancelled' from checkins where id = :'ck4id'), 'Le client annule sa visite');
select client_checkin(:'m1code') as ck5 \gset
select t.login(:'m1');
select merchant_scan(:'ck5'::jsonb->>'code', 1200);
select t.ok((select status = 'done' from checkins where id = (:'ck5'::jsonb->>'checkin_id')::uuid), 'Scan classique du bon : la visite est close');
select t.login(:'c2');
select t.ok((select count(*) from checkins) = 0, 'Un autre client ne voit pas ces visites');
select t.throws($$select * from admin_shop_scores()$$, 'NOT_ADMIN', 'Score réservé au fondateur');

-- ---------- Nombre d'inscrits ----------
select t.login(:'admin');
select admin_members() as mb \gset
select t.ok((:'mb'::jsonb->'clients'->>'total')::int = 2 and (:'mb'::jsonb->'clients'->>'active_30d')::int = 2
            and (:'mb'::jsonb->'clients'->>'unconfirmed')::int = 1,
            'Inscrits : 2 particuliers vérifiés (sans commerçants ni fondateur), actifs, 1 compte non vérifié');
select t.ok((:'mb'::jsonb->'shops'->>'total')::int = 2 and (:'mb'::jsonb->'shops'->>'active')::int = 2 and (:'mb'::jsonb->'shops'->>'launch_offer')::int = 2,
            'Inscrits : 2 commerces actifs avec l''offre de lancement');
select t.ok(jsonb_array_length(:'mb'::jsonb->'weeks') = 12
            and (select sum((x->>'clients')::int) from jsonb_array_elements(:'mb'::jsonb->'weeks') x) = 2,
            'Inscriptions des 12 dernières semaines');
select t.ok((select (x->>'shops')::int from jsonb_array_elements(:'mb'::jsonb->'by_zone') x where x->>'zone' = 'Seine-Saint-Denis (93)') >= 1,
            'Commerces par département');
select t.login(:'m1');
select t.throws($$select admin_members()$$, 'NOT_ADMIN', 'Nombre d''inscrits réservé au fondateur');

-- ---------- Offre de bienvenue (payée par Souki Deals) ----------
reset role;
insert into auth.users (id, email, email_confirmed_at) values
  ('bbbbbbbb-0000-0000-0000-000000000031', 'nouveau1@test.fr', now()),
  ('bbbbbbbb-0000-0000-0000-000000000032', 'nouveau2@test.fr', now()),
  ('bbbbbbbb-0000-0000-0000-000000000033', 'nouveau3@test.fr', now());
insert into profiles (id, full_name, phone) values
  ('bbbbbbbb-0000-0000-0000-000000000031', 'Samir N.', '06 11 22 33 44'),
  ('bbbbbbbb-0000-0000-0000-000000000032', 'Samir bis', '0611223344'),
  ('bbbbbbbb-0000-0000-0000-000000000033', 'Nora K.', null);
update purchases set status = 'confirmed' where status = 'pending';
set role authenticated;
select t.login(:'admin');
select admin_update_welcome(true, 1000, 3000, 2);
select t.ok((admin_promo_stats()->>'welcome_used')::int = 0, 'Bienvenue : aucune utilisée');
select t.throws($$select admin_update_welcome(true, 99999, 3000, 2)$$, 'BAD_SETTINGS', 'Bienvenue : montant trop élevé refusé');
select t.login('bbbbbbbb-0000-0000-0000-000000000031');
select t.ok((client_welcome()->>'amount_cents')::int = 1000 and (client_welcome()->>'min_cents')::int = 3000, 'Nouveau client : -10 € dès 30 €');
select code as wcode from create_voucher(:'m2shop') \gset
select t.login(:'m2');
select t.ok((merchant_voucher_info(:'wcode')->>'welcome_cents')::int = 1000, 'En caisse : le commerçant voit les 10 € à déduire');
select merchant_scan(:'wcode', 1500) as w1 \gset
select t.ok((:'w1'::jsonb->>'welcome_cents')::int = 0, 'Achat trop petit (15 € + 10 € < 30 €) : pas de bienvenue');
reset role;
delete from purchases where (:'w1'::jsonb->>'purchase_id')::uuid = id;
update vouchers set status = 'active' where code = :'wcode';
set role authenticated;
select merchant_scan(:'wcode', 2500) as w2 \gset
select t.ok((:'w2'::jsonb->>'welcome_cents')::int = 1000 and (:'w2'::jsonb->>'commission_cents')::int = 175,
            'Achat de 25 € payés + 10 € de bienvenue : commission sur 35 € = 1,75 €');
select t.login('bbbbbbbb-0000-0000-0000-000000000031');
select t.ok((client_welcome()->>'amount_cents')::int = 0, 'Bienvenue : une seule fois par client');
select t.login('bbbbbbbb-0000-0000-0000-000000000032');
select t.ok((client_welcome()->>'amount_cents')::int = 0, 'Même numéro de téléphone : pas de deuxième bienvenue');
select t.login('bbbbbbbb-0000-0000-0000-000000000033');
select t.ok((client_welcome()->>'amount_cents')::int = 1000, 'Autre client : bienvenue disponible');
select code as wcode3 from create_voucher(:'m2shop') \gset
select t.login(:'m2');
select merchant_scan(:'wcode3', 4000);
select t.login('bbbbbbbb-0000-0000-0000-000000000033');
select t.ok((client_welcome()->>'amount_cents')::int = 0, 'Après usage : plus de bienvenue');
select t.login(:'admin');
select t.ok((admin_promo_stats()->>'welcome_used')::int = 2 and (admin_promo_stats()->>'welcome_cost_cents')::int = 2000, 'Fondateur : 2 bienvenues, 20 € de coût');
select admin_update_welcome(true, 1000, 3000, 2);
reset role;
insert into auth.users (id, email, email_confirmed_at) values ('bbbbbbbb-0000-0000-0000-000000000034', 'nouveau4@test.fr', now());
set role authenticated;
select t.login('bbbbbbbb-0000-0000-0000-000000000034');
select t.ok((client_welcome()->>'amount_cents')::int = 0, 'Places de bienvenue épuisées : offre arrêtée');
select t.login(:'m2');
select t.ok((merchant_stats()->>'welcome_credit_cents')::int = 0, 'Achats en attente de confirmation : rien à rembourser encore');
-- Prélèvement : commission − bienvenue ; en faveur du commerçant si négatif
reset role;
update purchases set status = 'confirmed', week_start = week_of(now()) where welcome_cents > 0 or (status = 'pending' and shop_id = :'m2shop');
delete from charges where shop_id = :'m2shop' and status = 'pending';
update shops set free_until = paris_today() + 30 where id = :'m2shop';
update purchases set free = true, week_start = week_of(now()) where shop_id = :'m2shop' and charge_id is null and status = 'confirmed';
select close_week(week_of(now()));
select t.ok((select amount_cents = -2000 and welcome_cents = 2000 and commission_cents = 0 from charges
             where shop_id = :'m2shop' and status = 'pending' and amount_cents < 0),
            'Offre de lancement + 2 bienvenues : Souki Deals doit 20 € au commerçant');
set role authenticated;
select t.login(:'c1');
select t.ok(shop_is_visible(:'m2shop') and not shop_is_blocked(:'m2shop'), 'Remboursement dû : le commerce reste visible');
select t.login(:'admin');
select t.ok((admin_promo_stats()->>'refunds_due_cents')::int = 2000, 'Fondateur : 20 € à rembourser');
select admin_set_charge_status((select id from charges where shop_id = :'m2shop' and amount_cents < 0), 'paid');
select t.ok(not exists (select 1 from invoices where charge_id = (select id from charges where shop_id = :'m2shop' and amount_cents < 0)),
            'Remboursement sans commission : pas de facture');
select admin_update_welcome(false, 1000, 3000, 100);

-- ---------- Promos du commerçant ----------
select t.login(:'m1');
select t.throws($$select merchant_save_promo('flash', 'Gigot', 5, null, 0)$$, 'BAD_PROMO', 'Offre flash : pas moins que la remise du commerce');
select t.throws($$select merchant_save_promo('flash', 'Gigot', 30, null, 9)$$, 'BAD_PROMO', 'Offre flash : 7 jours au plus');
select t.throws($$select merchant_save_promo('gift', 'Pain', null, 50, 3)$$, 'BAD_PROMO', 'Produit offert : montant minimum vérifié');
select merchant_save_promo('flash', 'Gigot d''agneau', 20, null, 0) as pr1 \gset
select merchant_save_promo('gift', 'Pain', null, 2000, 7);
select t.ok((select count(*) from promos where shop_id = :'m1shop' and active) = 2
            and (select ends_at = ((paris_today() + 1)::timestamp at time zone 'Europe/Paris') from promos where id = :'pr1'),
            'Promos créées ; l''offre flash finit ce soir à minuit');
select merchant_save_promo('flash', 'Merguez', 15, null, 1);
select t.throws($$select merchant_save_promo('flash', 'Poulet', 15, null, 0)$$, 'TOO_MANY', '3 promos au plus');
select t.login(:'c1');
select t.ok((select count(*) from active_promos(48.93, 2.35, 10) where shop_id = :'m1shop') = 3
            and (select kind from active_promos(48.93, 2.35, 10) limit 1) = 'flash', 'Le client voit les promos autour de lui, flash d''abord');
select t.ok((select count(*) from active_promos(43.3, 5.4, 10)) = 0, 'Trop loin : aucune promo');
select t.throws(format($$select merchant_stop_promo(%s)$$, :'pr1'), 'NOT_FOUND', 'Un client n''arrête pas une promo');
select t.login(:'m1');
select merchant_stop_promo(:'pr1');
select t.login(null);
set role anon;
select t.ok((select count(*) from active_promos(null, null, null) where id = :'pr1') = 0 and (select count(*) from promos where shop_id = :'m1shop') = 2,
            'Promo arrêtée : invisible, même sans compte');
set role authenticated;

-- ---------- IBAN du commerçant ----------
select t.login(:'m2');
select t.throws($$select merchant_save_bank('Resto SARL', 'FR76 3000 6000 0112 3456 7890 188')$$, 'BAD_IBAN', 'IBAN avec une mauvaise clé refusé');
select t.throws($$select merchant_save_bank('Resto SARL', 'FR76 3000 6000 0112 3456 7890')$$, 'BAD_IBAN', 'IBAN trop court refusé');
select merchant_save_bank('Resto SARL', 'fr76 3000 6000 0112 3456 7890 189', 'agrifrpp');
select t.ok((select iban = 'FR7630006000011234567890189' and bic = 'AGRIFRPP' from shop_bank), 'IBAN valide enregistré, sans espaces');
reset role;
select t.ok(iban_valid('DE89370400440532013000') and iban_valid('BE68539007547034'), 'IBAN allemand et belge reconnus');
set role authenticated;
select t.login(:'m1');
select t.ok((select count(*) from shop_bank) = 0, 'Un autre commerçant ne voit pas cet IBAN');
select t.login(:'c1');
select t.ok((select count(*) from shop_bank) = 0, 'Un client ne voit aucun IBAN');
select t.throws($$select merchant_save_bank('Pirate', 'FR7630006000011234567890189')$$, 'NO_SHOP', 'Un client n''enregistre pas d''IBAN');
select t.login(:'admin');
select t.ok((select count(*) from shop_bank where shop_id = :'m2shop') = 1, 'Le fondateur voit l''IBAN pour rembourser');

-- ---------- Notifications ----------
select t.login(:'m1');
select t.throws($$select register_push_token('nimporte quoi')$$, 'BAD_TOKEN', 'Jeton invalide refusé');
select register_push_token('ExponentPushToken[commercant-m1]');
select t.login(:'c1');
select register_push_token('ExponentPushToken[client-c1]');
select t.ok((select count(*) from push_tokens) = 1, 'Chacun ne voit que son propre jeton');
-- Client présent : le commerçant est prévenu (en arabe s'il l'a choisi)
reset role;
update profiles set lang = 'fr' where id = :'c1';
delete from purchases where client_id = :'c1' and shop_id = :'m1shop';
set role authenticated;
select (client_checkin(:'m1code')->>'checkin_id') as nck \gset
select t.login(:'m1');
select t.ok(exists (select 1 from notifications where key = 'client_present' and body like 'Karim a scanné%' and sent),
            'Client présent : le commerçant reçoit « Karim a scanné votre QR code »');
select merchant_complete_checkin(:'nck', 1234);
select t.login(:'c1');
select t.ok(exists (select 1 from notifications where key = 'purchase_to_confirm' and body = 'Vous avez payé 12,34 € chez Boucherie Al Baraka ?'),
            'Achat saisi : le client doit confirmer 12,34 €');
select client_answer_purchase((select id from purchases where amount_cents = 1234), false, 'Pas ce montant');
select t.login(:'m1');
select t.ok(exists (select 1 from notifications where key = 'purchase_disputed' and body like '%12,34 €%'), 'Achat contesté : le commerçant est prévenu');
select t.login(:'admin');
select admin_resolve_purchase((select id from purchases where amount_cents = 1234), 'cancelled');
reset role;
select t.ok((select count(*) from net.calls where body::text like '%commercant-m1%') >= 2, 'Envoi vers le téléphone du commerçant demandé');
set role authenticated;
-- Offre flash : clients proches, une seule par jour, désactivable
select t.login(:'c1');
select set_my_area(48.93712, 2.35815);
select t.ok((select area_lat = 48.94 and area_lng = 2.36 from profiles where id = auth.uid()), 'Position arrondie à environ 1 km');
select t.login(:'c2');
insert into profiles (id, full_name) values (auth.uid(), 'Yasmine') on conflict (id) do nothing;
select set_my_area(43.30, 5.37);
select t.login(:'m1');
select merchant_stop_promo(id) from promos where shop_id = :'m1shop' and active;
select merchant_save_promo('flash', 'Côtelettes', 25, null, 0);
select t.login(:'c1');
select t.ok(exists (select 1 from notifications where key = 'flash_nearby' and body like 'Boucherie Al Baraka : Côtelettes à -25 %%'),
            'Offre flash : le client proche est prévenu');
select t.login(:'c2');
select t.ok(not exists (select 1 from notifications where key = 'flash_nearby'), 'Client loin (Marseille) : pas prévenu');
select t.login(:'m1');
select merchant_save_promo('flash', 'Merguez maison', 30, null, 0);
select t.login(:'c1');
select t.ok((select count(*) from notifications where key = 'flash_nearby') = 1, 'Une seule offre flash par jour au plus');
select set_my_notif_promos(false);
select t.ok((select not notif_promos from profiles where id = auth.uid()), 'Le client peut couper les offres');
-- Remboursement versé
select t.login(:'m2');
select t.ok(exists (select 1 from notifications where key = 'refund_sent' and body like '%20,00 €%'), 'Remboursement : le commerçant est prévenu');

-- ---------- Suppression du compte ----------
select t.login(:'admin');
select t.throws($$select delete_my_account()$$, 'NOT_ALLOWED', 'Le compte du fondateur ne se supprime pas');
select t.login(:'m1');
select t.throws($$select delete_my_account()$$, 'BALANCE_DUE', 'Commerçant avec des commissions en cours : suppression refusée');
select t.login('bbbbbbbb-0000-0000-0000-000000000031');
select count(*) as nb31 from purchases where client_id = 'bbbbbbbb-0000-0000-0000-000000000031' \gset
select delete_my_account();
reset role;
select t.ok(not exists (select 1 from auth.users where id = 'bbbbbbbb-0000-0000-0000-000000000031')
            and not exists (select 1 from profiles where id = 'bbbbbbbb-0000-0000-0000-000000000031'),
            'Compte client supprimé avec son profil');
select t.ok((select count(*) from purchases where welcome_cents > 0 and client_id is null) >= 1 and :'nb31'::int >= 1,
            'Ses achats restent pour les commerçants, sans son nom');
set role authenticated;

-- ---------- Photos des produits ----------
select t.login(:'m1');
select id as gigot from products where shop_id = :'m1shop' and name = 'Gigot d''agneau' \gset
update products set photo_path = 'products/' || :'m1shop' || '/gigot-1.jpg' where id = :'gigot';
select t.ok((select photo_path = 'products/' || :'m1shop' || '/gigot-1.jpg' from products where id = :'gigot'), 'Photo ajoutée à un produit frais');
select t.throws(format($$update products set photo_path = 'products/%s/x.jpg' where id = %s$$, :'m2shop', :'gigot'), 'BAD_PHOTO',
                'Photo rangée dans le dossier d''un autre commerce : refusée');
insert into products (shop_id, name, unit, price_cents, packaged, photo_path)
values (:'m1shop', 'Lait demi-écrémé 1 L', 'piece', 115, true, 'products/' || :'m1shop' || '/lait.jpg');
select t.ok((select photo_path is null from products where name = 'Lait demi-écrémé 1 L'), 'Produit emballé (lait) : pas de photo');
insert into storage.objects (bucket_id, name) values ('photos', 'products/' || :'m1shop' || '/gigot-2.jpg');
select t.fails(format($$insert into storage.objects (bucket_id, name) values ('photos', 'products/%s/pirate.jpg')$$, :'m2shop'),
               'Pas d''envoi de photo dans le dossier d''un autre commerce');
select t.login(:'c1');
select t.ok((select photo_path is not null from products where id = :'gigot'), 'Le client voit la photo');
select t.ok(report_create(:'m1shop', 'photo', 'Photo qui ne correspond pas', :'gigot') > 0, 'Le client peut signaler une photo');
select t.throws(format($$select admin_remove_product_photo(%s)$$, :'gigot'), 'NOT_ADMIN', 'Seul le fondateur retire une photo');
select t.login(:'admin');
select admin_remove_product_photo(:'gigot');
select t.ok((select photo_path is null from products where id = :'gigot')
            and not exists (select 1 from reports where kind = 'photo' and status = 'open'), 'Photo retirée, signalement traité');

-- ---------- Limites ----------
select t.login(:'admin');
select admin_update_settings(5, 5, 24, 1, 120, 50000, 24, 150, 3);
select t.throws($$select admin_update_settings(5, 40, 24, 5, 120, 50000, 24, 150, 3)$$, 'BAD_SETTINGS', 'Commission de 40 % refusée');
select t.login(:'c2');
select * from create_voucher(:'m2shop');
select t.throws(format($$select * from create_voucher(%L)$$, :'m1shop'), 'TOO_MANY', 'Nombre de bons actifs limité');
select cancel_voucher((select id from vouchers where client_id = :'c2' and status = 'active'));
select t.ok((select count(*) from vouchers where client_id = :'c2' and status = 'active') = 0, 'Le client annule son bon');
select t.login(:'admin');
select admin_update_settings(5, 5, 24, 5, 120, 50000, 24, 150, 3);

-- ---------- Signalements ----------
select t.login(:'c1');
select t.throws(format($$select report_create(%L, 'spam', 'texte')$$, :'m1shop'), 'BAD_KIND', 'Type de signalement inconnu refusé');
select t.ok(report_create(:'m1shop', 'prix', 'Le gigot est à 22 € en magasin', (select id from products where name = 'Gigot d''agneau')) > 0, 'Prix faux signalé');
select t.login(:'admin');
select t.ok((admin_summary()->>'reports_open')::int = 1, 'Le fondateur voit le signalement');
select admin_close_report((select id from reports where status = 'open' limit 1));
select t.ok((admin_summary()->>'reports_open')::int = 0, 'Signalement traité');

-- ---------- Zones ----------
select admin_set_zone_open(t.z('Seine-Saint-Denis (93)'), false);
select t.login(:'c1');
select t.ok(not exists (select 1 from nearby_shops(48.93, 2.35, 5)), 'Zone fermée : commerces invisibles');
select t.login(:'admin');
select admin_set_zone_open(t.z('Seine-Saint-Denis (93)'), true);

-- ---------- Résumé ----------
select t.ok((admin_summary()->>'shops_active')::int = 2 and (admin_summary()->>'launch_slots_left')::int = 148, 'Résumé du fondateur');
select t.login(:'c1');
select t.throws($$select merchant_stats()$$, 'NO_SHOP', 'Un client n''a pas de tableau de commerçant');

-- ---------- Notifications complètes (013) ----------
reset role;
select t.ok(exists (select 1 from notifications where key = 'visit_closed' and body like 'Votre visite chez %'), 'Visite sans montant : le client est prévenu');
select t.ok(exists (select 1 from notifications where key = 'photo_removed' and body like '%Gigot%'), 'Photo retirée : le commerçant est prévenu');
select t.ok(exists (select 1 from notifications n where key = 'admin_new_shop' and n.user_id = :'admin'), 'Nouveau commerce : le fondateur est prévenu');
select t.ok(exists (select 1 from notifications n where key = 'admin_new_report' and n.user_id = :'admin'), 'Nouveau signalement : le fondateur est prévenu');
select t.ok((select count(*) from notifications where key = 'invoice_issued') = (select count(*) from invoices where shop_id is not null)
            and exists (select 1 from invoices), 'Chaque facture : le commerçant est prévenu');
select t.login(:'admin');
select admin_set_shop_status(:'m2shop', 'suspended');
select admin_set_shop_status(:'m2shop', 'active');
reset role;
select t.ok(exists (select 1 from notifications n join shops s on s.owner_id = n.user_id where s.id = :'m2shop' and key = 'shop_suspended')
            and exists (select 1 from notifications n join shops s on s.owner_id = n.user_id where s.id = :'m2shop' and key = 'shop_back'),
            'Commerce suspendu puis remis en ligne : le commerçant est prévenu');
select t.ok(not exists (select 1 from notifications where key in ('visit_closed', 'admin_new_shop') and (title is null or body like '%{%')),
            'Textes des notifications complets');

-- ---------- E-mails d'authentification (014) ----------
reset role;
select t.ok((public.deals_send_auth_email('{"user":{"email":"a@b.fr"},"email_data":{"email_action_type":"signup","token_hash":"x"}}'::jsonb)->'error'->>'http_code') = '500',
            'Sans clé Resend : erreur claire');
insert into vault.decrypted_secrets (name, decrypted_secret) values ('resend_api_key', 're_test');
delete from net.calls;
select t.ok(public.deals_send_auth_email('{"user":{"email":"karim@test.fr","user_metadata":{"lang":"fr","espace":"commercant"}},"email_data":{"email_action_type":"signup","token_hash":"abc123","redirect_to":"https://soukideals.com/compte-confirme.html"}}'::jsonb) = '{}'::jsonb,
            'Inscription commerçant : e-mail envoyé');
select t.ok((select body->>'subject' = 'Confirmez votre adresse Souki Deals' and body->'to'->>0 = 'karim@test.fr'
                    and body->>'html' like '%verify?token=abc123&amp;type=signup&amp;redirect_to=https%3A%2F%2Fsoukideals.com%2Fcompte-confirme.html%'
                    and body->>'html' like '%votre commerce%' and body->>'html' not like '%\%\%URL%'
             from net.calls where url = 'https://api.resend.com/emails'), 'Lien de confirmation et texte commerçant corrects');
delete from net.calls;
select public.deals_send_auth_email('{"user":{"email":"sara@test.fr","user_metadata":{"lang":"ar"}},"email_data":{"email_action_type":"recovery","token_hash":"r1"}}'::jsonb);
select t.ok((select body->>'html' like '%dir="rtl"%' and body->>'html' like '%type=recovery%' from net.calls), 'Mot de passe oublié en arabe');
delete from net.calls;
select public.deals_send_auth_email('{"user":{"email":"old@test.fr","new_email":"new@test.fr"},"email_data":{"email_action_type":"email_change","token_hash":"n1","token_hash_new":"o1"}}'::jsonb);
select t.ok((select count(*) from net.calls) = 2 and exists (select 1 from net.calls where body->'to'->>0 = 'new@test.fr' and body->>'html' like '%new@test.fr%'),
            'Changement d''adresse : les deux adresses sont prévenues');
select t.ok(public.deals_send_auth_email('{"user":{"email":"a@b.fr"},"email_data":{"email_action_type":"reauthentication"}}'::jsonb) = '{}'::jsonb,
            'Autres cas : rien à envoyer, pas d''erreur');
select t.ok(not has_function_privilege('authenticated', 'public.deals_send_auth_email(jsonb)', 'execute')
            and has_function_privilege('supabase_auth_admin', 'public.deals_send_auth_email(jsonb)', 'execute'), 'Seul Supabase Auth appelle le hook');
delete from vault.decrypted_secrets;

-- ---------- Bon de l'offre choisie (016) ----------
reset role;
insert into auth.users (id, email, email_confirmed_at) values ('bbbbbbbb-0000-0000-0000-000000000023', 'client3@test.fr', now());
set role authenticated;
select t.login('bbbbbbbb-0000-0000-0000-000000000023');
insert into profiles (id, full_name) values (auth.uid(), 'Amina K.');
select (client_checkin('SOUKIDEALS:SHOP:' || (select shop_code from shops where id = :'m1shop'))->>'checkin_id') as ck3 \gset
reset role;
insert into promos (shop_id, kind, title, discount_pct, ends_at) values (:'m1shop', 'flash', 'Côtelettes', 25, now() + interval '1 day') returning id as prm \gset
set role authenticated;
select t.login('bbbbbbbb-0000-0000-0000-000000000023');
select t.throws(format($$select client_set_checkin_promo(%L, %s)$$, :'ck3', :'pr1'), 'PROMO_INVALID', 'Offre arrêtée : refusée');
select t.ok((client_set_checkin_promo(:'ck3', :'prm')->>'title') = 'Côtelettes', 'Le client choisit une offre du commerce');
-- ---------- Derniers inscrits (017) ----------
select t.login(:'c1');
select t.throws($$select admin_latest_members()$$, 'NOT_ADMIN', 'Liste des inscrits réservée au fondateur');
select t.login(:'admin');
select t.ok((select count(*) from jsonb_array_elements(admin_latest_members()) e where e->>'email' = 'demba.sacko20@gmail.com') = 0
            and (select count(*) from jsonb_array_elements(admin_latest_members()) e where e->>'email' = 'client3@test.fr' and e->>'kind' = 'particulier' and e->>'full_name' = 'Amina K.') = 1
            and (select count(*) from jsonb_array_elements(admin_latest_members()) e where e->>'kind' = 'commercant' and e->>'shop_name' is not null) >= 2,
            'Le fondateur voit les derniers inscrits : nom, e-mail, particulier ou commerçant');
reset role;
delete from notifications where key = 'admin_daily_signups';
select deals_daily_signups();
select t.ok(exists (select 1 from notifications where key = 'admin_daily_signups' and user_id = :'admin' and body like '%inscrits aujourd''hui%'),
            'Résumé du soir envoyé au fondateur');
set role authenticated;

-- ---------- Messagerie avec le fondateur (018) ----------
select t.login(:'c2');
select t.throws($$select support_send('   ')$$, 'MESSAGE_EMPTY', 'Message vide refusé');
select t.ok((support_send('Bonjour, la boucherie près de chez moi n''est pas encore inscrite')->>'from_admin')::boolean = false, 'Le particulier écrit au fondateur');
select t.throws($$select admin_support_threads()$$, 'NOT_ADMIN', 'Liste des conversations réservée au fondateur');
select t.throws(format($$select admin_support_reply(%L, 'x')$$, :'c1'), 'NOT_ADMIN', 'Seul le fondateur répond');
select t.login(:'c1');
select t.ok(jsonb_array_length(support_my_thread()) = 0, 'Un autre inscrit ne voit pas la conversation');
select t.ok((select count(*) from support_messages) = 0, 'Table protégée : chacun ne lit que ses messages');
select t.login(:'admin');
select t.ok(exists (select 1 from notifications where key = 'admin_new_message' and user_id = :'admin' and title like 'Message de %'), 'Le fondateur est prévenu du message');
select t.ok(support_unread() >= 1, 'Pastille : message non lu pour le fondateur');
select t.ok((select (e->>'unread')::int from jsonb_array_elements(admin_support_threads()) e where e->>'user_id' = :'c2') = 1, 'La conversation apparaît avec 1 non lu');
select t.ok(jsonb_array_length(admin_support_thread(:'c2')->'messages') = 1, 'Le fondateur ouvre la conversation');
select t.ok(support_unread() = 0, 'Le fondateur lit : plus de non lu');
select t.ok((admin_support_reply(:'c2', 'Merci, je passe la voir cette semaine')->>'from_admin')::boolean, 'Le fondateur répond');
select t.throws($$select support_send('test')$$, 'USE_ADMIN', 'Le fondateur ne s''écrit pas à lui-même');
select t.login(:'c2');
select t.ok(exists (select 1 from notifications where key = 'support_reply' and user_id = :'c2'), 'Le particulier est prévenu de la réponse');
select t.ok(support_unread() = 1, 'Pastille : réponse non lue');
select t.ok(jsonb_array_length(support_my_thread()) = 2, 'Le particulier voit les deux messages');
select t.ok(support_unread() = 0, 'Réponse lue : plus de pastille');

-- ---------- Bilan ----------
reset role;
\o
\set QUIET off
select count(*) filter (where passed) as reussis, count(*) filter (where not passed) as echecs from t.results;
select label from t.results where not passed;
do $$ begin
  if exists (select 1 from t.results where not passed) then
    raise exception 'Des tests ont échoué';
  end if;
end $$;
