# Génère les e-mails d'authentification de Souki Deals :
#   - modèles Supabase (*.html, syntaxe Go) pour Authentication > Email Templates
#   - migrations/014_emails.sql : envoi direct par Resend (hook « Send Email »), sans passer par l'éditeur
import os
G = '#0E7A35'; O = '#FF7A1A'
HERE = os.path.dirname(os.path.abspath(__file__))

TXT = {
 'signup_client': {
  'fr': (['<b>Bienvenue sur Souki Deals !</b>', "Confirmez votre adresse pour profiter des remises dans les commerces halal près de chez vous, et de <b>10 € offerts</b> sur votre premier achat dès 30 €."], 'Confirmer mon adresse', 'Confirmez votre adresse Souki Deals'),
  'en': (['<b>Welcome to Souki Deals!</b>', 'Confirm your email to enjoy discounts in halal shops near you, plus <b>€10 off</b> your first purchase of €30 or more.'], 'Confirm my email', 'Confirm your Souki Deals email'),
  'ar': (['<b>مرحبًا بك في Souki Deals!</b>', 'أكّد بريدك الإلكتروني للاستفادة من التخفيضات في المتاجر الحلال قربك، و<b>10 € هدية</b> على أول شراء من 30 €.'], 'تأكيد بريدي', 'أكّد بريدك في Souki Deals')},
 'signup_pro': {
  'fr': (['<b>Bienvenue sur Souki Deals !</b>', "Confirmez votre adresse pour finir l'inscription de votre commerce. Dès sa validation, vos clients vous trouveront dans l'appli avec votre remise."], 'Confirmer mon adresse', 'Confirmez votre adresse Souki Deals'),
  'en': (['<b>Welcome to Souki Deals!</b>', 'Confirm your email to finish registering your shop. Once approved, customers will find you in the app with your discount.'], 'Confirm my email', 'Confirm your Souki Deals email'),
  'ar': (['<b>مرحبًا بك في Souki Deals!</b>', 'أكّد بريدك الإلكتروني لإكمال تسجيل متجرك. بعد الموافقة سيجدك الزبائن في التطبيق مع تخفيضك.'], 'تأكيد بريدي', 'أكّد بريدك في Souki Deals')},
 'recovery': {
  'fr': (['<b>Mot de passe oublié ?</b>', 'Touchez le bouton pour choisir un nouveau mot de passe. Ce lien est valable 1 heure.'], 'Choisir un nouveau mot de passe', 'Nouveau mot de passe Souki Deals'),
  'en': (['<b>Forgot your password?</b>', 'Tap the button to choose a new password. This link is valid for 1 hour.'], 'Choose a new password', 'Your new Souki Deals password'),
  'ar': (['<b>نسيت كلمة المرور؟</b>', 'اضغط على الزر لاختيار كلمة مرور جديدة. الرابط صالح لمدة ساعة.'], 'اختيار كلمة مرور جديدة', 'كلمة مرور جديدة في Souki Deals')},
 'magiclink': {
  'fr': (['<b>Votre lien de connexion</b>', 'Touchez le bouton pour vous connecter à Souki Deals.'], 'Me connecter', 'Votre lien de connexion Souki Deals'),
  'en': (['<b>Your sign-in link</b>', 'Tap the button to sign in to Souki Deals.'], 'Sign in', 'Your Souki Deals sign-in link'),
  'ar': (['<b>رابط الدخول</b>', 'اضغط على الزر للدخول إلى Souki Deals.'], 'الدخول', 'رابط الدخول إلى Souki Deals')},
 'email_change': {
  'fr': (['<b>Nouvelle adresse e-mail</b>', 'Confirmez que <b>{NEW}</b> devient votre adresse Souki Deals.'], 'Confirmer', 'Confirmez votre nouvelle adresse'),
  'en': (['<b>New email address</b>', 'Confirm that <b>{NEW}</b> becomes your Souki Deals email.'], 'Confirm', 'Confirm your new email'),
  'ar': (['<b>بريد إلكتروني جديد</b>', 'أكّد أن <b>{NEW}</b> سيصبح بريدك في Souki Deals.'], 'تأكيد', 'أكّد بريدك الجديد')},
}

