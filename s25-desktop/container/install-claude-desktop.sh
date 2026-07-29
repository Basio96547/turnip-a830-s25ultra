#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  install-claude-desktop.sh — Claude كتطبيق سطح مكتب على الجوال
#
#  الوضع الحقيقي (بصراحة): Anthropic تصدر تطبيق Claude Desktop لـ macOS و
#  Windows فقط — لا يوجد إصدار رسمي لـ Linux (ولا لـ arm64). لذلك هناك
#  مسارَان، وكلاهما يعطي «تطبيقاً» حقيقياً بنافذته وأيقونته لا صفحة متصفح:
#
#   1. community : حزمة Claude Desktop من مشروع claude-desktop-debian
#                  (تعيد تغليف ملفات النسخة الرسمية في تطبيق Electron لـ Linux،
#                   وتدعم arm64 وتدعم MCP). تحتاج إنترنت وقد تتعطل عند تحديث
#                   الملفات الأصلية.
#   2. wrapper   : تطبيق Electron محلي (في /opt/s25/claude-pc) يفتح claude.ai
#                  في نافذة تطبيق مستقلة: بدون شريط عنوان متصفح، أيقونة خاصة،
#                  اختصارات لوحة مفاتيح، جلسة دخول محفوظة، وضع ملء الشاشة.
#
#  الافتراضي auto: نحاول (1) ثم نسقط إلى (2). كما يُثبَّت Claude Code CLI
#  (أداة Anthropic الرسمية للطرفية — تعمل على Linux/arm64 بشكل كامل).
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

MODE="auto"
WITH_CLI=1
S25_USER="${S25_USER:-s25}"
WRAPPER_DIR=/opt/s25/claude-pc

while [ $# -gt 0 ]; do
    case "$1" in
        --mode)   MODE="${2:?}"; shift 2 ;;
        --no-cli) WITH_CLI=0; shift ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) die "خيار غير معروف: $1" ;;
    esac
done
case "$MODE" in auto|community|wrapper) ;; *) die "--mode: auto|community|wrapper" ;; esac

S25_HOME="$(getent passwd "$S25_USER" | cut -d: -f6)"
S25_HOME="${S25_HOME:-/home/$S25_USER}"

# ── Node.js ────────────────────────────────────────────────────────────
ensure_node() {
    local ver=0
    if have node; then ver="$(node -v 2>/dev/null | sed 's/^v//')"; fi
    if version_ge "$ver" "20.0.0"; then
        ok "Node.js $ver"
        return 0
    fi
    step "تثبيت Node.js 22"
    apt_refresh
    apt_install curl ca-certificates gnupg
    if retry 3 bash -c 'curl -fsSL https://deb.nodesource.com/setup_22.x | bash -' >/dev/null 2>&1 \
       && apt_install nodejs; then
        ok "Node.js $(node -v)"
    else
        warn "فشل مستودع NodeSource — استخدام حزمة التوزيعة"
        apt_install_soft nodejs npm
        have node || die "تعذر تثبيت Node.js"
        ok "Node.js $(node -v)"
    fi
}

# ── (1) حزمة المجتمع ───────────────────────────────────────────────────
install_community() {
    step "محاولة بناء حزمة Claude Desktop (بناء المجتمع)"
    apt_refresh
    apt_install git p7zip-full wget imagemagick file
    apt_install_soft icoutils nodejs npm dpkg-dev fakeroot
    ensure_node

    local dir=/opt/s25/build/claude-desktop-debian
    rm -rf "$dir"
    mkdir -p "$(dirname "$dir")"
    retry 3 git clone --depth 1 https://github.com/aaddrick/claude-desktop-debian.git "$dir" \
        || { warn "تعذر تنزيل مشروع البناء"; return 1; }

    chown -R "$S25_USER:$S25_USER" "$dir"
    # سكربت البناء يرفض العمل كـ root ويستخدم sudo داخلياً
    if ! su - "$S25_USER" -c "cd '$dir' && bash ./build.sh --build deb --clean yes" ; then
        warn "فشل سكربت بناء حزمة المجتمع"
        return 1
    fi

    local deb
    deb="$(find "$dir" -maxdepth 2 -name 'claude-desktop_*.deb' | head -1)"
    [ -n "$deb" ] || { warn "لم يتم إنتاج ملف .deb"; return 1; }
    apt-get install -y -qq "$deb" || { warn "فشل تثبيت $deb"; return 1; }
    have claude-desktop || { warn "الحزمة مثبتة لكن الأمر claude-desktop غير موجود"; return 1; }
    ok "Claude Desktop (حزمة المجتمع) مثبت: $(command -v claude-desktop)"
    rm -rf "$dir"
    return 0
}

