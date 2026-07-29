#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  install-windows-layer.sh — طبقة ويندوز على الجوال (Wine + box64 + DXVK)
#
#  الهدف: تشغيل ملفات .exe الحقيقية — Claude Desktop لويندوز وGoogle Chrome
#  لويندوز — داخل الحاوية على الجوال، مع تسريع الرسوميات عبر Turnip/Vulkan.
#
#  كيف تعمل السلسلة:
#     برنامج ويندوز (x86_64 .exe)
#         └─ Wine        : يوفّر واجهات ويندوز (بدون محاكاة نظام كامل)
#             └─ box64   : يترجم تعليمات x86_64 إلى arm64 لحظياً
#                 └─ DXVK: يحوّل Direct3D إلى Vulkan
#                     └─ Turnip: تعريف Adreno 830 (من هذا المستودع)
#
#  ⚠️ توقعات واقعية: هذه السلسلة تشغّل كثيراً من برامج ويندوز، لكن برامج
#  Chromium/Electron (وClaude Desktop وChrome منها بالذات) هي أصعب حالة على
#  Wine: تحتاج تعطيل الحماية (--no-sandbox) وأداؤها أبطأ بكثير من النسخة
#  الأصلية. المسار الأصلي (claude-pc / chrome-pc) يبقى الأسرع والأكثر ثباتاً.
#
#  الاستخدام (داخل الحاوية كـ root):
#     bash /opt/s25/src/install-windows-layer.sh [خيارات]
#       --wine-url <url>     تحديد بناء Wine (افتراضي: أحدث بناء amd64)
#       --dxvk-url <url>     تحديد إصدار DXVK
#       --no-dxvk            بدون DXVK (استخدام WineD3D فوق OpenGL/Zink)
#       --prefix-only        إعادة إنشاء بيئة ويندوز فقط
# ═══════════════════════════════════════════════════════════════════════

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -r "$SRC_DIR/lib/common.sh" ]; then
    # shellcheck source=/dev/null
    . "$SRC_DIR/lib/common.sh"
else
    # shellcheck source=../lib/common.sh
    . "$SRC_DIR/../lib/common.sh"
fi
# shellcheck source=lib-multiarch.sh
. "$SRC_DIR/lib-multiarch.sh"

need_root
export DEBIAN_FRONTEND=noninteractive

WIN_ROOT=/opt/s25/windows
WINE_DIR="$WIN_ROOT/wine"
WINEPREFIX_DIR="$WIN_ROOT/prefix"
DL_DIR="$WIN_ROOT/downloads"
WINE_URL=""
DXVK_URL=""
WITH_DXVK=1
PREFIX_ONLY=0
S25_USER="${S25_USER:-s25}"

WINE_FALLBACK_URL="https://github.com/Kron4ek/Wine-Builds/releases/download/9.0/wine-9.0-amd64.tar.xz"

while [ $# -gt 0 ]; do
    case "$1" in
        --wine-url)    WINE_URL="${2:?}"; shift 2 ;;
        --dxvk-url)    DXVK_URL="${2:?}"; shift 2 ;;
        --no-dxvk)     WITH_DXVK=0; shift ;;
        --prefix-only) PREFIX_ONLY=1; shift ;;
        -h|--help)     sed -n '2,32p' "$0"; exit 0 ;;
        *) die "خيار غير معروف: $1" ;;
    esac
done

S25_HOME="$(getent passwd "$S25_USER" | cut -d: -f6)"
S25_HOME="${S25_HOME:-/home/$S25_USER}"

# ── دالة: أحدث أصل تنزيل من إصدارات GitHub ─────────────────────────────
latest_asset() { # latest_asset <owner/repo> <نمط grep>
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
        | grep -oE "https://[^\"]*$2" | head -1
}

