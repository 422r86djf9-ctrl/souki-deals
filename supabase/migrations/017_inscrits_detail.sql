-- 017 : liste des derniers inscrits pour le fondateur, et résumé quotidien des inscriptions
-- (une notification chaque soir vers 20 h, seulement s'il y a eu des inscriptions). Relançable.

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
    end
  end;
$$;

-- Derniers inscrits (comptes confirmés ou non), le fondateur exclu
create or replace function public.admin_latest_members(p_limit int default 100)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.require_admin();
  return coalesce((
    select jsonb_agg(x order by x.created_at desc) from (
      select au.id, au.email, au.created_at, au.email_confirmed_at is not null as confirmed,
             nullif(btrim(p.full_name), '') as full_name,
             case when s.id is not null then 'commercant' else 'particulier' end as kind,
             s.name as shop_name, s.status as shop_status,
             (exists (select 1 from public.vouchers v where v.client_id = au.id)
              or exists (select 1 from public.checkins c where c.client_id = au.id)) as used
      from auth.users au
      left join public.profiles p on p.id = au.id
      left join public.shops s on s.owner_id = au.id
      where lower(coalesce(au.email, '')) <> 'demba.sacko20@gmail.com'
      order by au.created_at desc
      limit least(greatest(coalesce(p_limit, 100), 1), 500)
    ) x), '[]'::jsonb);
end $$;

-- Résumé du jour, envoyé au fondateur par la tâche du soir
create or replace function public.deals_daily_signups()
returns void language plpgsql security definer set search_path = public as $$
declare
  v_today timestamptz := (public.paris_today()::timestamp) at time zone 'Europe/Paris';
  v_clients int;
  v_shops int;
  v_total int;
begin
  select count(*) into v_shops from public.shops where created_at >= v_today;
  select count(*) into v_clients from auth.users au
  where au.created_at >= v_today and lower(coalesce(au.email, '')) <> 'demba.sacko20@gmail.com'
    and not exists (select 1 from public.shops s where s.owner_id = au.id);
  if v_clients + v_shops = 0 then
    return;
  end if;
  select count(*) into v_total from auth.users au
  where au.email_confirmed_at is not null and lower(coalesce(au.email, '')) <> 'demba.sacko20@gmail.com'
    and not exists (select 1 from public.shops s where s.owner_id = au.id);
  perform public.deals_notify(public.admin_ids(), 'admin_daily_signups',
    jsonb_build_object('clients', v_clients, 'shops', v_shops, 'total', v_total), jsonb_build_object('url', '/admin'));
end $$;

revoke execute on function public.admin_latest_members(int), public.deals_daily_signups() from public, anon, authenticated;
grant execute on function public.admin_latest_members(int) to authenticated;

-- Chaque soir à 19 h UTC (20 h l'hiver, 21 h l'été à Paris)
do $do$
begin
  perform cron.unschedule('souki-deals-inscrits') where exists (select 1 from cron.job where jobname = 'souki-deals-inscrits');
  perform cron.schedule('souki-deals-inscrits', '0 19 * * *', 'select public.deals_daily_signups()');
exception when others then
  raise warning 'SOUKI DEALS : résumé quotidien des inscriptions non planifié (%).', sqlerrm;
end $do$;
