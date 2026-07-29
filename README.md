# Turnip Vulkan Driver — Adreno 830v2 (Galaxy S25 Ultra)

> ⚡ تعريف Vulkan مفتوح المصدر لجهاز Samsung Galaxy S25 Ultra
> مبني من Mesa Freedreno + Turnip مع باتشات A8xx مخصصة

## 📋 حالة المشروع

| البند | الحالة |
|-------|--------|
| Mesa Upstream A8xx | ✅ مدموج (Mesa 26.0+) |
| Turnip A830 Support | ✅ تجريبي (يعمل) |
| GMEM Rendering | ❌ غير مستقر (يسبب GPU hangs) |
| Sysmem Rendering | ✅ يعمل |
| KGSL Backend | ✅ مدعوم |
| UBWC 5/6 | ✅ مدعوم |
| Device ID 0x44050001 | ✅ معروف |

## 🚀 تحميل التعريف الجاهز

أسرع طريقة: حمل من [Banners-Turnip Releases](https://github.com/The412Banner/Banners-Turnip/releases/latest) واختر ملف `-A8xx.zip`.

أو استخدم الروابط المباشرة في [الدليل العربي](دليل-تثبيت-تيرنِب-830.html).

## 🖥️ جديد: نظام سطح مكتب كامل على الجوال (Claude PC + كروم الكمبيوتر)

مجلد [`s25-desktop/`](s25-desktop/) يحوّل الجهاز إلى كمبيوتر لينكس حقيقي يستفيد من
تعريف Turnip المبني هنا — **بدون روت**:

- حاوية **Debian arm64** بسطح مكتب **XFCE** داخل Termux (proot) وعرض عبر Termux:X11
- **Claude PC** — تطبيق سطح مكتب بنافذة وأيقونة مستقلة (حزمة المجتمع أو غلاف Electron)
- **كروم سطح المكتب** (Chromium arm64) بتسريع GPU عبر ANGLE ⇢ Vulkan ⇢ Turnip
- **Claude Code CLI** الرسمي داخل الطرفية
- بناء Mesa بنسخة **glibc** (Turnip/KGSL + Zink) لأن تعريف أندرويد لا يعمل داخل الحاوية

```bash
pkg install git -y
git clone https://github.com/basio96547/turnip-a830-s25ultra
cd turnip-a830-s25ultra
bash s25-desktop/install.sh          # أو: --mesa-tarball <حزمة من Actions> للتثبيت السريع

s25-desktop            # سطح مكتب كامل
s25-desktop claude     # Claude PC بملء الشاشة
s25-desktop chrome     # كروم سطح المكتب
```

📖 الدليل الكامل: [s25-desktop/docs/README.md](s25-desktop/docs/README.md) ·
حل المشاكل: [TROUBLESHOOTING.md](s25-desktop/docs/TROUBLESHOOTING.md)

## 🛠️ البناء من المصدر

### المتطلبات
- Linux x86_64 (Ubuntu 22.04+)
- Android NDK r29
- git, meson, ninja, patchelf, glslang

### خطوات البناء
```bash
chmod +x build-turnip-a830.sh
./build-turnip-a830.sh
```

الملف الناتج: `turnip_workdir_a830/Turnip-A830v2-*.zip`

## 🤖 البناء التلقائي (GitHub Actions)

يتم البناء تلقائياً عند كل push + كل أسبوع. الناتج يظهر في:
- **Artifacts**: علامة تبويب Actions في المستودع
- **Releases**: إصدار تلقائي مع ملف ZIP

## ⚙️ هيكل الملفات

```
.
├── build-turnip-a830.sh          # سكربت البناء الرئيسي (أندرويد/bionic)
├── apply_a830_gpus.py            # إضافة إدخالات GPU
├── fix_a830_dev_info.py          # إصلاح fd_dev_info.h
├── patches-a830/
│   └── adreno_830v2.patch        # باتش التخصيص لـ A830v2
├── s25-desktop/                  # نظام سطح المكتب: Claude PC + كروم على الجوال
│   ├── install.sh                #   المُثبّت (يعمل داخل Termux)
│   ├── termux/                   #   X11 + صوت + proot-distro + أوامر التشغيل
│   ├── container/                #   XFCE + Mesa glibc + Chromium + Claude PC
│   └── docs/                     #   الدليل وحل المشاكل
├── .github/workflows/
│   ├── build-turnip-a830.yml     # بناء تعريف أندرويد للمحاكيات
│   ├── build-mesa-glibc-arm64.yml# بناء Mesa لحاويات proot (glibc)
│   └── lint-s25-desktop.yml      # فحص سكربتات s25-desktop
└── دليل-تثبيت-تيرنِب-830.html    # الدليل العربي الشامل
```

## ⚠️ ملاحظات مهمة

1. **يجب استخدام `TU_DEBUG=sysmem`** — GMEM يسبب GPU hangs على A830
2. التعريف تجريبي — A8xx support لا يزال قيد التطوير النشط في Mesa
3. للحصول على أفضل أداء: فعّل Async Shaders + Disk Shader Cache في المحاكي
4. للمشاكل: افتح [issue](https://github.com/The412Banner/Banners-Turnip/issues) في مستودع Banners-Turnip

## 📊 مواصفات الجهاز (Galaxy S25 Ultra)

- **SoC**: Snapdragon 8 Elite (SM8750)
- **GPU**: Adreno 830v2
- **Device ID**: 0x44050001
- **GMEM**: 12 MB
- **Vulkan**: 1.3.284 / Instance 1.4.0
- **FT Policy**: 0xC2

## 🙏 الشكر

- [Mesa Freedreno Team](https://gitlab.freedesktop.org/mesa/mesa)
- [Rob Clark](https://gitlab.freedesktop.org/robclark) — Freedreno maintainer
- [The412Banner](https://github.com/The412Banner) — A8xx build automation
- [whitebelyash](https://github.com/whitebelyash) — A8xx patches pioneer
- [K11MCH1](https://github.com/K11MCH1) — AdrenoToolsDrivers
- [StevenMXZ](https://github.com/StevenMXZ) — CI infrastructure
