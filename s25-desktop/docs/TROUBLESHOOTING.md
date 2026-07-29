# حل المشاكل — نظام سطح المكتب على S25 Ultra

ابدأ دائماً بالتشخيص:

```bash
s25-desktop shell
s25-doctor
```

---

## شاشة سوداء أو لا يفتح سطح المكتب

| السبب | الحل |
|-------|------|
| تطبيق Termux:X11 غير مثبت | ثبّت `app-arm64-v8a-debug.apk` من [releases](https://github.com/termux/termux-x11/releases) وافتحه مرة واحدة |
| نسخة الحزمة لا تطابق التطبيق | `pkg install termux-x11-nightly` ثم أعد تنزيل أحدث APK |
| مقبس X قديم عالق | `s25-stop` ثم `s25-desktop` |
| dbus لم يبدأ | `s25-desktop shell` ثم `sudo dbus-uuidgen > /etc/machine-id` |

للتحقق من خادم X:

```bash
s25-desktop shell
xdpyinfo | head -5      # يجب أن يطبع أبعاد الشاشة
```

---

## `s25-doctor` يقول: الرسوميات = software

يعني أن Turnip غير مُحمّل. التحقق بالترتيب:

1. **الجهاز**: `ls -l /dev/kgsl-3d0` — إن لم يوجد، الجهاز ليس Adreno/KGSL أو الجلسة
   لم تُشغّل عبر `proot-distro` (يجب أن تكون `/dev` مُمرَّرة).
2. **التعريف**: `ls -l /opt/s25/mesa/lib/libvulkan_freedreno.so` — إن لم يوجد فالبناء
   لم يكتمل:
   ```bash
   sudo bash /opt/s25/src/build-mesa-turnip.sh --jobs 2
   ```
3. **ملف ICD**: `echo $VK_DRIVER_FILES` ثم `cat "$VK_DRIVER_FILES"` — تأكد أن
   `library_path` يشير إلى ملف موجود.
4. **الاختبار المباشر**:
   ```bash
   VK_DRIVER_FILES=/opt/s25/mesa/share/vulkan/icd.d/freedreno_icd.aarch64.json \
   LD_LIBRARY_PATH=/opt/s25/mesa/lib TU_DEBUG=sysmem vulkaninfo --summary
   ```

---

## تعليق الـ GPU / الشاشة تتجمد / أخطاء رسم

هذا الجهاز **لا يتحمّل GMEM**. تأكد من:

```bash
echo $TU_DEBUG          # يجب أن يحتوي sysmem
```

إن استمرت المشكلة، أضف تدريجياً:

```bash
TU_DEBUG=sysmem,nolrz s25-desktop
TU_DEBUG=sysmem,nolrz,noconform s25-desktop
S25_GPU=off s25-desktop          # تشخيص: هل المشكلة من التعريف؟
```

---

## فشل بناء Mesa

| الرسالة | الحل |
|---------|------|
| `Killed` / نفاد الذاكرة | `--jobs 2` أو `--jobs 1`، وأغلق التطبيقات الأخرى |
| `no space left on device` | يحتاج ~10 غيغابايت مؤقتاً — أفرغ مساحة، أو استخدم `--mesa-tarball` |
| `libdrm >= 2.4.121 required` | السكربت يبنيه تلقائياً؛ إن فشل: `LIBDRM_TAG=libdrm-2.4.123 sudo bash /opt/s25/src/build-mesa-turnip.sh` |
| `meson version` قديم | `pip3 install --break-system-packages -U meson` |
| فشل باتش A8xx | جرّب إصداراً أقدم من Mesa: `--mesa-ref mesa-25.3` أو `--skip-patches` إن كان الدعم أصبح رسمياً |
| انقطاع الشبكة | السكربت يعيد المحاولة؛ أعد تشغيل الأمر — المصادر تُستأنف |

الأسرع دائماً: بناء الحزمة في GitHub Actions ثم:

```bash
bash s25-desktop/install.sh --mesa-tarball ~/storage/downloads/mesa-a830-glibc-arm64.tar.gz
```

---

## كروم لا يفتح / يُغلق فوراً

```bash
chrome-pc 2>&1 | tail -30
```

| الرسالة | الحل |
|---------|------|
| `Running as root without --no-sandbox` | شغّله كمستخدم `s25` (التشغيل الطبيعي يفعل ذلك) |
| `Failed to create GPU process` | `S25_GPU=off chrome-pc` — ثم افحص Turnip بـ `s25-doctor` |
| `bus error` / انهيار عشوائي | `S25_CHROME_FLAGS="--single-process"` كحل مؤقت |
| النص صغير جداً | `S25_SCALE=1.8 chrome-pc` |
| `/dev/shm` صغير | العلم `--disable-dev-shm-usage` مضبوط أصلاً؛ تأكد من استخدام `chrome-pc` لا `chromium` مباشرة |

معلومات الرسوميات الحقيقية: افتح `chrome://gpu` داخل كروم.

---

## Claude PC لا يفتح

```bash
claude-pc 2>&1 | tail -30
```

- **`غلاف Claude PC غير مثبت`**:
  ```bash
  sudo bash /opt/s25/src/install-claude-desktop.sh --mode wrapper
  ```
- **فشل تنزيل Electron** (حجب/بطء):
  ```bash
  export ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
  sudo -E bash /opt/s25/src/install-claude-desktop.sh --mode wrapper
  ```
  أو ثبّت نسخة محددة: `S25_ELECTRON_VERSION=33.4.11`
- **فشل حزمة المجتمع**: طبيعي إن غيّرت Anthropic ملفات المُثبّت — استخدم
  `--mode wrapper`، والوظائف الأساسية (المحادثة، المشاريع، الملفات) تعمل.
- **تسجيل الدخول بجوجل لا يكتمل**: الغلاف يعرّف نفسه كـ Chrome على لينكس؛ إن
  رفضت جوجل النافذة، سجّل بالبريد وكلمة المرور أو برابط تسجيل الدخول من البريد.
- **الشاشة بيضاء**: `S25_GPU=off claude-pc` للتأكد إن كانت المشكلة من الـ GPU.

---

## لا يوجد صوت

```bash
# في Termux
pulseaudio -k
pulseaudio --start --exit-idle-time=-1 \
  --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1"
# داخل الحاوية
pactl info
```

يجب أن يكون `PULSE_SERVER=tcp:127.0.0.1:4713`.

---

## اللمس/الماوس لا يعمل بشكل صحيح

من قائمة تطبيق Termux:X11 (اسحب من الحافة أو زر القائمة):
- بدّل بين **Touchscreen** و **Trackpad**
- فعّل **Show additional keys** للحصول على `Ctrl`/`Alt`/`Esc`
- إن كانت الأبعاد غير مناسبة، غيّر **Display resolution mode** إلى `Native` أو `Scaled`

---

## بطء عام

1. تأكد أن `s25-doctor` يظهر `turnip` لا `software`.
2. أوقف التركيب في XFCE (مضبوط افتراضياً): `Settings ▸ Window Manager Tweaks ▸ Compositor`.
3. استخدم وضع التطبيق الواحد بدل سطح المكتب: `s25-desktop claude` / `s25-desktop chrome`.
4. أوقف حفظ الجلسة في XFCE: `Settings ▸ Session and Startup ▸ Save session on logout` = مُعطّل.
5. `s25-stop` بين الجلسات لتحرير الذاكرة.

---

## مساحة القرص

```bash
s25-desktop shell
df -h /
du -sh /opt/s25/* 2>/dev/null
sudo rm -rf /opt/s25/build          # مصادر البناء المؤقتة
sudo apt-get clean
```

---

## ملفات ويندوز (.exe) لا تعمل

طبقة ويندوز لها دليلها الخاص بمشاكلها وحلولها:
[WINDOWS.md](WINDOWS.md) — تشخيص Wine و box64 و DXVK.

---

## البدء من الصفر

```bash
s25-stop
proot-distro remove debian
bash s25-desktop/install.sh --mesa-tarball <حزمة جاهزة>
```
