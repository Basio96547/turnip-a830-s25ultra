# نظام سطح المكتب على Galaxy S25 Ultra — Claude PC + كروم الكمبيوتر

> يحوّل جوال S25 Ultra إلى جهاز لينكس سطح مكتب حقيقي: نظام Debian كامل بواجهة
> XFCE، مع **Claude كتطبيق سطح مكتب** و **كروم سطح المكتب** (نسخة الكمبيوتر
> الكاملة لا نسخة الجوال)، وكل ذلك مسرّع على GPU الجهاز عبر تعريف **Turnip
> A830v2** الذي يبنيه هذا المستودع.
>
> **بدون روت.** لا حاجة لفتح البوتلودر ولا لتعديل النظام.

---

## 1. كيف يعمل؟ (المعمارية)

```
┌─ Android 15/16 (S25 Ultra · Snapdragon 8 Elite) ─────────────────────┐
│                                                                      │
│  Termux ────────────────────────┐   Termux:X11 (تطبيق العرض)         │
│   • proot-distro (حاوية بدون روت)│    • شاشة + لمس + لوحة مفاتيح       │
│   • PulseAudio (صوت عبر TCP)     │    • حافظة مشتركة                  │
│                                  │                                    │
│  ┌─ حاوية Debian arm64 ──────────┴──────────────────────────────┐     │
│  │  سطح مكتب XFCE                                              │     │
│  │  ├── Claude PC   (تطبيق Electron — نافذة مستقلة)             │     │
│  │  ├── chrome-pc   (Chromium سطح المكتب)                       │     │
│  │  └── claude      (Claude Code CLI في الطرفية)                │     │
│  │                                                             │     │
│  │  الرسوميات:  Chromium/Electron ─► ANGLE ─► Vulkan            │     │
│  │              تطبيقات OpenGL     ─► Zink  ─► Vulkan           │     │
│  │                                            │                 │     │
│  └────────────────────────────────────────────┼─────────────────┘     │
│                                    Turnip (Mesa) — بناء glibc         │
│                                               │                       │
│                                        /dev/kgsl-3d0                  │
│                                     Adreno 830v2 (0x44050001)         │
└──────────────────────────────────────────────────────────────────────┘
```

**نقطة مهمة عن التعريف:** ملف `libvulkan_freedreno.so` الذي يبنيه
`build-turnip-a830.sh` في جذر المستودع مبني لـ **أندرويد (bionic)** ويُستخدم في
محاكيات مثل Citron/Eden. لا يمكن تحميله داخل حاوية glibc، لذلك يبني
`s25-desktop/container/build-mesa-turnip.sh` نسخة **glibc** من نفس المصدر ونفس
باتشات A8xx وتُثبَّت في `/opt/s25/mesa`. النتيجة: نفس تعريف Turnip يخدم
المحاكيات وسطح المكتب، كل واحد بنسخته.

---

## 2. المتطلبات

