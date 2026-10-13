begin;
-- SOUKI DEALS : mise a jour 010 (IBAN des commercants). N'efface rien, relancable.
-- =====================================================================
-- SOUKI DEALS — 010 : IBAN du commerçant (pour lui rembourser les offres de bienvenue)
-- Table à part, lisible seulement par le commerçant et le fondateur.
-- L'IBAN est vérifié (clé de contrôle) et sa date de changement est gardée :
-- le fondateur est alerté si l'IBAN vient de changer avant un virement.
-- Ce fichier est relançable : il sert aussi de mise à jour (rien n'est effacé).
-- =====================================================================

create table if not exists public.shop_bank (
  shop_id     uuid primary key references public.shops(id) on delete cascade,
  holder      text not null check (char_length(holder) between 2 and 70),
  iban        text not null check (iban ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$'),
  bic         text check (bic is null or bic ~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$'),
  updated_at  timestamptz not null default now()
);
alter table public.shop_bank enable row level security;
drop policy if exists shop_bank_select on public.shop_bank;
create policy shop_bank_select on public.shop_bank for select to authenticated
  using (shop_id = public.my_shop_id() or public.is_admin());
grant select on public.shop_bank to authenticated;

-- Clé de contrôle de l'IBAN (norme ISO 13616, modulo 97)
create or replace function public.iban_valid(p_iban text)
returns boolean language plpgsql immutable as $$
declare
  s text;
  digits text := '';
  ch text;
  r int := 0;
  i int;
  v_len int;
begin
  s := upper(regexp_replace(coalesce(p_iban, ''), '\s', '', 'g'));
  if s !~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$' then
    return false;
  end if;
  -- Longueurs connues des pays proches (les autres pays : longueur libre)
  v_len := case left(s, 2) when 'FR' then 27 when 'BE' then 16 when 'DE' then 22 when 'ES' then 24
                           when 'IT' then 27 when 'NL' then 18 when 'LU' then 20 when 'CH' then 21
                           when 'MC' then 27 when 'GB' then 22 when 'PT' then 25 else null end;
  if v_len is not null and length(s) <> v_len then
    return false;
  end if;
  s := substr(s, 5) || left(s, 4);
  for i in 1..length(s) loop
    ch := substr(s, i, 1);
    if ch ~ '[A-Z]' then
      digits := digits || (ascii(ch) - 55)::text;
    else
      digits := digits || ch;
    end if;
  end loop;
  for i in 1..length(digits) loop
    r := (r * 10 + substr(digits, i, 1)::int) % 97;
  end loop;
  return r = 1;
end $$;

create or replace function public.merchant_save_bank(p_holder text, p_iban text, p_bic text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_shop uuid := public.my_shop_id();
  v_iban text := upper(regexp_replace(coalesce(p_iban, ''), '\s', '', 'g'));
  v_bic text := nullif(upper(regexp_replace(coalesce(p_bic, ''), '\s', '', 'g')), '');
begin
  perform public.require_login();
  if v_shop is null then
    perform public.souki_error('Aucun commerce.', 'NO_SHOP');
  end if;
  if char_length(btrim(coalesce(p_holder, ''))) not between 2 and 70 then
    perform public.souki_error('Indiquez le titulaire du compte.', 'BAD_BANK');
  end if;
  if not public.iban_valid(v_iban) then
    perform public.souki_error('IBAN invalide : vérifiez-le sur votre RIB.', 'BAD_IBAN');
  end if;
  if v_bic is not null and v_bic !~ '^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$' then
    perform public.souki_error('BIC invalide (8 ou 11 caractères).', 'BAD_BANK');
  end if;
  insert into public.shop_bank (shop_id, holder, iban, bic, updated_at)
  values (v_shop, btrim(p_holder), v_iban, v_bic, now())
  on conflict (shop_id) do update set holder = excluded.holder, iban = excluded.iban, bic = excluded.bic,
    updated_at = case when public.shop_bank.iban is distinct from excluded.iban then now() else public.shop_bank.updated_at end;
end $$;

revoke execute on function public.iban_valid(text), public.merchant_save_bank(text, text, text) from public, anon, authenticated;
grant execute on function public.merchant_save_bank(text, text, text) to authenticated;

commit;
