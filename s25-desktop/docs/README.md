# تشغيل برامج ويندوز (.exe) على Galaxy S25 Ultra

> نظام يشغّل **Claude Desktop لويندوز** و**Google Chrome لويندوز** — ملفات
> `.exe` الرسمية نفسها — على جوال S25 Ultra، بتسريع رسوميات عبر تعريف
> **Turnip A830v2** الذي يبنيه هذا المستودع.
>
> **بدون روت.** لا فتح بوتلودر ولا تعديل نظام.

---

## 1. كيف يعمل؟

```
┌─ Android (S25 Ultra · Snapdragon 8 Elite) ───────────────────────────┐
│                                                                      │
│  تطبيق S25 Desktop ──► Termux ──────────┐  Termux:X11 (شاشة العرض)   │
│  (أيقونة على الشاشة)   • proot-distro   │   • لمس + لوحة مفاتيح       │
│                        • PulseAudio      │   • حافظة مشتركة           │
│                                          │                            │
│  ┌─ حاوية Debian arm64 ──────────────────┴────────────────────┐       │
│  │  سطح مكتب XFCE                                            │       │
│  │                                                           │       │
│  │   Claude.exe / chrome.exe        ← برامج ويندوز x86_64     │       │
│  │        └─ Wine    ← واجهات ويندوز                          │       │
│  │            └─ box64  ← ترجمة x86_64 إلى ARM64             │       │
│  │                └─ DXVK  ← Direct3D إلى Vulkan             │       │
│  └────────────────────────────┬──────────────────────────────┘       │
│                     Turnip (Mesa) — بناء glibc · TU_DEBUG=sysmem      │
│                                │                                     │
│                         /dev/kgsl-3d0 · Adreno 830v2 (0x44050001)     │
└──────────────────────────────────────────────────────────────────────┘
```

**ليست محاكاة ويندوز كاملة:** Wine يترجم نداءات ويندوز إلى نداءات لينكس — لا
نظام ويندوز داخل الجوال ولا حاجة لترخيص. نفس مبدأ Winlator.

**نقطة مهمة عن التعريف:** ملف `libvulkan_freedreno.so` الذي يبنيه
`build-turnip-a830.sh` في جذر المستودع مبني لأندرويد (bionic) ويُستخدم في
المحاكيات. لا يُحمَّل داخل حاوية glibc، لذلك يبني
`container/build-mesa-turnip.sh` نسخة **glibc** من نفس المصدر ونفس باتشات A8xx
في `/opt/s25/mesa`.

---

## 2. المتطلبات