# ── (2) غلاف Electron المحلي ───────────────────────────────────────────
install_wrapper() {
    step "تثبيت تطبيق Claude PC (غلاف Electron محلي)"
    ensure_node
    have npm || apt_install_soft npm
    have npm || die "npm غير متوفر"

    install -d "$WRAPPER_DIR"
    install -m644 "$SRC_DIR/claude-pc-app/package.json" "$WRAPPER_DIR/package.json"
    install -m644 "$SRC_DIR/claude-pc-app/main.js"      "$WRAPPER_DIR/main.js"
    install -m644 "$SRC_DIR/claude-pc-app/preload.js"   "$WRAPPER_DIR/preload.js"

    export npm_config_fund=false npm_config_audit=false npm_config_update_notifier=false
    export ELECTRON_CACHE="/opt/s25/build/electron-cache"
    mkdir -p "$ELECTRON_CACHE"

    log "تنزيل Electron لـ linux-arm64 (~120 ميغابايت)…"
    local rc=0
    if [ -n "${S25_ELECTRON_VERSION:-}" ]; then
        ( cd "$WRAPPER_DIR" && retry 3 npm install --omit=dev "electron@$S25_ELECTRON_VERSION" ) || rc=1
    else
        ( cd "$WRAPPER_DIR" && retry 3 npm install --omit=dev ) || rc=1
    fi
    if [ "$rc" != 0 ] || [ ! -f "$WRAPPER_DIR/node_modules/electron/cli.js" ]; then
        warn "فشل تنزيل Electron.
  إن كان التنزيل محجوباً جرّب مرآة:
    export ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/
    sudo -E bash /opt/s25/src/install-claude-desktop.sh --mode wrapper"
        return 1
    fi

    chown -R "$S25_USER:$S25_USER" "$WRAPPER_DIR" 2>/dev/null || true
    ok "تطبيق Claude PC جاهز في $WRAPPER_DIR"
    return 0
}

# ── (3) Claude Code CLI (رسمي من Anthropic) ────────────────────────────
install_cli() {
    step "تثبيت Claude Code CLI"
    ensure_node
    have npm || return 1
    if retry 3 npm install -g @anthropic-ai/claude-code >/dev/null 2>&1; then
        ok "claude (Claude Code CLI) — شغّله من الطرفية بكتابة: claude"
    else
        warn "فشل تثبيت Claude Code CLI (يمكن تثبيته لاحقاً: npm i -g @anthropic-ai/claude-code)"
    fi
}

# ── مدخل قائمة التطبيقات ───────────────────────────────────────────────
install_desktop_entry() {
    cat > /usr/share/applications/claude-pc.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Claude PC
GenericName=Claude Desktop
Comment=تطبيق Claude لسطح المكتب
Exec=/opt/s25/bin/claude-pc %U
Icon=claude-pc
Terminal=false
StartupNotify=true
StartupWMClass=Claude
Categories=Network;Development;Utility;
Keywords=claude;ai;anthropic;
EOF
    cat > /usr/share/applications/claude-code.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Claude Code (طرفية)
Comment=Claude Code CLI داخل طرفية
Exec=xfce4-terminal --title="Claude Code" -e "bash -lc 'claude; exec bash'"
Icon=utilities-terminal
Terminal=false
Categories=Development;
EOF
    update-desktop-database >/dev/null 2>&1 || true

    if [ -d "$S25_HOME" ]; then
        install -d -o "$S25_USER" -g "$S25_USER" "$S25_HOME/Desktop"
        install -m755 -o "$S25_USER" -g "$S25_USER" \
            /usr/share/applications/claude-pc.desktop "$S25_HOME/Desktop/claude-pc.desktop"
    fi
}

# ── التنفيذ ────────────────────────────────────────────────────────────
INSTALLED=""
case "$MODE" in
    community)
        install_community && INSTALLED="حزمة المجتمع" || die "فشل تثبيت حزمة المجتمع (جرّب --mode wrapper)"
        ;;
    wrapper)
        install_wrapper && INSTALLED="غلاف Electron" || die "فشل تثبيت غلاف Electron"
        ;;
    auto)
        if install_community; then
            INSTALLED="حزمة المجتمع"
            # الغلاف كخطة بديلة إن تعطلت الحزمة بعد تحديث
            install_wrapper && INSTALLED="$INSTALLED + غلاف Electron احتياطي" || true
        elif install_wrapper; then
            INSTALLED="غلاف Electron"
        else
            warn "لم يُثبّت أي تطبيق سطح مكتب لـ Claude — سيبقى الوصول عبر كروم و Claude Code CLI"
        fi
        ;;
esac

install_desktop_entry
[ "$WITH_CLI" = 1 ] && install_cli || true

printf '\n'
if [ -n "$INSTALLED" ]; then
    ok "Claude PC مثبت ($INSTALLED)"
    printf '  التشغيل: claude-pc        (أو من Termux: s25-desktop claude)\n'
else
    warn "Claude PC غير مثبت — راجع docs/TROUBLESHOOTING.md"
fi
printf '  الطرفية: claude           (Claude Code CLI)\n\n'
