#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  bootstrap-debian.sh — تهيئة الحاوية: سطح مكتب XFCE + مستخدم + بيئة
#  يُشغّل كـ root داخل الحاوية:
#     proot-distro login debian -- bash /opt/s25/src/bootstrap-debian.sh
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
S25_DPI="${S25_DPI:-140}"

DISTRO_NAME="$( (. /etc/os-release && echo "$PRETTY_NAME") 2>/dev/null || echo "غير معروفة")"
log "التوزيعة داخل الحاوية: $DISTRO_NAME"

step "1/7 تحديث فهرس الحزم"
apt_refresh

step "2/7 سطح مكتب XFCE والأدوات الأساسية"
apt_install xfce4 xfce4-terminal dbus-x11 x11-xserver-utils xauth \
    sudo nano less curl wget ca-certificates gnupg locales \
    xdg-utils desktop-file-utils procps psmisc file
apt_install_soft openbox thunar-archive-plugin xarchiver \
    xfce4-taskmanager xfce4-screenshooter mousepad \
    x11-utils mesa-utils vulkan-tools pulseaudio-utils xclip \
    gnome-themes-extra adwaita-icon-theme \
    fonts-noto-core fonts-noto-color-emoji fonts-liberation \
    fonts-kacst fonts-hosny-amiri \
    mesa-vulkan-drivers libgl1-mesa-dri

step "3/7 مكتبات تشغيل Chromium / Electron"
# أسماء الحزم تغيّرت بين bookworm و trixie (لواحق t64) — نجرب البديلين
apt_install_any libgtk-3-0t64 libgtk-3-0
apt_install_any libasound2t64 libasound2
apt_install_any libatk1.0-0t64 libatk1.0-0
apt_install_any libatk-bridge2.0-0t64 libatk-bridge2.0-0
apt_install_any libcups2t64 libcups2
apt_install_soft libnss3 libnspr4 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxrandr2 libxfixes3 libxext6 libxss1 libdrm2 libgbm1 \
    libpangocairo-1.0-0 libcairo2 libexpat1 libsecret-1-0 libudev1 \
    libglib2.0-0 libxshmfence1

step "4/7 اللغات (عربي + إنجليزي)"
if [ -f /etc/locale.gen ]; then
    sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
    sed -i 's/^# *\(ar_SA.UTF-8 UTF-8\)/\1/' /etc/locale.gen
    locale-gen >/dev/null 2>&1 || warn "locale-gen فشل"
fi
update-locale LANG=en_US.UTF-8 >/dev/null 2>&1 || \
    printf 'LANG=en_US.UTF-8\n' > /etc/default/locale
ok "en_US.UTF-8 + ar_SA.UTF-8"

step "5/7 المستخدم $S25_USER"
if id -u "$S25_USER" >/dev/null 2>&1; then
    ok "المستخدم موجود مسبقاً"
else
    useradd -m -s /bin/bash -u 1000 "$S25_USER" 2>/dev/null || useradd -m -s /bin/bash "$S25_USER"
    passwd -d "$S25_USER" >/dev/null 2>&1 || true
    ok "تم إنشاء المستخدم $S25_USER (بدون كلمة مرور)"
fi
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$S25_USER" > /etc/sudoers.d/010-s25
chmod 440 /etc/sudoers.d/010-s25
for grp in audio video plugdev; do
    getent group "$grp" >/dev/null 2>&1 && usermod -aG "$grp" "$S25_USER" || true
done
S25_HOME="$(getent passwd "$S25_USER" | cut -d: -f6)"
S25_HOME="${S25_HOME:-/home/$S25_USER}"

# dbus يحتاج machine-id
[ -s /etc/machine-id ] || dbus-uuidgen > /etc/machine-id 2>/dev/null || true
mkdir -p /var/lib/dbus
[ -s /var/lib/dbus/machine-id ] || cp /etc/machine-id /var/lib/dbus/machine-id 2>/dev/null || true

