#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  s25-desktop — تشغيل برامج ويندوز (.exe) أو سطح مكتب لينكس على الجوال
#  (سكربت مستقل — يُنسخ إلى $PREFIX/bin/s25-desktop)
# ═══════════════════════════════════════════════════════════════════════

C_G=$'\033[0;32m'; C_Y=$'\033[0;33m'; C_R=$'\033[0;31m'; C_N=$'\033[0m'
log()  { printf '%s\n' "${C_G}▶${C_N} $*"; }
warn() { printf '%s\n' "${C_Y}⚠${C_N} $*" >&2; }
die()  { printf '%s\n' "${C_R}✗${C_N} $*" >&2; exit 1; }

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
CONF="$PREFIX/etc/s25-desktop.conf"
# shellcheck source=/dev/null
[ -r "$CONF" ] && . "$CONF"

DISTRO="${S25_DISTRO:-debian}"
XDISPLAY="${S25_XDISPLAY:-:0}"
TMP="${TMPDIR:-$PREFIX/tmp}"
XSOCK="$TMP/.X11-unix/X${XDISPLAY#:}"

MODE="desktop"
case "${1:-}" in
    ""|desktop|shell|win-claude|win-chrome|windows)
        MODE="${1:-desktop}"
        if [ $# -gt 0 ]; then shift; fi
        ;;
    -h|--help)
        cat <<'EOF'
الاستخدام: s25-desktop [win-claude|win-chrome|windows|desktop|shell] [أوامر إضافية]

  win-claude  Claude Desktop لويندوز (.exe) بملء الشاشة
  win-chrome  Chrome لويندوز (.exe) بملء الشاشة
  windows     winecfg — للتأكد أن طبقة ويندوز تعمل
  desktop     سطح مكتب XFCE كامل (الافتراضي)
  shell       طرفية داخل الحاوية بدون واجهة رسومية

متغيرات مفيدة (أو عدّل $PREFIX/etc/s25-desktop.conf):
  S25_GPU=off     تعطيل Turnip واستخدام رسوميات المعالج
  S25_DPI=160     تكبير خطوط سطح المكتب
  S25_SCALE=1.6   تكبير واجهة البرامج
EOF
        exit 0 ;;
    *) die "وضع غير معروف: $1 (استخدم --help)" ;;
esac

command -v proot-distro >/dev/null || die "proot-distro غير مثبت"

# جذر نظام الملفات: المُثبّت يحفظه في الإعدادات؛ وإلا نكتشفه (التخطيط يختلف
# بين نسخ proot-distro: installed-rootfs/<alias> أو containers/<alias>/rootfs)
ROOTFS="${S25_ROOTFS:-}"
if [ -z "$ROOTFS" ] || [ ! -r "$ROOTFS/etc/os-release" ]; then
    ROOTFS=""
    for c in "$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO" \
             "$PREFIX/var/lib/proot-distro/containers/$DISTRO/rootfs" \
             "$PREFIX/var/lib/proot-distro/containers/$DISTRO/root" \
             "$PREFIX/var/lib/proot-distro/containers/$DISTRO"; do
        if [ -r "$c/etc/os-release" ]; then ROOTFS="$c"; break; fi
    done
fi
if [ -z "$ROOTFS" ]; then
    proot-distro login "$DISTRO" -- /bin/true >/dev/null 2>&1 \
        || die "الحاوية '$DISTRO' غير مثبتة — شغّل: bash s25-desktop/install.sh"
fi

# ── منع نوم الجهاز أثناء الجلسة ────────────────────────────────────────
command -v termux-wake-lock >/dev/null && termux-wake-lock >/dev/null 2>&1 || true

# ── الصوت: PulseAudio عبر TCP محلي ─────────────────────────────────────
if ! pgrep -x pulseaudio >/dev/null 2>&1; then
    log "تشغيل خدمة الصوت…"
    pulseaudio --start --exit-idle-time=-1 \
        --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
        >/dev/null 2>&1 || warn "تعذر تشغيل PulseAudio — سيعمل النظام بدون صوت"
fi

# ── خادم X (Termux:X11) ────────────────────────────────────────────────
X11_LOG="$TMP/s25-termux-x11.log"
X11_LOCK="$TMP/.X${XDISPLAY#:}-lock"

