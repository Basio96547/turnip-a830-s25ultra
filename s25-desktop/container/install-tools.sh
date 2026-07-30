#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  install-tools.sh — تثبيت أدوات النظام من /opt/s25/src إلى /opt/s25
#
#  فُصل عن bootstrap-debian.sh لسبب عملي: s25-update كان ينسخ المصادر إلى
#  /opt/s25/src فقط، فتبقى الأدوات العاملة في /opt/s25/bin و /opt/s25/etc
#  على نسخها القديمة بعد كل تحديث — وهذا يجعل الإصلاحات لا تصل للمستخدم.
#  الآن يستدعي s25-update هذا السكربت، ويستدعيه bootstrap في خطوته الخامسة.
# ═══════════════════════════════════════════════════════════════════════

SRC_DIR="${SRC_DIR:-/opt/s25/src}"
if [ -r "$SRC_DIR/lib/common.sh" ]; then
    # shellcheck source=/dev/null
    . "$SRC_DIR/lib/common.sh"
else
    # shellcheck source=../lib/common.sh
    . "$SRC_DIR/../lib/common.sh"
fi
trap_errors

need_root

S25_USER="${S25_USER:-s25}"
S25_HOME="$(getent passwd "$S25_USER" 2>/dev/null | cut -d: -f6)"
S25_HOME="${S25_HOME:-/home/$S25_USER}"

step "تثبيت أدوات النظام في /opt/s25"
install -d /opt/s25/bin /opt/s25/etc /opt/s25/share
for f in "$SRC_DIR/bin/"*; do
    [ -f "$f" ] || continue
    install -m755 "$f" "/opt/s25/bin/$(basename "$f")"
done
install -m644 "$SRC_DIR/etc/env.sh" /opt/s25/etc/env.sh
if [ -r "$SRC_DIR/.version" ]; then
    install -m644 "$SRC_DIR/.version" /opt/s25/etc/version
fi
install -m644 "$SRC_DIR/etc/profile.d-s25.sh" /etc/profile.d/10-s25-desktop.sh
if [ -f "$SRC_DIR/share/claude-pc.svg" ]; then
    install -Dm644 "$SRC_DIR/share/claude-pc.svg" \
        /usr/share/icons/hicolor/scalable/apps/claude-pc.svg
fi
for b in s25-session s25-app s25-doctor win-run claude-pc-win chrome-pc-win; do
    ln -sf "/opt/s25/bin/$b" "/usr/local/bin/$b"
done

# مدخلات قائمة التطبيقات لبرامج ويندوز
cat > /usr/share/applications/claude-pc-win.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Claude Desktop (ويندوز)
Name[en]=Claude Desktop (Windows)
Comment=نسخة ويندوز الرسمية عبر Wine + box64
Exec=/opt/s25/bin/claude-pc-win
Icon=claude-pc
Terminal=false
StartupNotify=true
Categories=Network;Development;Utility;
EOF
cat > /usr/share/applications/chrome-pc-win.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Google Chrome (ويندوز)
Name[en]=Google Chrome (Windows)
Comment=نسخة ويندوز الرسمية عبر Wine + box64 + DXVK
Exec=/opt/s25/bin/chrome-pc-win %U
Icon=web-browser
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
EOF
cat > /usr/share/applications/winecfg-s25.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=إعدادات ويندوز (winecfg)
Name[en]=Windows settings (winecfg)
Exec=/opt/s25/bin/win-run winecfg
Icon=preferences-system
Terminal=false
Categories=Settings;
EOF
update-desktop-database >/dev/null 2>&1 || true

if [ -d "$S25_HOME" ]; then
    install -d -o "$S25_USER" -g "$S25_USER" "$S25_HOME/Desktop"
    for d in claude-pc-win chrome-pc-win; do
        install -m755 -o "$S25_USER" -g "$S25_USER" \
            "/usr/share/applications/$d.desktop" "$S25_HOME/Desktop/$d.desktop"
    done
fi
ok "الأوامر: s25-doctor · win-run · claude-pc-win · chrome-pc-win"
