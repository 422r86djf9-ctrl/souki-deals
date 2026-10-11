-- =====================================================================
-- SOUKI DEALS — 004 : données de départ
-- Réglages validés le 11 octobre 2026 : remise client 5 % minimum,
-- commission 5 % du montant payé, 3 mois offerts aux 150 premiers commerces.
-- Lancement en Île-de-France (8 départements, ouverts).
-- =====================================================================

insert into public.settings (id) values (1);

insert into public.zones (country, currency, name, name_en, name_ar, open, sort) values
  ('FR', 'EUR', 'Paris (75)',             'Paris (75)',             'باريس (75)', true, 1),
  ('FR', 'EUR', 'Seine-Saint-Denis (93)', 'Seine-Saint-Denis (93)', 'سين سان دوني (93)', true, 2),
  ('FR', 'EUR', 'Val-de-Marne (94)',      'Val-de-Marne (94)',      'فال دو مارن (94)', true, 3),
  ('FR', 'EUR', 'Hauts-de-Seine (92)',    'Hauts-de-Seine (92)',    'أو دو سين (92)', true, 4),
  ('FR', 'EUR', 'Val-d''Oise (95)',       'Val-d''Oise (95)',       'فال دواز (95)', true, 5),
  ('FR', 'EUR', 'Essonne (91)',           'Essonne (91)',           'إيسون (91)', true, 6),
  ('FR', 'EUR', 'Yvelines (78)',          'Yvelines (78)',          'إيفلين (78)', true, 7),
  ('FR', 'EUR', 'Seine-et-Marne (77)',    'Seine-et-Marne (77)',    'سين إي مارن (77)', true, 8);
