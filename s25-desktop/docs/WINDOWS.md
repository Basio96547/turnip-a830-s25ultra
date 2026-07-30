# تشغيل ملفات ويندوز (.exe) على Galaxy S25 Ultra

تشغيل **Claude Desktop لويندوز** و**Google Chrome لويندوز** — ملفات `.exe`
الرسمية نفسها — على الجوال، بتسريع رسوميات عبر تعريف Turnip الذي يبنيه هذا
المستودع.

---

## كيف تعمل السلسلة

```
   برنامج ويندوز (.exe · x86_64)
        │
        ▼
   Wine ─────────── يوفّر واجهات ويندوز (ليس محاكاة نظام كامل)
        │
        ▼
   box64 ────────── يترجم تعليمات x86_64 إلى ARM64 لحظياً
        │
        ▼
   DXVK ─────────── يحوّل Direct3D 9/10/11 إلى Vulkan
        │
        ▼
   Turnip (Mesa) ── تعريف Adreno 830v2 · TU_DEBUG=sysmem
        │
        ▼
   /dev/kgsl-3d0 ── GPU الجهاز (Snapdragon 8 Elite)
```

**ليست محاكاة ويندوز كاملة**: Wine يترجم نداءات ويندوز إلى نداءات لينكس، فلا
يوجد نظام ويندوز داخل الجوال ولا حاجة لترخيص. هذا نفس مبدأ عمل Winlator.

### لماذا بناء `amd64-wow64` تحديداً؟

هذه أهم نقطة تقنية في الطبقة كلها، وقد تحققنا منها عملياً:

| بناء Wine | `bin/wine` | برامج ويندوز 32-بت |
|-----------|-----------|---------------------|
| `wine-*-amd64.tar.xz` | ELF **32-بت** | تحتاج **box86** — لا تعمل هنا |
| `wine-*-amd64-wow64.tar.xz` | ELF **64-بت** (بلا `wine64`) | تعمل عبر مُحمّل 64-بت → **box64 وحده يكفي** ✓ |

ولماذا يهم؟ لأن **مُثبّت Claude لويندوز (`Claude-Setup-x64.exe`) ملف 32-بت** رغم
اسمه — تحقّقنا: `PE32 executable (GUI) Intel 80386`. فلو استُخدم البناء الأول لما
عمل المُثبّت إطلاقاً على الجوال.

السكربت يختار البناء الصحيح تلقائياً، ويحذّرك إن انتهى بك بناء قديم:

```
⚠ هذا بناء WoW64 القديم (bin/wine ملف 32-بت).
```

---

## التثبيت

```bash
# داخل Termux
bash s25-desktop/install.sh
```

أو على نظام مثبّت مسبقاً:

```bash
s25-desktop shell
sudo bash /opt/s25/src/install-windows-layer.sh
```

يُنزّل: box64 + مكتبات x86_64 + بناء Wine + DXVK ≈ **1.5 غيغابايت**.

الأوقات الواقعية (قِست على معالج حاسوب، فالجوال أبطأ):

| المرحلة | الوقت |
|---------|-------|
| التنزيلات | 10–30 دقيقة حسب الشبكة |
| `wineboot` (إنشاء بيئة ويندوز) | **10–30 دقيقة** — استغرقت أكثر من 10 دقائق حتى على حاسوب. لا تقطعها |
| تثبيت Claude أو Chrome (أول تشغيل) | 5–20 دقيقة |

### خيارات

| الخيار | الوظيفة |
|--------|---------|
| `--wine-url <url>` | بناء Wine محدد (الافتراضي: أحدث `amd64-wow64` من Kron4ek) |
| `--dxvk-url <url>` | إصدار DXVK محدد |
| `--no-dxvk` | بدون DXVK (WineD3D فوق OpenGL/Zink — أبطأ لكن أوسع توافقاً) |
| `--prefix-only` | إعادة إنشاء بيئة ويندوز فقط (إصلاح بيئة تالفة) |

---

## التشغيل

من Termux مباشرة:

```bash
s25-desktop win-claude     # Claude Desktop لويندوز
s25-desktop win-chrome     # Chrome لويندوز
s25-desktop windows        # winecfg — للتأكد أن الطبقة تعمل
```

من داخل سطح المكتب:

| الأمر | الوظيفة |
|------|---------|
| `claude-pc-win` | ينزّل Claude-Setup-x64.exe أول مرة ثم يشغّل claude.exe |
| `chrome-pc-win` | ينزّل حزمة Chrome Enterprise MSI ثم يشغّل chrome.exe |
| `win-run <ملف.exe>` | تشغيل أي برنامج ويندوز آخر |
| `win-run winecfg` | إعدادات Wine |
| `s25-doctor` | تشخيص: box64 · Wine · DXVK · Turnip |

ملفات التنزيل من الجوال متاحة داخل الحاوية في `/mnt/sdcard/Download`:

```bash
win-run /mnt/sdcard/Download/AnyApp-Setup.exe
```

لتثبيت نسخة نزّلتها بنفسك بدل التنزيل التلقائي:

```bash
S25_CLAUDE_SETUP_URL=/mnt/sdcard/Download/Claude-Setup-x64.exe claude-pc-win
S25_CHROME_MSI_URL=/mnt/sdcard/Download/chrome.msi chrome-pc-win
```

---

## توقعات الأداء — بصراحة

| البرنامج | التوقع |
|----------|--------|
| برامج ويندوز البسيطة (أدوات، محررات، مشغلات) | تعمل عادةً بشكل مقبول |
| Claude Desktop (Electron) | **الحالة الأصعب**: عمليات متعددة + sandbox + GPU. قد يعمل ببطء، وقد لا يبدأ إطلاقاً على بعض بناءات Wine |
| Chrome لويندوز | نفس المشكلة، ويحتاج `--no-sandbox` (مضبوط تلقائياً) |
| الألعاب الثقيلة | خارج نطاق هذا المشروع |

سبب الصعوبة: Chromium يستخدم عمليات معزولة وحماية على مستوى النظام، وWine
لا يحاكي كل تلك الطبقات. لهذا حتى على Winlator، تشغيل Chrome/Electron أصعب
بكثير من تشغيل برامج ويندوز التقليدية.

**إن لم يعمل أحدهما:** جرّب بالترتيب:

```bash
# 1. بدون DXVK
sudo bash /opt/s25/src/install-windows-layer.sh --no-dxvk

# 2. بدون تسريع GPU إطلاقاً
S25_GPU=off chrome-pc-win

# 3. بناء Wine مختلف — يجب أن يبقى amd64-wow64
sudo bash /opt/s25/src/install-windows-layer.sh \
  --wine-url https://github.com/Kron4ek/Wine-Builds/releases/download/10.0/wine-10.0-amd64-wow64.tar.xz

# 4. بيئة ويندوز جديدة نظيفة
sudo bash /opt/s25/src/install-windows-layer.sh --prefix-only
```

---

## البديل الجاهز: Winlator

Winlator تطبيق أندرويد يجمع نفس المكوّنات (Wine + Box64 + DXVK + Turnip) في
واجهة جاهزة، ويقبل تعريفات Turnip بصيغة adrenotools — أي **نفس ملف ZIP الذي
يبنيه هذا المستودع**:

1. ابنِ التعريف أو نزّله: `Turnip-A830v2-*.zip` (من Actions أو Releases)
2. في Winlator: `Settings ▸ Graphics Driver ▸ Import` واختر ملف ZIP
3. اضبط `Container ▸ Environment Variables` وأضف `TU_DEBUG=sysmem` — إلزامي على
   A830 لأن GMEM يسبب تعليق الـ GPU
4. ثبّت `.exe` داخل حاوية Winlator

الفرق: Winlator أسهل وأكثر ثباتاً لأنه مُعدّ مسبقاً، وطبقة هذا المستودع تعطيك
تحكماً كاملاً وتعمل داخل نفس حاوية سطح المكتب مع بقية أدواتك.

---

## مشاكل شائعة

| ما تراه | السبب / الحل |
|---------|--------------|
| `box64 غير مثبت` | `sudo bash /opt/s25/src/install-windows-layer.sh` |
| `wine: cannot find L"C:\\windows\\system32\\..."` | بيئة ويندوز ناقصة → `--prefix-only` |
| نافذة سوداء أو بلا رسم | `S25_GPU=off` للتشخيص، ثم جرّب `--no-dxvk` |
| `err:module:import_dll` | مكتبة ويندوز ناقصة — غالباً يحتاج البرنامج مكوّنات إضافية (Visual C++ Runtime) |
| بطء شديد جداً | متوقع لبرامج Chromium؛ فعّل `BOX64_DYNAREC_BIGBLOCK=2` وأعد المحاولة |
| `Failed to create OpenGL context` | Turnip غير مُحمّل → `s25-doctor` وتأكد أن الوضع `turnip` لا `software` |
| المُثبّت 32-بت لا يبدأ إطلاقاً | بناء Wine خطأ — `s25-doctor` سيقول «WoW64 قديم»؛ أعد التثبيت أو مرّر `--wine-url` لبناء `amd64-wow64` |
| `s25-doctor` يقول «بيئة ويندوز ناقصة» | `wineboot` انقطع قبل أن يكمل → `--prefix-only` وانتظر حتى ينتهي |
| نفاد الذاكرة | أغلق التطبيقات الأخرى؛ Wine + Chromium يستهلكان ذاكرة كبيرة |

للتشخيص المفصّل شغّل مع سجلات Wine:

```bash
WINEDEBUG=+loaddll,+err win-run "$CLAUDE_EXE" 2>&1 | tail -50
```
