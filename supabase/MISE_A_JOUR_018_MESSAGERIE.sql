begin;
-- SOUKI DEALS : mise a jour 018 (messagerie avec le fondateur). Relancable.
-- 018 : messagerie directe entre chaque inscrit (particulier ou commerçant) et le fondateur. Relançable.

create table if not exists public.support_messages (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  from_admin boolean not null default false,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists support_messages_user_idx on public.support_messages (user_id, created_at desc);
alter table public.support_messages enable row level security;
revoke all on public.support_messages from anon, authenticated;
drop policy if exists support_messages_read on public.support_messages;
create policy support_messages_read on public.support_messages for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
grant select on public.support_messages to authenticated;

create or replace function public.deals_text(p_key text, p_lang text)
returns text[] language sql immutable as $$
  select case p_lang
    when 'en' then case p_key
      when 'client_present' then array['Customer in your shop', '{name} scanned your QR code. Enter the amount paid.']
      when 'purchase_to_confirm' then array['Confirm your purchase', 'Did you pay {amount} at {shop}?']
      when 'purchase_disputed' then array['Purchase disputed', 'A customer disputes a purchase of {amount}. Souki Deals will look into it.']
      when 'flash_nearby' then array['Flash offer near you', '{shop}: {title} -{pct}% until tonight']
      when 'shop_validated' then array['Your shop is live', '{shop} is now visible to Souki Deals customers.']
      when 'charge_failed' then array['Payment declined', 'The {amount} commission could not be charged. Your shop is hidden until it is paid.']
      when 'refund_sent' then array['Refund sent', 'Souki Deals has transferred {amount} to your account (welcome offers).']
      when 'visit_closed' then array['Did you buy something?', 'Your visit to {shop} ended without an amount. Tell us in "My vouchers and purchases".']
      when 'shop_suspended' then array['Shop suspended', '{shop} is no longer visible to customers. Contact Souki Deals.']
      when 'shop_back' then array['Your shop is back online', '{shop} is visible to customers again.']
      when 'photo_removed' then array['Photo removed', 'The photo of "{product}" was removed after a report. You can add another one.']
      when 'invoice_issued' then array['New invoice', 'Invoice {number} of {amount} is available. It has also been emailed to you.']
      when 'admin_new_shop' then array['New shop to validate', '{shop} ({city}) is waiting for your validation.']
      when 'admin_new_report' then array['New report', '{shop}: {kind}. {body}']
      when 'admin_daily_signups' then array['Today''s sign-ups', '{clients} customers and {shops} shops signed up today. Total: {total} customers.']
      when 'admin_new_message' then array['Message from {name}', '{preview}']
      when 'support_reply' then array['Reply from Souki Deals', '{preview}']
    end
    when 'ar' then case p_key
      when 'client_present' then array['زبون في متجرك', 'مسح {name} رمزك. أدخل المبلغ المدفوع.']
      when 'purchase_to_confirm' then array['أكّد مشترياتك', 'هل دفعت {amount} في {shop}؟']
      when 'purchase_disputed' then array['شراء مُعترض عليه', 'زبون يعترض على شراء بقيمة {amount}. سيتابع Souki Deals الأمر.']
      when 'flash_nearby' then array['عرض خاطف قربك', '{shop}: {title} -{pct} % حتى هذا المساء']
      when 'shop_validated' then array['متجرك مفعّل', 'أصبح {shop} ظاهرًا لزبائن Souki Deals.']
      when 'charge_failed' then array['تعذّر الاقتطاع', 'لم تُقتطع العمولة {amount}. متجرك مخفي حتى الدفع.']
      when 'refund_sent' then array['تم إرسال التعويض', 'حوّل Souki Deals مبلغ {amount} إلى حسابك (عروض الترحيب).']
      when 'visit_closed' then array['هل اشتريت شيئًا؟', 'انتهت زيارتك إلى {shop} دون إدخال مبلغ. أخبرنا في «قسائمي ومشترياتي».']
      when 'shop_suspended' then array['تم تعليق المتجر', 'لم يعد {shop} ظاهرًا للزبائن. تواصل مع Souki Deals.']
      when 'shop_back' then array['عاد متجرك إلى الظهور', 'أصبح {shop} ظاهرًا للزبائن من جديد.']
      when 'photo_removed' then array['تم حذف صورة', 'حُذفت صورة «{product}» بعد بلاغ. يمكنك إضافة صورة أخرى.']
      when 'invoice_issued' then array['فاتورة جديدة', 'الفاتورة {number} بقيمة {amount} متاحة. أُرسلت إليك أيضًا بالبريد.']
      when 'admin_new_shop' then array['متجر جديد للتحقق', '{shop} ({city}) في انتظار موافقتك.']
      when 'admin_new_report' then array['بلاغ جديد', '{shop}: {kind}. {body}']
      when 'admin_daily_signups' then array['تسجيلات اليوم', 'سجّل اليوم {clients} زبونًا و{shops} متجرًا. المجموع: {total} زبونًا.']
      when 'admin_new_message' then array['رسالة من {name}', '{preview}']
      when 'support_reply' then array['ردّ من Souki Deals', '{preview}']
    end
    else case p_key
      when 'client_present' then array['Client dans votre magasin', '{name} a scanné votre QR code. Saisissez le montant payé.']
      when 'purchase_to_confirm' then array['Confirmez votre achat', 'Vous avez payé {amount} chez {shop} ?']
      when 'purchase_disputed' then array['Achat contesté', 'Un client conteste un achat de {amount}. Souki Deals va regarder.']
      when 'flash_nearby' then array['Offre flash près de chez vous', '{shop} : {title} à -{pct} % jusqu''à ce soir']
      when 'shop_validated' then array['Votre commerce est en ligne', '{shop} est maintenant visible des clients Souki Deals.']
      when 'charge_failed' then array['Prélèvement refusé', 'La commission de {amount} n''a pas pu être prélevée. Votre commerce est masqué jusqu''au paiement.']
      when 'refund_sent' then array['Remboursement envoyé', 'Souki Deals vous a viré {amount} (offres de bienvenue).']
      when 'visit_closed' then array['Vous avez acheté ?', 'Votre visite chez {shop} s''est terminée sans montant. Dites-le-nous dans « Mes bons et achats ».']
      when 'shop_suspended' then array['Commerce suspendu', '{shop} n''est plus visible des clients. Contactez Souki Deals.']
      when 'shop_back' then array['Votre commerce est de retour', '{shop} est de nouveau visible des clients.']
      when 'photo_removed' then array['Photo retirée', 'La photo de « {product} » a été retirée après un signalement. Vous pouvez en mettre une autre.']
      when 'invoice_issued' then array['Nouvelle facture', 'La facture {number} de {amount} est disponible. Elle vous a aussi été envoyée par e-mail.']
      when 'admin_new_shop' then array['Nouveau commerce à valider', '{shop} ({city}) attend votre validation.']
      when 'admin_new_report' then array['Nouveau signalement', '{shop} : {kind}. {body}']
      when 'admin_daily_signups' then array['Inscriptions du jour', '{clients} particuliers et {shops} commerçants se sont inscrits aujourd''hui. Total : {total} particuliers.']
      when 'admin_new_message' then array['Message de {name}', '{preview}']
      when 'support_reply' then array['Réponse de Souki Deals', '{preview}']
    end
  end;
$$;

-- Aperçu court pour la notification
create or replace function public.support_preview(p_body text)
returns text language sql immutable as $$
  select case when char_length(btrim(p_body)) > 120 then left(btrim(p_body), 117) || '…' else btrim(p_body) end
$$;

-- L'inscrit écrit au fondateur
create or replace function public.support_send(p_body text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_body text := btrim(coalesce(p_body, ''));
  v_name text;
  v_row public.support_messages;
begin
  if v_uid is null then
    perform public.souki_error('Connectez-vous pour écrire.', 'NOT_AUTHENTICATED');
  end if;
  if public.is_admin() then
    perform public.souki_error('Répondez depuis l’administration.', 'USE_ADMIN');
  end if;
  if char_length(v_body) = 0 then
    perform public.souki_error('Écrivez votre message.', 'MESSAGE_EMPTY');
  end if;
  if char_length(v_body) > 2000 then
    perform public.souki_error('Message trop long (2000 caractères au plus).', 'MESSAGE_TOO_LONG');
  end if;
  if (select count(*) from public.support_messages
      where user_id = v_uid and not from_admin and created_at > now() - interval '1 hour') >= 20 then
    perform public.souki_error('Beaucoup de messages envoyés : réessayez dans un moment.', 'MESSAGE_RATE');
  end if;
  insert into public.support_messages (user_id, from_admin, body) values (v_uid, false, v_body) returning * into v_row;
  select coalesce(nullif(btrim(s.name), ''), nullif(btrim(p.full_name), ''), au.email) into v_name
  from auth.users au
  left join public.profiles p on p.id = au.id
  left join public.shops s on s.owner_id = au.id
  where au.id = v_uid
  limit 1;
  perform public.deals_notify(public.admin_ids(), 'admin_new_message',
    jsonb_build_object('name', coalesce(v_name, '?'), 'preview', public.support_preview(v_body)),
    jsonb_build_object('url', '/messages?user=' || v_uid::text));
  return to_jsonb(v_row);
end $$;

-- L'inscrit lit sa conversation (les réponses du fondateur passent en « lues »)
create or replace function public.support_my_thread()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then
    perform public.souki_error('Connectez-vous pour écrire.', 'NOT_AUTHENTICATED');
  end if;
  update public.support_messages set read_at = now() where user_id = v_uid and from_admin and read_at is null;
  return coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at, m.id)
                   from (select * from public.support_messages where user_id = v_uid order by created_at desc, id desc limit 300) m), '[]'::jsonb);
