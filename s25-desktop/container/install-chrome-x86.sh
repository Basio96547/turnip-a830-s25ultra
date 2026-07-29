#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  install-chrome-x86.sh — Google Chrome الرسمي (amd64) عبر box64  ⚠ تجريبي
#
#  اقرأ هذا أولاً:
#   • Google لا تصدر Chrome لـ Linux/arm64، لذلك الطريقة الوحيدة لتشغيل
#     «Chrome الرسمي» هي ترجمة تعليمات x86_64 لحظياً عبر box64.
#   • النتيجة أبطأ بمراحل من Chromium الأصلي (chrome-pc)، وبدون تسريع GPU،
#     وقد لا يعمل إطلاقاً بعد تحديثات Chrome. استخدمه فقط إن كنت مضطراً.
#   • الحجم: ~1.5 غيغابايت (مكتبات amd64 + Chrome).
#
#  الاستخدام: sudo bash /opt/s25/src/install-chrome-x86.sh
#  التشغيل  : chrome-x86
# ═══════════════════════════════════════════════════════════════════════

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$SRC_DIR/lib/common.sh" ]; then
    # shellcheck source=/dev/null
    . "$SRC_DIR/lib/common.sh"
else
    # shellcheck source=../lib/common.sh
    . "$SRC_DIR/../lib/common.sh"
fi

need_root
export DEBIAN_FRONTEND=noninteractive
TARGET=/opt/s25/chrome-x86

warn "هذا المسار تجريبي وبطيء — الموصى به هو chrome-pc (Chromium أصلي)"
confirm "المتابعة بتثبيت Chrome amd64 عبر box64؟" || { log "تم الإلغاء"; exit 0; }

# ── 1. box64 ───────────────────────────────────────────────────────────
step "1/4 تثبيت box64"
apt_refresh
apt_install curl ca-certificates gnupg wget

if have box64; then
    ok "box64 مثبت مسبقاً: $(box64 --version 2>&1 | head -1)"
else
    if apt_available box64; then
        apt_install box64
    else
        log "إضافة مستودع box64…"
        curl -fsSL https://ryanfortner.github.io/box64-debs/KEY.gpg \
            | gpg --dearmor -o /usr/share/keyrings/box64-archive-keyring.gpg 2>/dev/null || \
            warn "تعذر تنزيل مفتاح المستودع"
        printf 'deb [signed-by=/usr/share/keyrings/box64-archive-keyring.gpg] https://ryanfortner.github.io/box64-debs/debian ./\n' \
            > /etc/apt/sources.list.d/box64.list
        apt_refresh
        apt_install_any box64-generic-arm box64
    fi
    have box64 || die "فشل تثبيت box64"
    ok "box64 جاهز"
fi

# ── 2. مكتبات amd64 ────────────────────────────────────────────────────
step "2/4 إضافة معمارية amd64 ومكتباتها"
dpkg --add-architecture amd64
CODENAME="$( (. /etc/os-release && echo "${VERSION_CODENAME:-}") 2>/dev/null || true)"
CODENAME="${CODENAME:-trixie}"

# نحصر المستودعات الأصلية على arm64 ثم نضيف مستودع amd64
if [ -f /etc/apt/sources.list.d/debian.sources ]; then
    grep -q '^Architectures:' /etc/apt/sources.list.d/debian.sources || \
        sed -i 's/^Components:/Architectures: arm64\nComponents:/' /etc/apt/sources.list.d/debian.sources
fi
if [ -f /etc/apt/sources.list ] && grep -q '^deb ' /etc/apt/sources.list; then
    sed -i 's|^deb \(http\)|deb [arch=arm64] \1|' /etc/apt/sources.list
fi
cat > /etc/apt/sources.list.d/amd64.sources <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: $CODENAME
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
apt_refresh

apt_install_soft libc6:amd64 libstdc++6:amd64 libgcc-s1:amd64 \
    libglib2.0-0:amd64 libnss3:amd64 libnspr4:amd64 libx11-6:amd64 \
    libxcomposite1:amd64 libxdamage1:amd64 libxext6:amd64 libxfixes3:amd64 \
    libxrandr2:amd64 libxkbcommon0:amd64 libdrm2:amd64 libgbm1:amd64 \
    libexpat1:amd64 libxcb1:amd64 libasound2:amd64 libatk1.0-0:amd64 \
    libatk-bridge2.0-0:amd64 libcups2:amd64 libpango-1.0-0:amd64 \
    libpangocairo-1.0-0:amd64 libcairo2:amd64 libatspi2.0-0:amd64 \
    libgtk-3-0:amd64 libxss1:amd64 libudev1:amd64
ok "مكتبات amd64 مثبتة"

# ── 3. Chrome ──────────────────────────────────────────────────────────
step "3/4 تنزيل Google Chrome (amd64)"
DEB=/tmp/google-chrome-amd64.deb
retry 4 curl -fL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o "$DEB" \
    || die "فشل تنزيل Chrome"
rm -rf "$TARGET"
mkdir -p "$TARGET"
# نستخرج الحزمة فقط (بدون dpkg) لتجنّب تعارض المعماريات
dpkg-deb -x "$DEB" "$TARGET"
rm -f "$DEB"
CHROME_BIN="$TARGET/opt/google/chrome/chrome"
[ -x "$CHROME_BIN" ] || die "لم يتم العثور على ملف chrome بعد الاستخراج"
ok "Chrome في $TARGET"

# ── 4. المُشغّل ────────────────────────────────────────────────────────
step "4/4 إنشاء المُشغّل chrome-x86"
cat > /opt/s25/bin/chrome-x86 <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Google Chrome amd64 عبر box64 — تجريبي وبطيء (استخدم chrome-pc للأداء)
. /opt/s25/etc/env.sh
export BOX64_LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu:/opt/s25/chrome-x86/opt/google/chrome"
export BOX64_NOBANNER="${BOX64_NOBANNER:-1}"
exec box64 /opt/s25/chrome-x86/opt/google/chrome/chrome \
    --no-sandbox --disable-gpu --disable-dev-shm-usage \
    --ozone-platform=x11 --password-store=basic \
    --user-data-dir="$HOME/.config/chrome-x86" \
    --force-device-scale-factor="${S25_SCALE:-1.4}" "$@"
EOF
chmod +x /opt/s25/bin/chrome-x86
ln -sf /opt/s25/bin/chrome-x86 /usr/local/bin/chrome-x86

cat > /usr/share/applications/s25-chrome-x86.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Google Chrome (x86 · تجريبي)
Comment=Chrome الرسمي amd64 عبر box64 — بطيء
Exec=/opt/s25/bin/chrome-x86 %U
Icon=chromium
Terminal=false
Categories=Network;WebBrowser;
EOF
update-desktop-database >/dev/null 2>&1 || true

ok "شغّله بـ: chrome-x86   (وتوقّع بطئاً ملحوظاً)"