| البند | التفاصيل |
|-------|----------|
| الجهاز | Galaxy S25 Ultra (أو أي جهاز Adreno 8xx بنواة KGSL) |
| Termux | من **F-Droid** أو **GitHub** — نسخة Play Store قديمة ولا تعمل |
| Termux:X11 | ملف APK من [termux-x11/releases](https://github.com/termux/termux-x11/releases) (`app-arm64-v8a-debug.apk`) |
| مساحة | ~8 غيغابايت (12 غيغابايت إن بنيت Mesa على الجهاز) |
| إنترنت | مطلوب أثناء التثبيت فقط |
| موصى به | لوحة مفاتيح وماوس بلوتوث + شاشة خارجية (أو Samsung DeX للشاشة) |

---

## 3. التثبيت

### 3.1 الطريقة السريعة (موصى بها)

بناء Mesa على الجوال يستغرق **40 دقيقة إلى ساعتين**. الأسرع هو تنزيل حزمة مبنية
من GitHub Actions (سير العمل `Build Mesa (Turnip KGSL + Zink) — proot glibc arm64`)
ثم:

```bash
pkg install git -y
git clone https://github.com/basio96547/turnip-a830-s25ultra
cd turnip-a830-s25ultra

# الحزمة المنزّلة موجودة في مجلد التنزيلات
bash s25-desktop/install.sh \
  --mesa-tarball ~/storage/downloads/mesa-a830-glibc-arm64.tar.gz
```

### 3.2 البناء الكامل على الجهاز

```bash
pkg install git -y
git clone https://github.com/basio96547/turnip-a830-s25ultra
cd turnip-a830-s25ultra
bash s25-desktop/install.sh          # يبني Mesa داخل الحاوية
```

أوصل الشاحن وابقِ Termux في المقدمة (أو استخدم `termux-wake-lock`).

### 3.3 بدون تسريع GPU (تثبيت سريع للتجربة)

```bash
bash s25-desktop/install.sh --skip-mesa      # رسوميات على المعالج — بطيء لكنه يعمل
```

### خيارات `install.sh`

| الخيار | الوظيفة |
|--------|---------|
| `--mesa-tarball <path\|url>` | استخدام حزمة Mesa جاهزة بدل البناء |
| `--mesa-ref <ref>` | فرع/وسم Mesa (افتراضي `main`) |
| `--jobs <N>` | عدد مهام الترجمة (قلّلها إن نفدت الذاكرة) |
| `--claude-mode auto\|community\|wrapper` | طريقة تثبيت Claude PC |
| `--skip-mesa` / `--skip-chromium` / `--skip-claude` | تخطي مرحلة |
| `--with-chrome-x86` | إضافة Chrome الرسمي amd64 عبر box64 (تجريبي) |
| `-y` | بدون أسئلة تأكيد |

---

## 4. التشغيل

### 4.1 من أيقونة على الشاشة الرئيسية (الأسهل)

ثبّت تطبيق **S25 Desktop** — أيقونة تفتح النظام بضغطة واحدة وتنقلك إلى شاشة
العرض تلقائياً، وفيها أزرار: Claude PC · كروم سطح المكتب · سطح المكتب الكامل ·
تشخيص · إيقاف الكل.

- الحزمة الجاهزة: [`s25-launcher/prebuilt/S25-Desktop-launcher.apk`](../../s25-launcher/prebuilt/S25-Desktop-launcher.apk)
- التفاصيل والبناء من المصدر: [`s25-launcher/README.md`](../../s25-launcher/README.md)

الضغط الطويل على الأيقونة يعطي اختصارات مباشرة يمكن سحبها للشاشة الرئيسية
(أيقونة مستقلة لـ Claude PC مثلاً).

### 4.2 من Termux

```bash
s25-desktop            # سطح مكتب XFCE كامل
s25-desktop claude     # Claude PC وحده بملء الشاشة
s25-desktop chrome     # كروم سطح المكتب وحده
s25-desktop shell      # طرفية داخل الحاوية (بدون واجهة)
s25-stop               # إيقاف كل شيء وتحرير الذاكرة والبطارية
```

بعد التشغيل، انتقل إلى تطبيق **Termux:X11** لرؤية سطح المكتب. يمكن أيضاً وضع
اختصارات على الشاشة الرئيسية عبر تطبيق **Termux:Widget** (الاختصارات جاهزة في
`~/.shortcuts`).

داخل سطح المكتب:

| الأمر | الوظيفة |
|------|---------|
| `claude-pc` | تطبيق Claude لسطح المكتب |
| `chrome-pc` | كروم سطح المكتب |
| `claude` | Claude Code CLI في الطرفية |
| `s25-doctor` | تشخيص شامل (GPU، عرض، صوت، تطبيقات) |
| `chrome-x86` | Chrome الرسمي amd64 عبر box64 (إن ثُبّت) |

---

## 5. هل «Claude PC» تطبيق فعلي؟

نعم — نافذة تطبيق مستقلة بأيقونتها وقائمتها واختصاراتها، وليست تبويب متصفح.
لكن يجب توضيح الوضع بدقة:

- **Anthropic لا تصدر Claude Desktop لـ Linux** (macOS و Windows فقط)، ولا يوجد
  إصدار لـ arm64. لذلك يوفر النظام مسارين:

| الوضع | ما هو | الميزات | المخاطر |
|-------|-------|---------|---------|
| `community` | حزمة [claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian) — تعيد تغليف ملفات النسخة الرسمية في تطبيق Electron لـ Linux/arm64 | تطبيق سطح المكتب الحقيقي، يدعم MCP | مشروع مجتمعي؛ قد يتعطل عند تحديث Anthropic لملفاتها |
| `wrapper` | تطبيق Electron محلي في `/opt/s25/claude-pc` يفتح `claude.ai` في نافذة تطبيق | مستقر، خفيف، أيقونة وقائمة عربية، جلسة دخول محفوظة، ملء شاشة، تكبير | لا يدعم MCP ولا الأدوات المحلية؛ المحتوى من الويب |

الوضع الافتراضي `auto`: يحاول حزمة المجتمع، وإن فشلت يثبّت الغلاف (ويُثبَّت
الغلاف أيضاً كخطة بديلة عند نجاح الحزمة).

- **Claude Code CLI** هو الأداة الرسمية الوحيدة من Anthropic التي تعمل أصلاً على
  Linux/arm64، ويُثبَّت تلقائياً — شغّله بكتابة `claude` في الطرفية.

لفرض وضع معيّن:

```bash
S25_CLAUDE_IMPL=wrapper claude-pc     # الغلاف
S25_CLAUDE_IMPL=desktop claude-pc     # حزمة المجتمع
S25_CLAUDE_URL=https://claude.ai/code claude-pc
```

---

## 6. لماذا Chromium وليس Google Chrome؟

Google تصدر Chrome لـ Linux على **amd64 فقط** — لا نسخة arm64. Chromium هو نفس
المحرك (Blink/V8) ونفس واجهة سطح المكتب الكاملة، ويعمل **أصلاً** على معالج
الجهاز، أي أسرع بمراحل من أي محاكاة. الملفات، الإضافات، أدوات المطور، عدة
نوافذ، تبويبات — كلها كما في الكمبيوتر.

من يريد Chrome الرسمي بالاسم والشعار: `--with-chrome-x86` يشغّله عبر box64
(ترجمة x86_64 لحظية). يعمل، لكنه بطيء وبدون تسريع GPU — للتجربة فقط.

---

## 7. الرسوميات والأداء

| الطبقة | ما يُستخدم |
|--------|-----------|
| Vulkan | Turnip (Mesa) — بناء glibc بخلفية KGSL |
| Chromium / Electron | ANGLE فوق Vulkan (بدون طبقة OpenGL — الأسرع والأكثر استقراراً) |
| تطبيقات OpenGL | Zink فوق Vulkan |
| احتياطي | llvmpipe / lavapipe على المعالج |

إعدادات إلزامية لـ A830 مضبوطة تلقائياً في `/opt/s25/etc/env.sh`:

- `TU_DEBUG=sysmem` — **إلزامي**: GMEM يسبب تعليق الـ GPU على هذا الجهاز
- `LIBGL_KOPPER_DRI2=1` — لأن Termux:X11 لا يوفر DRI3
- `MESA_LOADER_DRIVER_OVERRIDE=zink` + `GALLIUM_DRIVER=zink`

متغيرات يمكنك تعديلها (في `$PREFIX/etc/s25-desktop.conf` أو قبل الأمر):

```bash
S25_GPU=off  s25-desktop        # تعطيل تسريع GPU مؤقتاً
S25_DPI=170  s25-desktop        # تكبير خطوط سطح المكتب
S25_SCALE=1.7 s25-desktop chrome # تكبير واجهة كروم/Claude
TU_DEBUG=sysmem,nolrz s25-desktop  # عند وجود أخطاء رسم
```

للتحقق من عمل التسريع:

```bash
s25-desktop shell
s25-doctor              # يجب أن يظهر: جهاز Vulkan = Turnip Adreno 830
```

---

## 8. نصائح استخدام على الجوال

- **شاشة أكبر**: Samsung DeX عبر USB-C → HDMI، أو شاشة لاسلكية. Termux:X11 يتبع
  دقة الشاشة النشطة.
- **لوحة مفاتيح وماوس**: بلوتوث أو USB OTG — تجربة قريبة من الكمبيوتر تماماً.
- **بدون ماوس**: في تطبيق Termux:X11 فعّل وضع المؤشر (touchpad mode) من قائمته.
- **الحرارة والبطارية**: البناء ثقيل؛ التشغيل اليومي معتدل. `s25-stop` يحرر كل
  شيء عند الانتهاء.
- **الملفات**: تخزين الجوال متاح داخل الحاوية في `/mnt/sdcard`.

---

## 9. ما يعمل وما لا يعمل

**يعمل:** سطح مكتب XFCE، كروم سطح المكتب بتبويبات وإضافات، Claude PC كتطبيق،
Claude Code CLI، طرفية كاملة، محرر نصوص، مدير ملفات، صوت، حافظة مشتركة،
تشغيل فيديو (بفك ترميز على المعالج).

**لا يعمل / محدود:**
- الفيديو المسرّع بالعتاد (VA-API) غير مدعوم في هذا المسار — فك الترميز على المعالج.
- Widevine (نتفليكس وشبيهاتها) غير متوفر لـ Chromium arm64.
- تطبيقات x86_64 تحتاج box64 وأداؤها متواضع.
- MCP والأدوات المحلية تعمل فقط مع حزمة المجتمع لا مع الغلاف.
- التعريف تجريبي: A8xx في Mesa لا يزال تحت التطوير — توقّع أخطاء رسم عرضية.

---

## 10. الملفات

```
s25-desktop/
├── install.sh                      # المُثبّت الرئيسي (يعمل في Termux)
├── lib/common.sh                   # دوال مشتركة
├── termux/
│   ├── setup-termux.sh             # X11 + صوت + proot-distro
│   ├── provision-container.sh      # تثبيت الحاوية وتشغيل مراحل التهيئة
│   ├── start-desktop.sh            # ← يُثبّت كـ s25-desktop
│   ├── stop-desktop.sh             # ← يُثبّت كـ s25-stop
│   └── shortcuts/                  # اختصارات Termux:Widget
├── container/
│   ├── bootstrap-debian.sh         # XFCE + مستخدم + لغات + إعدادات الشاشة
│   ├── build-mesa-turnip.sh        # Mesa glibc: Turnip/KGSL + Zink
│   ├── install-chromium.sh         # كروم سطح المكتب
│   ├── install-claude-desktop.sh   # Claude PC + Claude Code CLI
│   ├── install-chrome-x86.sh       # Chrome amd64 عبر box64 (تجريبي)
│   ├── claude-pc-app/              # تطبيق Electron (main.js, preload.js)
│   ├── bin/                        # s25-session, s25-app, chrome-pc, claude-pc, s25-doctor
│   └── etc/env.sh                  # بيئة الرسوميات والصوت والعرض
└── docs/
    ├── README.md                   # هذا الملف
    └── TROUBLESHOOTING.md          # حل المشاكل
```

---

## 11. الإزالة

```bash
s25-stop
proot-distro remove debian
rm -f $PREFIX/bin/s25-desktop $PREFIX/bin/s25-stop $PREFIX/etc/s25-desktop.conf
rm -f ~/.shortcuts/S25-*.sh ~/.shortcuts/Claude-PC.sh ~/.shortcuts/Chrome-PC.sh
```

---

## 12. شكر

هذا النظام مبني فوق عمل: [Mesa/Freedreno](https://gitlab.freedesktop.org/mesa/mesa)،
[Turnip A8xx patches](https://github.com/The412Banner/Banners-Turnip)،
[Termux](https://github.com/termux) و [Termux:X11](https://github.com/termux/termux-x11)،
[proot-distro](https://github.com/termux/proot-distro)،
[box64](https://github.com/ptitSeb/box64)،
[claude-desktop-debian](https://github.com/aaddrick/claude-desktop-debian).

Claude و Anthropic علامتان تجاريتان لشركة Anthropic؛ هذا المستودع مشروع مستقل
غير رسمي.