end $$;

-- Nombre de réponses du fondateur pas encore lues (pastille sur l'accueil)
create or replace function public.support_unread()
returns int language sql stable security definer set search_path = public as $$
  select case when public.is_admin()
    then (select count(*)::int from public.support_messages where not from_admin and read_at is null)
    else (select count(*)::int from public.support_messages where user_id = auth.uid() and from_admin and read_at is null) end
$$;

-- Le fondateur : liste des conversations
create or replace function public.admin_support_threads()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_admin();
  return coalesce((
    select jsonb_agg(x order by x.last_at desc) from (
      select m.user_id, au.email,
             nullif(btrim(p.full_name), '') as full_name,
             s.name as shop_name,
             case when s.id is not null then 'commercant' else 'particulier' end as kind,
             max(m.created_at) as last_at,
             (array_agg(m.body order by m.created_at desc, m.id desc))[1] as last_body,
             (array_agg(m.from_admin order by m.created_at desc, m.id desc))[1] as last_from_admin,
             count(*) filter (where not m.from_admin and m.read_at is null)::int as unread
      from public.support_messages m
      join auth.users au on au.id = m.user_id
      left join public.profiles p on p.id = m.user_id
      left join public.shops s on s.owner_id = m.user_id
      group by m.user_id, au.email, p.full_name, s.id, s.name
    ) x), '[]'::jsonb);
end $$;

-- Le fondateur : une conversation (les messages de l'inscrit passent en « lus »)
create or replace function public.admin_support_thread(p_user uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.require_admin();
  update public.support_messages set read_at = now() where user_id = p_user and not from_admin and read_at is null;
  return jsonb_build_object(
    'user', (select jsonb_build_object('id', au.id, 'email', au.email, 'full_name', nullif(btrim(p.full_name), ''),
                                       'phone', p.phone, 'shop_name', s.name,
                                       'kind', case when s.id is not null then 'commercant' else 'particulier' end)
             from auth.users au left join public.profiles p on p.id = au.id left join public.shops s on s.owner_id = au.id
             where au.id = p_user limit 1),
    'messages', coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at, m.id)
                          from (select * from public.support_messages where user_id = p_user order by created_at desc, id desc limit 300) m), '[]'::jsonb));
