-- 015 : offre de bienvenue (10 €) limitée aux 1000 premiers clients. Relançable.
alter table public.settings alter column welcome_slots set default 1000;
update public.settings set welcome_slots = 1000 where id = 1;
