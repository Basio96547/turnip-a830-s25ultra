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
#  Wine: تحتاج تعطيل الحماية (--no-sandbox) وأداؤها أبطأ بكثير من نسخة أصلية.
#  إن تعذّر تشغيل أحدهما فراجع سلّم الحلول في docs/WINDOWS.md.
#
#  الاستخدام (داخل الحاوية كـ root):
#     bash /opt/s25/src/install-windows-layer.sh [خيارات]
#       --wine-url <url>     بناء Wine (افتراضي: أحدث amd64-wow64 — إلزامي لـ 32-بت)
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

# ⚠ يجب أن يكون بناء «amd64-wow64» تحديداً (WoW64 الجديد):
#   • wine-*-amd64.tar.xz        → bin/wine ملف ELF 32-بت، فتشغيل أي برنامج
#                                  ويندوز 32-بت يحتاج box86 (غير مثبت هنا)
#   • wine-*-amd64-wow64.tar.xz  → bin/wine ملف ELF 64-بت ولا يوجد wine64،
#                                  فبرامج 32-بت تعمل عبر مُحمّل 64-بت → box64 يكفي
# وهذا مهم عملياً: مُثبّت Claude لويندوز (Claude-Setup-x64.exe) ملف 32-بت.
# ⚠ لا نأخذ «أحدث» بناء: box64 يحتوي كود توافق خاص بـ Wine، وبناء Wine أحدث
# بكثير من box64 المثبّت يفشل بـ:
#   [BOX64] Warning, Symbol wine_main_preload_info not found
#   wine: could not load kernel32.dll, status c0000135
# لذلك نثبّت نسخة معروفة التوافق، ونجرّب البدائل تلقائياً إن فشلت البيئة.
WINE_URL_DEFAULT="https://github.com/Kron4ek/Wine-Builds/releases/download/10.0/wine-10.0-staging-amd64-wow64.tar.xz"
WINE_URL_ALT1="https://github.com/Kron4ek/Wine-Builds/releases/download/10.0/wine-10.0-amd64-wow64.tar.xz"
WINE_URL_ALT2="https://github.com/Kron4ek/Wine-Builds/releases/download/10.13/wine-10.13-staging-amd64-wow64.tar.xz"
DXVK_FALLBACK_URL="https://github.com/doitsujin/dxvk/releases/download/v2.5.3/dxvk-2.5.3.tar.gz"

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

id -u "$S25_USER" >/dev/null 2>&1 || \
    die "المستخدم $S25_USER غير موجود — شغّل bootstrap-debian.sh أولاً:
    bash /opt/s25/src/bootstrap-debian.sh"
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
fi

# install_wine_build <url> — ينزّل بناء Wine ويفكّه في $WINE_DIR
install_wine_build() {
    local url="$1" tar
    mkdir -p "$DL_DIR"
    tar="$DL_DIR/$(basename "$url")"
    log "المصدر: $url"
    if [ ! -s "$tar" ]; then
        retry 4 curl -fL "$url" -o "$tar" || { warn "فشل تنزيل $url"; return 1; }
    fi
    rm -rf "$WINE_DIR"
    mkdir -p "$WINE_DIR"
    tar -xf "$tar" -C "$WINE_DIR" --strip-components=1 || { warn "فشل فك $tar"; return 1; }
    [ -x "$WINE_DIR/bin/wine" ] || [ -x "$WINE_DIR/bin/wine64" ] || {
        warn "بناء Wine لا يحتوي bin/wine"; return 1; }

    # مُحمّل 32-بت يعني WoW64 القديم — يحتاج box86 غير المدعوم هنا
    if file -L "$WINE_DIR/bin/wine" 2>/dev/null | grep -q 'ELF 32-bit'; then
        warn "بناء WoW64 قديم (bin/wine ملف 32-بت) — برامج 32-بت لن تعمل بلا box86"
    else
        ok "بناء WoW64 الجديد ✓ (برامج 32-بت تعمل عبر box64 وحده)"
    fi
    WINE_TAR="$tar"
    printf '%s' "$(basename "$tar")" > "$WIN_ROOT/.s25-wine-tag"
    ok "Wine في $WINE_DIR ($(du -sh "$WINE_DIR" | cut -f1))"
    return 0
}

if [ "$PREFIX_ONLY" = 0 ] || [ -n "$WINE_URL" ]; then
    step "3/6 تنزيل Wine (بناء amd64-wow64)"
    apt_install xz-utils tar curl file
    [ -n "$WINE_URL" ] || WINE_URL="$WINE_URL_DEFAULT"
    install_wine_build "$WINE_URL" || die "فشل تجهيز Wine"
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
# لا نضبط WINEDLLPATH: Wine الحديث يجد مكتباته من مسار مُحمّله

# بناء amd64-wow64 لا يحتوي wine64 إطلاقاً، و bin/wine فيه 64-بت — وهو المطلوب
if [ -x "$S25_WIN_ROOT/wine/bin/wine" ]; then
    S25_WINE="$S25_WIN_ROOT/wine/bin/wine"