end $$;

-- Le fondateur répond
create or replace function public.admin_support_reply(p_user uuid, p_body text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_body text := btrim(coalesce(p_body, ''));
  v_row public.support_messages;
begin
  perform public.require_admin();
  if char_length(v_body) = 0 then
    perform public.souki_error('Écrivez votre message.', 'MESSAGE_EMPTY');
  end if;
  if char_length(v_body) > 2000 then
    perform public.souki_error('Message trop long (2000 caractères au plus).', 'MESSAGE_TOO_LONG');
  end if;
  if not exists (select 1 from auth.users where id = p_user) then
    perform public.souki_error('Compte introuvable.', 'USER_NOT_FOUND');
  end if;
  insert into public.support_messages (user_id, from_admin, body) values (p_user, true, v_body) returning * into v_row;
  perform public.deals_notify(array[p_user], 'support_reply', jsonb_build_object('preview', public.support_preview(v_body)),
                              jsonb_build_object('url', '/messages'));
  return to_jsonb(v_row);
end $$;

revoke execute on function public.support_send(text), public.support_my_thread(), public.support_unread(),
  public.admin_support_threads(), public.admin_support_thread(uuid), public.admin_support_reply(uuid, text) from public, anon;
grant execute on function public.support_send(text), public.support_my_thread(), public.support_unread(),
  public.admin_support_threads(), public.admin_support_thread(uuid), public.admin_support_reply(uuid, text) to authenticated;

commit;