if [ "$PREFIX_ONLY" = 0 ]; then
    step "1/6 box64 (ترجمة تعليمات x86_64)"
    apt_refresh
    install_box64 || die "فشل تثبيت box64 — بدونه لا يمكن تشغيل برامج x86_64"

    step "2/6 مكتبات x86_64 داخل الحاوية"
    enable_amd64_multiarch
    install_amd64_runtime_libs
    ok "مكتبات amd64 جاهزة"

    step "3/6 تنزيل Wine (بناء x86_64)"
    mkdir -p "$DL_DIR"
    if [ -z "$WINE_URL" ]; then
        WINE_URL="$(latest_asset Kron4ek/Wine-Builds '\-amd64\.tar\.xz' || true)"
        [ -n "$WINE_URL" ] || WINE_URL="$WINE_FALLBACK_URL"
    fi
    log "المصدر: $WINE_URL"
    apt_install xz-utils tar curl
    WINE_TAR="$DL_DIR/$(basename "$WINE_URL")"
    if [ ! -s "$WINE_TAR" ]; then
        retry 4 curl -fL "$WINE_URL" -o "$WINE_TAR" || die "فشل تنزيل Wine"
    fi
    rm -rf "$WINE_DIR"
    mkdir -p "$WINE_DIR"
    tar -xf "$WINE_TAR" -C "$WINE_DIR" --strip-components=1
    [ -x "$WINE_DIR/bin/wine64" ] || [ -x "$WINE_DIR/bin/wine" ] \
        || die "بناء Wine لا يحتوي bin/wine"
    ok "Wine في $WINE_DIR ($(du -sh "$WINE_DIR" | cut -f1))"
fi

# ── ملف بيئة طبقة ويندوز ───────────────────────────────────────────────
step "4/6 كتابة إعدادات البيئة"
install -d /opt/s25/etc
cat > /opt/s25/etc/windows.sh <<'EOF'
# shellcheck shell=sh
# /opt/s25/etc/windows.sh — بيئة طبقة ويندوز (Wine + box64 + DXVK)
S25_WIN_ROOT=/opt/s25/windows
export WINEPREFIX="${WINEPREFIX:-$S25_WIN_ROOT/prefix}"
export WINEARCH="${WINEARCH:-win64}"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLPATH="$S25_WIN_ROOT/wine/lib/wine"

if [ -x "$S25_WIN_ROOT/wine/bin/wine64" ]; then
    S25_WINE="$S25_WIN_ROOT/wine/bin/wine64"
else
    S25_WINE="$S25_WIN_ROOT/wine/bin/wine"
fi
export S25_WINE

# box64: أين يجد مكتبات x86_64
export BOX64_LD_LIBRARY_PATH="$S25_WIN_ROOT/wine/lib:$S25_WIN_ROOT/wine/lib64:/usr/lib/x86_64-linux-gnu:/lib/x86_64-linux-gnu"
export BOX64_NOBANNER="${BOX64_NOBANNER:-1}"
# Wine يعتمد على إشارات ومقاطع ذاكرة خاصة — هذه القيم هي الموصى بها لتشغيله
export BOX64_DYNAREC_STRONGMEM="${BOX64_DYNAREC_STRONGMEM:-1}"
export BOX64_DYNAREC_BIGBLOCK="${BOX64_DYNAREC_BIGBLOCK:-1}"
export BOX64_DYNAREC_SAFEFLAGS="${BOX64_DYNAREC_SAFEFLAGS:-2}"

# DXVK إن كان مثبتاً في البيئة
if [ -f "$WINEPREFIX/.s25-dxvk" ]; then
    export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d11,d3d10core,dxgi,d3d9=n}"
    export DXVK_HUD="${DXVK_HUD:-0}"
    export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-none}"
fi
EOF
chmod 644 /opt/s25/etc/windows.sh
ok "/opt/s25/etc/windows.sh"

# ── إنشاء بيئة ويندوز (wineprefix) ─────────────────────────────────────
step "5/6 إنشاء بيئة ويندوز (wineprefix)"
# shellcheck source=/dev/null
. /opt/s25/etc/env.sh
# shellcheck source=/dev/null
. /opt/s25/etc/windows.sh

install -d -o "$S25_USER" -g "$S25_USER" "$WIN_ROOT" "$WINEPREFIX_DIR" "$DL_DIR"
chown -R "$S25_USER:$S25_USER" "$WIN_ROOT"

