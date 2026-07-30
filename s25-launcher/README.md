# تطبيق S25 Desktop — مُشغّل النظام من الشاشة الرئيسية

تطبيق أندرويد صغير (~35 كيلوبايت، بدون أي مكتبات خارجية) يضع أيقونة على الشاشة
الرئيسية: تضغطها → يشغّل النظام داخل Termux → ينقلك تلقائياً إلى شاشة العرض.
لا حاجة لكتابة أي أمر بعد التثبيت الأول.

<p align="center">
  <code>[ ✦ Claude Desktop (ويندوز .exe) ]  [ ◉ Chrome (ويندوز .exe) ]  [ ▶ سطح المكتب ]</code>
</p>

## الزر الأول: تثبيت النظام

زر **«① تثبيت النظام (مرة واحدة)»** يشغّل التثبيت الكامل داخل جلسة Termux مرئية:

```bash
pkg install -y git && git clone https://github.com/basio96547/turnip-a830-s25ultra
bash turnip-a830-s25ultra/s25-desktop/install.sh
```

قبل انتهائه لا تعمل أزرار التشغيل — والتطبيق يمنعك من الدخول إلى شاشة عرض فارغة
ويعرض تنبيهاً بدلاً من ذلك.

## ما يفعله بالضبط

1. يرسل الأمر `s25-desktop <mode>` إلى Termux عبر خدمة `com.termux.RUN_COMMAND`
2. ينتظر ~3.5 ثانية حتى يبدأ خادم X وجلسة الحاوية
3. يفتح تطبيق **Termux:X11** — فتظهر لك الواجهة مباشرة

أزرار إضافية: فتح شاشة العرض، تشخيص النظام (`s25-doctor` في جلسة مرئية)، فتح
Termux، وإيقاف الكل (`s25-stop`).

**اختصارات سريعة:** اضغط ضغطة طويلة على أيقونة التطبيق → تظهر ثلاثة اختصارات
(Claude ويندوز / Chrome ويندوز / سطح المكتب) يمكن سحب أي منها ليصبح أيقونة
مستقلة على الشاشة الرئيسية.

طبقة ويندوز تُثبَّت افتراضياً مع `bash s25-desktop/install.sh` — التفاصيل في
[docs/WINDOWS.md](../s25-desktop/docs/WINDOWS.md).

## التثبيت

### 1. التطبيق

- **جاهز:** [`prebuilt/S25-Desktop-launcher.apk`](prebuilt/S25-Desktop-launcher.apk)
  — نزّله على الجوال وثبّته (اسمح بالتثبيت من مصادر غير معروفة).
- **أو** من صفحة Releases (سير عمل `Build S25 Desktop launcher APK` بتشغيل يدوي).
- **أو** ابنه بنفسك:
  ```bash
  cd s25-launcher
  gradle assembleDebug        # أو افتح المجلد في Android Studio
  # الناتج: app/build/outputs/apk/debug/app-debug.apk
  ```

الحزمة موقّعة بمفتاح **debug** بمخططَي التوقيع v2 و v3 (وهما ما يتحقق منه
أندرويد الحديث) — كافٍ تماماً للتثبيت اليدوي، وغير مناسب للنشر في متجر Play.
للتحقق من الحزمة الجاهزة:

```bash
sha256sum prebuilt/S25-Desktop-launcher.apk
# f056b4c158a36fcede29e7a79a786c33394e36f888858f6c20f2a1f3e745fb3d
```

### إن رفض الجهاز التثبيت (سامسونج تحديداً)

هذه أشهر الأسباب على S25 Ultra بالترتيب:

1. **Auto Blocker (حاجب تلقائي)** — مفعّل افتراضياً في One UI ويمنع تثبيت أي
   تطبيق من خارج المتاجر تماماً، وغالباً هو السبب:
   `الإعدادات ▸ الأمان والخصوصية ▸ Auto Blocker / الحاجب التلقائي ▸ إيقاف`
   (يمكن إعادة تفعيله بعد التثبيت).
2. **صلاحية «تثبيت تطبيقات غير معروفة»** — يجب منحها *للتطبيق الذي يفتح الملف*
   (مدير الملفات أو المتصفح، لا لهذا التطبيق):
   `الإعدادات ▸ التطبيقات ▸ [مدير الملفات] ▸ تثبيت تطبيقات غير معروفة ▸ سماح`
3. **الملف تالف أو غيّر امتداده** أثناء النقل عبر تطبيق محادثة — نزّله من رابط
   GitHub المباشر بدلاً من ذلك، وتحقق من بصمة sha256 أعلاه.
4. **Play Protect** يعطي تحذيراً — اختر «تثبيت على أي حال» (Install anyway).
5. لا يزال يرفض؟ التطبيق ليس شرطاً — كل شيء يعمل من Termux مباشرة:
   `s25-desktop win-claude` أو `s25-desktop win-chrome`.

### 2. التطبيقات المرافقة

| التطبيق | من أين | لماذا |
|---------|--------|-------|
| Termux | [F-Droid](https://f-droid.org/packages/com.termux/) | يشغّل الحاوية (نسخة Play Store قديمة ولا تعمل) |
| Termux:X11 | [GitHub Releases](https://github.com/termux/termux-x11/releases) | شاشة العرض (`app-arm64-v8a-debug.apk`) |

### 3. تثبيت النظام (مرة واحدة)

```bash
git clone https://github.com/basio96547/turnip-a830-s25ultra
bash turnip-a830-s25ultra/s25-desktop/install.sh
```

سكربت التثبيت يفعّل تلقائياً `allow-external-apps=true` في
`~/.termux/termux.properties` — وهي الصلاحية التي يحتاجها التطبيق لتشغيل الأوامر
داخل Termux. إن ظهرت رسالة «صلاحية مطلوبة» في التطبيق، اضغط «نسخ الأمر» ونفّذه
في Termux:

```bash
echo 'allow-external-apps=true' >> ~/.termux/termux.properties && termux-reload-settings
```

## الأذونات

إذن واحد فقط: `com.termux.permission.RUN_COMMAND` — تشغيل أمر داخل Termux.
لا إنترنت، لا تخزين، لا موقع، ولا أي اعتمادية خارجية في الحزمة.

## البنية

```
s25-launcher/
├── settings.gradle · build.gradle · gradle.properties
├── app/
│   ├── build.gradle                     # AGP 8.5.2 · minSdk 26 · targetSdk 34
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/s25/desktop/launcher/MainActivity.java
│       └── res/                          # واجهة عربية/إنجليزية + أيقونة تكيّفية
└── prebuilt/S25-Desktop-launcher.apk     # حزمة جاهزة للتثبيت
```

## المشاكل الشائعة

| ما تراه | الحل |
|---------|------|
| «صلاحية مطلوبة في Termux» | نفّذ أمر `allow-external-apps` أعلاه |
| شاشة سوداء بعد الانتقال | النظام غير مثبت بعد — نفّذ `bash s25-desktop/install.sh` داخل Termux |
| «تعذر التشغيل — افتح Termux» | افتح Termux مرة واحدة ثم أعد المحاولة (أندرويد يمنع بدء الخدمات من الخلف) |
| لا شيء يحدث | اضغط «تشخيص النظام» — يفتح جلسة Termux مرئية تُظهر سبب المشكلة |
| الأيقونة لا تفتح شيئاً بعد التحديث | أعد تثبيت الحزمة (`adb install -r` أو ثبّت فوق القديمة) |
