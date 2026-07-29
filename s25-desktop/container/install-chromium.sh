#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  install-chromium.sh — كروم سطح المكتب (Chromium arm64) داخل الحاوية
#
#  لماذا Chromium وليس Google Chrome؟
#  Google لا تصدر Chrome لـ Linux/arm64 — تصدره لـ amd64 فقط. Chromium هو
#  نفس المحرك ونفس واجهة سطح المكتب ويعمل أصلاً (native) على معالج الجهاز،
#  أي أسرع بمراحل من محاكاة x86_64. لمن يريد Chrome الرسمي بأي حال:
#  استخدم chrome-pc-win (نسخة ويندوز عبر Wine — تجريبي وأبطأ بكثير).
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
S25_USER="${S25_USER:-s25}"

step "تثبيت Chromium"
apt_refresh

BIN=""
if apt_available chromium; then
    apt_install chromium
    apt_install_soft chromium-l10n chromium-sandbox
    BIN="chromium"
elif apt_available chromium-browser; then
    apt_install chromium-browser
    BIN="chromium-browser"
else
    err "لا توجد حزمة chromium في مستودعات هذه التوزيعة."
    cat <<'EOF'
  الحلول:
    • استخدم توزيعة debian للحاوية (فيها chromium لـ arm64):
        proot-distro install debian
    • أو ثبّت متصفحاً آخر يدوياً وحدّد مساره:
        export S25_CHROME_BIN=/path/to/browser
EOF
    exit 1
fi
ok "$BIN $(dpkg-query -W -f='${Version}' "$BIN" 2>/dev/null || echo '')"

# ── مدخل قائمة التطبيقات ───────────────────────────────────────────────
step "إضافة أيقونة «كروم سطح المكتب»"
cat > /usr/share/applications/s25-chrome.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Chrome (سطح المكتب)
Name[en]=Chrome (Desktop)
GenericName=Web Browser
Comment=متصفح سطح المكتب الكامل بتسريع Turnip
Exec=/opt/s25/bin/chrome-pc %U
Icon=chromium
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
Keywords=chrome;chromium;browser;متصفح;
EOF
update-desktop-database >/dev/null 2>&1 || true

S25_HOME="$(getent passwd "$S25_USER" | cut -d: -f6)"
S25_HOME="${S25_HOME:-/home/$S25_USER}"
if [ -d "$S25_HOME" ]; then
    install -d -o "$S25_USER" -g "$S25_USER" "$S25_HOME/Desktop"
    install -m755 -o "$S25_USER" -g "$S25_USER" \
        /usr/share/applications/s25-chrome.desktop "$S25_HOME/Desktop/s25-chrome.desktop"
fi

# المتصفح الافتراضي للنظام (يستخدمه xdg-open وتطبيق Claude PC للروابط الخارجية)
if have update-alternatives; then
    update-alternatives --install /usr/bin/x-www-browser x-www-browser /opt/s25/bin/chrome-pc 200 >/dev/null 2>&1 || true
    update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser /opt/s25/bin/chrome-pc 200 >/dev/null 2>&1 || true
fi

ok "شغّله بـ: chrome-pc   (أو: s25-desktop chrome من Termux)"