# بقايا جلسة قُطعت: ملف قفل بلا خادم يعمل يجعل termux-x11 يرفض البدء بصمت
x11_clean_stale() {
    pgrep -f 'termux-x11' >/dev/null 2>&1 && return 0
    rm -f "$X11_LOCK" "$XSOCK" 2>/dev/null || true
}

x11_kill_all() {
    pkill -f 'termux-x11' >/dev/null 2>&1 || true
    command -v am >/dev/null 2>&1 && am force-stop com.termux.x11 >/dev/null 2>&1 || true
    sleep 2
    rm -f "$X11_LOCK" "$XSOCK" 2>/dev/null || true
}

x11_start() {
    mkdir -p "$TMP/.X11-unix"
    log "تشغيل خادم X على $XDISPLAY…"
    termux-x11 "$XDISPLAY" >"$X11_LOG" 2>&1 &
    # في Termux:X11 التطبيق نفسه هو خادم X — لا يظهر المقبس قبل أن يعمل التطبيق
    if command -v am >/dev/null; then
        am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 \
            || warn "افتح تطبيق Termux:X11 يدوياً"
    fi
}

x11_wait() { # x11_wait <ثوانٍ>
    local left="$1"
    while [ "$left" -gt 0 ]; do
        [ -e "$XSOCK" ] && return 0
        sleep 1
        left=$((left - 1))
    done
    return 1
}

if [ "$MODE" != "shell" ]; then
    if [ -e "$XSOCK" ]; then
        log "خادم X يعمل مسبقاً على $XDISPLAY"
    else
        x11_clean_stale
        x11_start
        if ! x11_wait 30; then
            warn "لم يظهر مقبس X — تنظيف بقايا الجلسة السابقة وإعادة المحاولة"
            x11_kill_all
            x11_start
            x11_wait 30 || {
                if [ -s "$X11_LOG" ]; then
                    printf '  ── مخرجات termux-x11 ──\n' >&2
                    tail -12 "$X11_LOG" | sed 's/^/  /' >&2
                fi
                die "لم يبدأ خادم X على $XDISPLAY.

جرّب بالترتيب:
  1. افتح تطبيق Termux:X11 يدوياً من قائمة التطبيقات واتركه مفتوحاً،
     ثم أعد تشغيل هذا الأمر.
  2. s25-stop   ثم أعد المحاولة (ينظّف كل البقايا).
  3. إن كان التطبيق غير مثبت، ثبّت app-arm64-v8a-debug.apk من:
     https://github.com/termux/termux-x11/releases
  4. أوقف تحسين البطارية لتطبيق Termux:X11 — أندرويد يقتله في الخلفية:
     الإعدادات ▸ التطبيقات ▸ Termux:X11 ▸ البطارية ▸ غير مقيّد

السجل: $X11_LOG"
            }
        fi
    fi
fi

# ── الدخول إلى الحاوية وتشغيل الجلسة ───────────────────────────────────
BINDS=()
if [ "${S25_BIND_SDCARD:-1}" = "1" ] && [ -d /sdcard ]; then
    BINDS+=(--bind "/sdcard:/mnt/sdcard")
fi
[ -e /dev/kgsl-3d0 ] || warn "‏/dev/kgsl-3d0 غير موجود — تسريع Turnip لن يعمل"

USER_ARG=()
if [ -n "$ROOTFS" ] && grep -q '^s25:' "$ROOTFS/etc/passwd" 2>/dev/null; then
    USER_ARG=(--user s25)
elif proot-distro login "$DISTRO" -- id -u s25 >/dev/null 2>&1; then
    USER_ARG=(--user s25)
fi

ENV_PASS=""
for v in S25_GPU S25_DPI S25_SCALE S25_CHROME_FLAGS S25_WIN_REINSTALL \
         S25_CLAUDE_SETUP_URL S25_CHROME_MSI_URL TU_DEBUG; do
    val="$(eval "printf '%s' \"\${$v:-}\"")"
    [ -n "$val" ] && ENV_PASS="$ENV_PASS $v=$(printf '%q' "$val")"
done

log "تشغيل الوضع: $MODE"
exec proot-distro login "$DISTRO" "${USER_ARG[@]}" --shared-tmp "${BINDS[@]}" -- \
    /bin/bash -lc "export DISPLAY=$XDISPLAY$ENV_PASS; exec /opt/s25/bin/s25-session $MODE $*"