else
    S25_WINE="$S25_WIN_ROOT/wine/bin/wine64"
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

# بيئة ويندوز سليمة تحتوي ~580 مكتبة في system32. الاعتماد على وجود المجلد
# وحده كان خطأً: بيئة من wineboot منقطع تبدو «موجودة» لكن Wine يفشل بـ
#   wine: could not load kernel32.dll, status c0000135
prefix_dll_count() {
    find "$WINEPREFIX_DIR/drive_c/windows/system32" -maxdepth 1 -name '*.dll' 2>/dev/null | wc -l
}

WINE_MARK="$WINEPREFIX_DIR/.s25-wine-build"
WINE_TAG="$(basename "${WINE_TAR:-${WINE_URL:-wine}}")"

need_boot=0
boot_reason=""
if [ "$PREFIX_ONLY" = 1 ]; then
    need_boot=1; boot_reason="طلب إعادة الإنشاء"
elif [ ! -d "$WINEPREFIX_DIR/drive_c" ]; then
    need_boot=1; boot_reason="غير موجودة"
elif [ "$(prefix_dll_count)" -lt 400 ]; then
    need_boot=1; boot_reason="ناقصة ($(prefix_dll_count) مكتبة فقط — wineboot سابق لم يكتمل)"
elif [ "$(cat "$WINE_MARK" 2>/dev/null)" != "$WINE_TAG" ]; then
    need_boot=1; boot_reason="بُنيت بنسخة Wine مختلفة"
fi

if [ "$need_boot" = 0 ]; then
    ok "بيئة ويندوز سليمة ($(prefix_dll_count) مكتبة)"
else
    log "إعادة إنشاء بيئة ويندوز — السبب: $boot_reason"

    # run_wineboot — ينشئ البيئة من الصفر بالبناء الحالي ويعيد 0 عند النجاح
    run_wineboot() {
        rm -rf "$WINEPREFIX_DIR"
        install -d -o "$S25_USER" -g "$S25_USER" "$WINEPREFIX_DIR"
        log "تهيئة أولية (wineboot) — 10 إلى 30 دقيقة على الجوال. لا تقطعها."
        su - "$S25_USER" -c "cd /tmp && . /opt/s25/etc/env.sh && . /opt/s25/etc/windows.sh && \
            DISPLAY= box64 \"\$S25_WINE\" wineboot -u" >/tmp/wineboot.log 2>&1 || true
        [ "$(prefix_dll_count)" -ge 400 ]
    }

    # تعارض نسخ box64/Wine يظهر كبيئة فارغة — نجرّب بناءات بديلة تلقائياً
    if run_wineboot; then
        BOOT_OK=1
    else
        BOOT_OK=0
        warn "wineboot لم يُنشئ بيئة صالحة ($(prefix_dll_count) مكتبة) — آخر الأسطر:"
        tail -8 /tmp/wineboot.log | sed 's/^/    /'
        if grep -q 'could not load kernel32.dll\|wine_main_preload_info' /tmp/wineboot.log 2>/dev/null; then
            warn "هذه علامة تعارض بين نسخة box64 ($(box64 --version 2>&1 | grep -oE 'v[0-9.]+' | head -1)) وبناء Wine"
        fi
        for alt in "$WINE_URL_DEFAULT" "$WINE_URL_ALT1" "$WINE_URL_ALT2"; do
            [ "$(basename "$alt")" = "$(basename "${WINE_TAR:-}")" ] && continue
            step "تجربة بناء Wine بديل: $(basename "$alt")"
            install_wine_build "$alt" || continue
            # نعيد قراءة البيئة لأن مسار Wine قد تغيّر
            # shellcheck source=/dev/null
            . /opt/s25/etc/windows.sh
            if run_wineboot; then BOOT_OK=1; break; fi
            warn "البناء $(basename "$alt") لم ينجح أيضاً"
        done
    fi

    DLLS="$(prefix_dll_count)"
    if [ "$BOOT_OK" = 1 ]; then
        WINE_TAG="$(basename "${WINE_TAR:-wine}")"
        printf '%s' "$WINE_TAG" > "$WINE_MARK"
        chown "$S25_USER:$S25_USER" "$WINE_MARK" 2>/dev/null || true
        ok "بيئة ويندوز جاهزة ($DLLS مكتبة) — البناء: $WINE_TAG"
    else
        warn "تعذّر إنشاء بيئة ويندوز بأي بناء ($DLLS مكتبة)"
        warn "الأسباب بالترتيب:"
        warn "  • box64 قديم مقابل Wine — حدّثه:  sudo apt-get install --only-upgrade box64"
        warn "  • مكتبات x86_64 ناقصة — أعد:  sudo bash /opt/s25/src/install-windows-layer.sh"
        warn "  • جرّب بناءً محدداً:  --wine-url <رابط بناء amd64-wow64>"
        warn "  السجل الكامل: /tmp/wineboot.log"
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
        [ -n "$DXVK_URL" ] || DXVK_URL="$DXVK_FALLBACK_URL"
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