def inner(blocks, btn, rtl, url):
    d = ' dir="rtl"' if rtl else ''
    al = 'right' if rtl else 'left'
    paras = ''.join(f'<p style="margin:0 0 14px;font-size:16px;line-height:1.5;color:#1C2A21;text-align:{al}">{b}</p>' for b in blocks)
    return (f'<div{d}>{paras}<p style="margin:22px 0;text-align:center"><a href="{url}" style="background:{G};color:#ffffff;'
            f'text-decoration:none;font-weight:bold;font-size:17px;padding:14px 28px;border-radius:12px;display:inline-block">{btn}</a></p></div>')

def frame(content, url):
    return (f'<!doctype html><html><body style="margin:0;background:#F7FAF6;font-family:Helvetica,Arial,sans-serif">'
            f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F7FAF6;padding:24px 12px"><tr><td align="center">'
            f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:16px;overflow:hidden">'
            f'<tr><td style="padding:22px 24px 10px;text-align:center"><img src="https://soukideals.com/logo.png" alt="Souki Deals" width="200" style="width:200px;max-width:70%;height:auto"></td></tr>'
            f'<tr><td style="height:4px;background:{O}"></td></tr><tr><td style="padding:24px">{content}'
            f'<p style="margin:18px 0 0;font-size:13px;line-height:1.5;color:#5B6A60">Si le bouton ne marche pas, copiez ce lien dans votre navigateur :<br>'
            f'<a href="{url}" style="color:{G};word-break:break-all">{url}</a></p></td></tr>'
            f'<tr><td style="padding:16px 24px;background:#E5F4EA;font-size:12px;color:#5B6A60;text-align:center">Souki Deals · Le halal au meilleur prix, près de chez vous · '
            f'<a href="https://soukideals.com" style="color:{G}">soukideals.com</a><br>Vous n\'avez rien demandé ? Ignorez simplement cet e-mail.</td></tr>'
            f'</table></td></tr></table></body></html>')

def variant(key, lang, url, new='{NEW}'):
    blocks, btn, subj = TXT[key][lang]
    blocks = [b.replace('{NEW}', new) for b in blocks]
    return subj, frame(inner(blocks, btn, lang == 'ar', url), url)

# 1) Modèles Go pour l'éditeur Supabase
def go(key_client, key_pro=None):
    U = '{{ .ConfirmationURL }}'
    def by_lang(lang):
        if key_pro:
            a = inner(*TXT[key_pro][lang][:2], lang == 'ar', U)
            b = inner(*TXT[key_client][lang][:2], lang == 'ar', U)
            return '{{ if eq .Data.espace "commercant" }}' + a + '{{ else }}' + b + '{{ end }}'
        blocks, btn, _ = TXT[key_client][lang]
        return inner([x.replace('{NEW}', '{{ .NewEmail }}') for x in blocks], btn, lang == 'ar', U)
    content = ('{{ if eq .Data.lang "en" }}' + by_lang('en') + '{{ else if eq .Data.lang "ar" }}' + by_lang('ar') +
               '{{ else }}' + by_lang('fr') + '{{ end }}')
    return frame(content, U) + '\n'
for name, args in [('1_confirmation_inscription', ('signup_client', 'signup_pro')), ('2_mot_de_passe_oublie', ('recovery',)),
                   ('3_lien_de_connexion', ('magiclink',)), ('4_changement_email', ('email_change',))]:
    open(os.path.join(HERE, name + '.html'), 'w').write(go(*args))

# 2) SQL : textes prêts à l'emploi, l'adresse est remplacée au moment de l'envoi
rows = []
for key in TXT:
    for lang in ('fr', 'en', 'ar'):
        subj, html = variant(key, lang, '%%URL%%', '%%NEW%%')
        rows.append(f"  when '{key}:{lang}' then array[$s${subj}$s$, $h${html}$h$]")
sql = open(os.path.join(HERE, '014_modele.sql')).read().replace('--@TEXTES@', '\n'.join(rows))
open(os.path.join(HERE, '..', 'migrations', '014_emails.sql'), 'w').write(sql)
print('ok')