step "6/7 تثبيت أدوات النظام في /opt/s25"
install -d /opt/s25/bin /opt/s25/etc /opt/s25/share
for f in "$SRC_DIR/bin/"*; do
    [ -f "$f" ] || continue
    install -m755 "$f" "/opt/s25/bin/$(basename "$f")"
done
install -m644 "$SRC_DIR/etc/env.sh" /opt/s25/etc/env.sh
install -m644 "$SRC_DIR/etc/profile.d-s25.sh" /etc/profile.d/10-s25-desktop.sh
if [ -f "$SRC_DIR/share/claude-pc.svg" ]; then
    install -Dm644 "$SRC_DIR/share/claude-pc.svg" \
        /usr/share/icons/hicolor/scalable/apps/claude-pc.svg
fi
for b in s25-session s25-app s25-doctor chrome-pc claude-pc; do
    ln -sf "/opt/s25/bin/$b" "/usr/local/bin/$b"
done
ok "الأوامر: s25-doctor, chrome-pc, claude-pc"

step "7/7 إعدادات سطح المكتب لشاشة S25 Ultra"
XFCONF="$S25_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
install -d -o "$S25_USER" -g "$S25_USER" "$XFCONF" "$S25_HOME/Desktop" "$S25_HOME/.cache"

cat > "$XFCONF/xsettings.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Adwaita-dark"/>
    <property name="IconThemeName" type="string" value="Adwaita"/>
    <property name="DoubleClickTime" type="int" value="400"/>
    <property name="EnableEventSounds" type="bool" value="false"/>
  </property>
  <property name="Xft" type="empty">
    <property name="DPI" type="int" value="$S25_DPI"/>
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="CursorThemeSize" type="int" value="32"/>
    <property name="FontName" type="string" value="Sans 11"/>
    <property name="MonospaceFontName" type="string" value="Monospace 11"/>
  </property>
</channel>
EOF

# إيقاف التركيب (compositing) — مكلف على Zink، وتكبير أزرار النوافذ للمس
cat > "$XFCONF/xfwm4.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="theme" type="string" value="Default"/>
    <property name="title_font" type="string" value="Sans Bold 11"/>
    <property name="workspace_count" type="int" value="2"/>
    <property name="click_to_focus" type="bool" value="true"/>
    <property name="easy_click" type="string" value="Super"/>
    <property name="snap_to_border" type="bool" value="true"/>
    <property name="wrap_windows" type="bool" value="false"/>
  </property>
</channel>
EOF

# لوحة سفلية بسيطة بأيقونات كبيرة تناسب اللمس
cat > "$XFCONF/xfce4-power-manager.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="blank-on-ac" type="int" value="0"/>
    <property name="dpms-enabled" type="bool" value="false"/>
  </property>
</channel>
EOF

chown -R "$S25_USER:$S25_USER" "$S25_HOME/.config" "$S25_HOME/Desktop" "$S25_HOME/.cache"

# بيئة المستخدم: تحميل env.sh حتى في الجلسات غير التفاعلية
BASHRC="$S25_HOME/.bashrc"
if ! grep -q 's25/etc/env.sh' "$BASHRC" 2>/dev/null; then
    printf '\n# S25 Desktop\n[ -r /opt/s25/etc/env.sh ] && . /opt/s25/etc/env.sh\nPATH="/opt/s25/bin:$PATH"\n' >> "$BASHRC"
    chown "$S25_USER:$S25_USER" "$BASHRC"
fi

ok "تمت تهيئة الحاوية"
printf '\n  المستخدم    : %s (بدون كلمة مرور، sudo مسموح)\n' "$S25_USER"
printf '  سطح المكتب  : XFCE (%s)\n' "$(dpkg-query -W -f='${Version}' xfce4-session 2>/dev/null || echo "?")"
printf '  الأوامر     : s25-doctor · chrome-pc · claude-pc\n\n'
