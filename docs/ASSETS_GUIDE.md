# أين أضع الشعارات والأيقونات والصور؟

كل شيء يُستبدل بنفس الاسم، ثم ارفع التغيير إلى GitHub.

## 1) صور الـ Mockups (الأهم)
- المجلد: `assets/mockups/`
- اسم الملف = المفتاح + `.png` (مثال: `iphone.png`, `laptop.png`, `business_card.png`).
- القائمة الكاملة (68 اسماً مع معناها بالعربية): `assets/mockups/MOCKUPS_LIST.txt`
- المقاس المقترح: **1200×1000 بكسل** (نسبة 1.2:1)، PNG أو JPG بامتداد `.png`.
- ما لم تضع الصورة يظهر مربع رمادي مكتوب عليه اسم الملف المطلوب — فتعرف أين تضعها.
- لمعرفة الناقص: `dart run tools/check_mockups.dart`

## 2) الشعارات
المجلد: `assets/logos/`

| الملف | الاستعمال |
|---|---|
| `mak_icon.png` | شعار التطبيق + أيقونة التطبيق (مربع **1024×1024**، خلفية غير شفافة) |
| `mak_design.png` | شعار MAK DESIGN |
| `mak_webs.png` | شعار MAK WEBS |
| `mak_writers.png` | شعار MAK WRITINGS |

الموجود الآن **صور مؤقتة** (M.A.K بلون الهوية) — استبدلها بملفاتك بنفس الأسماء.

## 3) أيقونات التطبيق (أندرويد / ويندوز / ويب)
تُولَّد **تلقائياً** من `assets/logos/mak_icon.png` أثناء البناء على GitHub (`flutter_launcher_icons`).
لا تحتاج أن تفعل شيئاً سوى استبدال ذلك الملف.

## 4) أيقونة الويب (favicon و PWA)
- `web/favicon.png` (64×64)
- `web/icons/Icon-192.png` و `Icon-512.png` و `Icon-maskable-192.png` و `Icon-maskable-512.png`
(تُستبدل تلقائياً أيضاً عند البناء من `mak_icon.png`، وهي هنا احتياط.)

## 5) أيقونة مثبّت ويندوز (اختياري)
في `installer/mak_booking.iss` أزل `;` من سطر `SetupIconFile` وضع ملف `.ico`.

## 6) الخدمات غير المسعّرة
`assets/data/extra_services.json` (الويب والكتابة) و `assets/data/catalog.json` (التصميم):
- `"tier": null` = السعر معطّل (تسعير يدوي).
- لتفعيل سعر ضع إحدى القيم: `small` (150) · `medium` (350) · `large` (700) · `premium` (950).
- الأسعار نفسها تُعدَّل من لوحة المدير ← الإعدادات ← الأسعار.