if [ -d "$WINEPREFIX_DIR/drive_c" ] && [ "$PREFIX_ONLY" = 0 ]; then
    ok "بيئة ويندوز موجودة مسبقاً (استخدم --prefix-only لإعادة إنشائها)"
else
    [ "$PREFIX_ONLY" = 1 ] && rm -rf "$WINEPREFIX_DIR"
    install -d -o "$S25_USER" -g "$S25_USER" "$WINEPREFIX_DIR"
    log "تهيئة أولية (wineboot) — قد تأخذ عدة دقائق على الجوال…"
    if su - "$S25_USER" -c "cd /tmp && . /opt/s25/etc/env.sh && . /opt/s25/etc/windows.sh && \
        DISPLAY= box64 \"\$S25_WINE\" wineboot -u" >/tmp/wineboot.log 2>&1; then
        ok "تم إنشاء بيئة ويندوز في $WINEPREFIX_DIR"
    else
        warn "wineboot أبلغ عن أخطاء — آخر الأسطر:"
        tail -12 /tmp/wineboot.log | sed 's/^/    /'
        warn "قد تبقى البيئة صالحة؛ تابع واختبر بـ win-run winecfg"
    fi
fi

# ── DXVK ───────────────────────────────────────────────────────────────
step "6/6 DXVK (Direct3D فوق Vulkan)"
if [ "$WITH_DXVK" = 0 ]; then
    warn "تم تخطي DXVK بناءً على الطلب — سيُستخدم WineD3D فوق OpenGL/Zink"
    rm -f "$WINEPREFIX_DIR/.s25-dxvk"
else
    if [ -z "$DXVK_URL" ]; then
        DXVK_URL="$(latest_asset doitsujin/dxvk 'dxvk-[0-9.]*\.tar\.gz' || true)"
    fi
    if [ -z "$DXVK_URL" ]; then
        warn "لم يتم العثور على إصدار DXVK — سيعمل النظام بـ WineD3D"
    else
        log "المصدر: $DXVK_URL"
        DXVK_TAR="$DL_DIR/$(basename "$DXVK_URL")"
        if [ ! -s "$DXVK_TAR" ]; then
            retry 4 curl -fL "$DXVK_URL" -o "$DXVK_TAR" || warn "فشل تنزيل DXVK"
        fi
        if [ -s "$DXVK_TAR" ]; then
            rm -rf "$DL_DIR/dxvk-extract"
            mkdir -p "$DL_DIR/dxvk-extract"
            tar -xzf "$DXVK_TAR" -C "$DL_DIR/dxvk-extract" --strip-components=1
            SYS32="$WINEPREFIX_DIR/drive_c/windows/system32"
            if [ -d "$SYS32" ] && [ -d "$DL_DIR/dxvk-extract/x64" ]; then
                cp -f "$DL_DIR/dxvk-extract/x64/"*.dll "$SYS32/"
                touch "$WINEPREFIX_DIR/.s25-dxvk"
                chown "$S25_USER:$S25_USER" "$WINEPREFIX_DIR/.s25-dxvk"
                ok "DXVK مُثبَّت في بيئة ويندوز"
            else
                warn "لم يتم العثور على system32 أو ملفات x64 — تخطي DXVK"
            fi
        fi
    fi
fi

chown -R "$S25_USER:$S25_USER" "$WIN_ROOT" 2>/dev/null || true

printf '\n'
ok "طبقة ويندوز جاهزة"
cat <<'EOF'
  الأوامر:
    win-run <ملف.exe> [وسائط]   تشغيل أي برنامج ويندوز
    win-run winecfg              إعدادات Wine (للتحقق أن الطبقة تعمل)
    claude-pc-win                تنزيل/تشغيل Claude Desktop لويندوز
    chrome-pc-win                تنزيل/تشغيل Google Chrome لويندوز

  من Termux مباشرة:
    s25-desktop win-claude
    s25-desktop win-chrome

EOF
