-- 013 : notifications manquantes depuis le début.
--   Client     : visite terminée sans montant saisi (« avez-vous acheté ? »).
--   Commerçant : commerce suspendu, commerce remis en ligne, photo retirée, nouvelle facture.
--   Fondateur  : nouveau commerce à valider, nouveau signalement (prix, halal, achat contesté, photo…).
-- N'efface rien, relançable.

-- Le fondateur (e-mail vérifié), pour le prévenir
create or replace function public.admin_ids()
returns uuid[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(u.id), '{}'::uuid[]) from auth.users u
  where lower(u.email) = 'demba.sacko20@gmail.com' and u.email_confirmed_at is not null;
$$;

-- Textes : ceux de 011 + les nouveaux
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
    end
  end;
$$;

-- Visite terminée sans montant (le commerçant a dit « pas d'achat », ou 30 min passées) : on demande au client
create or replace function public.notify_checkin_closed()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.status = 'waiting' and new.status in ('dismissed', 'expired') then
    perform public.deals_notify(array[new.client_id], 'visit_closed',
      jsonb_build_object('shop', (select name from public.shops where id = new.shop_id)), jsonb_build_object('url', '/achats'));
  end if;
  return new;
end $$;
drop trigger if exists checkins_closed_notify on public.checkins;
create trigger checkins_closed_notify after update of status on public.checkins
  for each row execute function public.notify_checkin_closed();

-- Commerce : validé, suspendu, remis en ligne ; nouveau commerce pour le fondateur
create or replace function public.notify_shop()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is not distinct from old.status then
    return new;
  end if;
  if new.status = 'active' and old.status = 'pending' then
    perform public.deals_notify(array[new.owner_id], 'shop_validated', jsonb_build_object('shop', new.name),
                                jsonb_build_object('url', '/commercant'));
  elsif new.status = 'active' and old.status = 'suspended' then
    perform public.deals_notify(array[new.owner_id], 'shop_back', jsonb_build_object('shop', new.name),
                                jsonb_build_object('url', '/commercant'));
  elsif new.status = 'suspended' then
    perform public.deals_notify(array[new.owner_id], 'shop_suspended', jsonb_build_object('shop', new.name),
                                jsonb_build_object('url', '/commercant'));
  end if;
  return new;
end $$;

create or replace function public.notify_shop_new()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending' then
    perform public.deals_notify(public.admin_ids(), 'admin_new_shop',
      jsonb_build_object('shop', new.name, 'city', coalesce((select name from public.zones where id = new.zone_id), '?')), jsonb_build_object('url', '/admin'));
  end if;
  return new;
end $$;
drop trigger if exists shops_new_notify on public.shops;
create trigger shops_new_notify after insert on public.shops
  for each row execute function public.notify_shop_new();

-- Photo retirée par le fondateur
create or replace function public.notify_photo_removed()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.photo_path is not null and new.photo_path is null and public.is_admin() then
    perform public.deals_notify((select array[owner_id] from public.shops where id = new.shop_id), 'photo_removed',
      jsonb_build_object('product', new.name), jsonb_build_object('url', '/commercant/produits'));
  end if;
  return new;
end $$;
drop trigger if exists products_photo_notify on public.products;
create trigger products_photo_notify after update of photo_path on public.products
  for each row execute function public.notify_photo_removed();

-- Nouvelle facture (en plus de l'e-mail)
create or replace function public.notify_invoice()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.shop_id is not null then
    perform public.deals_notify((select array[owner_id] from public.shops where id = new.shop_id), 'invoice_issued',
      jsonb_build_object('number', new.number, 'amount', public.fmt_euros(new.amount_ttc_cents)),
      jsonb_build_object('url', '/commercant'));
  end if;
  return new;
end $$;
drop trigger if exists invoices_notify on public.invoices;
create trigger invoices_notify after insert on public.invoices
  for each row execute function public.notify_invoice();

-- Nouveau signalement : le fondateur est prévenu
create or replace function public.notify_report()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.deals_notify(public.admin_ids(), 'admin_new_report',
    jsonb_build_object('shop', (select name from public.shops where id = new.shop_id),
                       'kind', case new.kind when 'prix' then 'prix faux' when 'halal' then 'doute halal'
                                             when 'achat' then 'achat' when 'photo' then 'photo' else 'autre' end,
                       'body', left(new.body, 120)),
    jsonb_build_object('url', '/admin'));
  return new;
end $$;
drop trigger if exists reports_notify on public.reports;
create trigger reports_notify after insert on public.reports
  for each row execute function public.notify_report();

-- ---------- Droits ----------
revoke execute on function
  public.admin_ids(), public.notify_checkin_closed(), public.notify_shop_new(), public.notify_photo_removed(),
  public.notify_invoice(), public.notify_report()
from public, anon, authenticated;