| البند | التفاصيل |
|-------|----------|
| الجهاز | Galaxy S25 Ultra (أو أي جهاز Adreno 8xx بنواة KGSL) |
| Termux | من **F-Droid** أو **GitHub** — نسخة Play Store قديمة ولا تعمل |
| Termux:X11 | APK من [termux-x11/releases](https://github.com/termux/termux-x11/releases) (`app-arm64-v8a-debug.apk`) |
| تطبيق التشغيل | [`s25-launcher`](../../s25-launcher/) — أيقونة تشغّل كل شيء (اختياري لكن مريح) |
| مساحة | ~10 غيغابايت (14 إن بنيت Mesa على الجهاز) |
| موصى به | لوحة مفاتيح وماوس بلوتوث + شاشة خارجية أو Samsung DeX |

---

## 3. التثبيت

### 3.1 الطريقة السريعة (موصى بها)

بناء Mesa على الجوال يستغرق 40 دقيقة إلى ساعتين. الأسرع تنزيل حزمة مبنية من
GitHub Actions (سير العمل `Build Mesa (Turnip KGSL + Zink) — proot glibc arm64`):

```bash
pkg install git -y
git clone https://github.com/basio96547/turnip-a830-s25ultra
cd turnip-a830-s25ultra
bash s25-desktop/install.sh \
  --mesa-tarball ~/storage/downloads/mesa-a830-glibc-arm64.tar.gz
```

### 3.2 البناء الكامل على الجهاز

```bash
bash s25-desktop/install.sh
```

أوصل الشاحن وابقِ Termux في المقدمة. المُثبّت ينفّذ بالترتيب: تهيئة Termux →
حاوية Debian + XFCE → Mesa/Turnip → طبقة ويندوز (Wine + box64 + DXVK).

### خيارات `install.sh`

| الخيار | الوظيفة |
|--------|---------|
| `--mesa-tarball <path\|url>` | حزمة Mesa جاهزة بدل البناء |
| `--mesa-ref <ref>` | فرع/وسم Mesa (افتراضي `main`) |
| `--jobs <N>` | مهام الترجمة (قلّلها إن نفدت الذاكرة) |
| `--skip-mesa` | بلا Turnip — رسوميات على المعالج (أبطأ بكثير) |
| `--skip-windows` | بلا طبقة ويندوز (حاوية وسطح مكتب فقط) |
| `-y` | بلا أسئلة تأكيد |

---

## 4. التشغيل

### 4.1 من أيقونة على الشاشة الرئيسية

ثبّت تطبيق **S25 Desktop**
([`prebuilt/S25-Desktop-launcher.apk`](../../s25-launcher/prebuilt/S25-Desktop-launcher.apk)):
أزرار مباشرة لـ Claude Desktop (ويندوز) وChrome (ويندوز) وسطح المكتب والتشخيص
والإيقاف، وينقلك تلقائياً إلى شاشة العرض. الضغط الطويل على الأيقونة يعطي
اختصارات يمكن سحبها كأيقونات مستقلة. التفاصيل:
[`s25-launcher/README.md`](../../s25-launcher/README.md).

### 4.2 من Termux

```bash
s25-desktop win-claude # Claude Desktop لويندوز (.exe)
s25-desktop win-chrome # Chrome لويندوز (.exe)
s25-desktop windows    # winecfg — للتأكد أن طبقة ويندوز تعمل
s25-desktop            # سطح مكتب XFCE كامل
s25-desktop shell      # طرفية داخل الحاوية
s25-stop               # إيقاف كل شيء وتحرير الذاكرة والبطارية
```

بعد التشغيل انتقل إلى تطبيق **Termux:X11** لرؤية الواجهة.

### 4.3 داخل الحاوية

| الأمر | الوظيفة |
|------|---------|
| `claude-pc-win` | Claude Desktop لويندوز (ينزّل المُثبّت أول مرة) |
| `chrome-pc-win` | Chrome لويندوز (حزمة MSI الرسمية) |
| `win-run <ملف.exe>` | تشغيل أي برنامج ويندوز — يدعم `.msi` أيضاً |
| `win-run winecfg` | إعدادات Wine |
| `s25-doctor` | تشخيص: GPU · عرض · صوت · box64 · Wine · DXVK |

ملفات تنزيلات الجوال متاحة داخل الحاوية في `/mnt/sdcard/Download`:

```bash
win-run /mnt/sdcard/Download/AnyApp-Setup.exe
```

---

## 5. توقعات الأداء — بصراحة

| البرنامج | التوقع |
|----------|--------|
| برامج ويندوز البسيطة | تعمل عادةً بشكل مقبول |
| Claude Desktop (Electron) | **أصعب حالة**: عمليات متعددة + sandbox + GPU. قد يعمل ببطء أو لا يبدأ على بعض بناءات Wine |
| Chrome لويندوز | نفس المشكلة، ويحتاج `--no-sandbox` (مضبوط تلقائياً) |
| الألعاب الثقيلة | خارج نطاق المشروع |

سلّم الحلول عند الفشل، ودليل Wine الكامل: [WINDOWS.md](WINDOWS.md).

**بديل جاهز:** [Winlator](WINDOWS.md#البديل-الجاهز-winlator) يجمع نفس المكوّنات
في تطبيق واحد ويقبل تعريف Turnip من هذا المستودع بصيغة adrenotools.

---

## 6. الرسوميات

| الطبقة | ما يُستخدم |
|--------|-----------|
| Vulkan | Turnip (Mesa) — بناء glibc بخلفية KGSL |
| Direct3D 9/10/11 | DXVK فوق Vulkan |
| OpenGL | Zink فوق Vulkan (وWineD3D عند `--no-dxvk`) |
| احتياطي | llvmpipe / lavapipe على المعالج |

إعدادات إلزامية مضبوطة تلقائياً في `/opt/s25/etc/env.sh`:

- `TU_DEBUG=sysmem` — **إلزامي**: GMEM يسبب تعليق GPU على A830
- `LIBGL_KOPPER_DRI2=1` — لأن Termux:X11 لا يوفر DRI3
- `MESA_LOADER_DRIVER_OVERRIDE=zink`

متغيرات يمكن تعديلها (أو في `$PREFIX/etc/s25-desktop.conf`):

```bash
S25_GPU=off  s25-desktop win-chrome   # تعطيل تسريع GPU للتشخيص
S25_DPI=170  s25-desktop              # تكبير خطوط سطح المكتب
S25_SCALE=1.7 s25-desktop win-claude  # تكبير واجهة البرنامج
TU_DEBUG=sysmem,nolrz s25-desktop     # عند أخطاء رسم
```

---

## 7. نصائح على الجوال

- **شاشة أكبر**: Samsung DeX عبر USB-C → HDMI، أو شاشة لاسلكية.
- **لوحة مفاتيح وماوس**: بلوتوث أو USB OTG — تجربة قريبة من الكمبيوتر.
- **بدون ماوس**: في تطبيق Termux:X11 فعّل وضع المؤشر (Trackpad) من قائمته.
- **الحرارة والبطارية**: `s25-stop` بعد الانتهاء يحرر الذاكرة ويوقف wake-lock.

---

## 8. الملفات

```
s25-desktop/
├── install.sh                      # المُثبّت (يعمل في Termux)
├── lib/common.sh                   # دوال مشتركة
├── termux/
│   ├── setup-termux.sh             # X11 + صوت + proot-distro + صلاحية المُشغّل
│   ├── provision-container.sh      # تثبيت الحاوية وتشغيل مراحل التهيئة
│   ├── start-desktop.sh            # ← يُثبّت كـ s25-desktop
│   └── stop-desktop.sh             # ← يُثبّت كـ s25-stop
├── container/
│   ├── bootstrap-debian.sh         # XFCE + مستخدم + لغات + إعدادات الشاشة
│   ├── build-mesa-turnip.sh        # Mesa glibc: Turnip/KGSL + Zink
│   ├── install-windows-layer.sh    # Wine + box64 + DXVK + بيئة ويندوز
│   ├── lib-multiarch.sh            # box64 ومكتبات x86_64
│   ├── bin/                        # s25-session · s25-app · win-run
│   │                               #   claude-pc-win · chrome-pc-win · s25-doctor
│   └── etc/env.sh                  # بيئة الرسوميات والصوت والعرض
└── docs/
    ├── README.md                   # هذا الملف
    ├── WINDOWS.md                  # طبقة ويندوز بالتفصيل
    └── TROUBLESHOOTING.md          # حل المشاكل
```

---

## 9. الإزالة

```bash
s25-stop
proot-distro remove debian
rm -f $PREFIX/bin/s25-desktop $PREFIX/bin/s25-stop $PREFIX/etc/s25-desktop.conf
```

---

## 10. شكر

[Mesa/Freedreno](https://gitlab.freedesktop.org/mesa/mesa) ·
[Turnip A8xx patches](https://github.com/The412Banner/Banners-Turnip) ·
[Termux](https://github.com/termux) و[Termux:X11](https://github.com/termux/termux-x11) ·
[proot-distro](https://github.com/termux/proot-distro) ·
[Wine](https://www.winehq.org/) ·
[box64](https://github.com/ptitSeb/box64) ·
[DXVK](https://github.com/doitsujin/dxvk) ·
[Kron4ek Wine-Builds](https://github.com/Kron4ek/Wine-Builds) ·
[Winlator](https://github.com/brunodev85/winlator).

Claude و Anthropic و Google Chrome علامات تجارية لأصحابها؛ هذا مشروع مستقل غير
رسمي ولا يوزّع أي برنامج منها — التنزيل يتم من مصادرها الرسمية عند التشغيل.
