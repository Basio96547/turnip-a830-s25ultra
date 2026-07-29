#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  s25-desktop — تشغيل سطح مكتب لينكس / Claude PC / كروم على الجوال
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
    ""|desktop|claude|chrome|shell)
        MODE="${1:-desktop}"
        if [ $# -gt 0 ]; then shift; fi
        ;;
    -h|--help)
        cat <<'EOF'
الاستخدام: s25-desktop [desktop|claude|chrome|shell] [أوامر إضافية]

  desktop   سطح مكتب XFCE كامل (الافتراضي)
  claude    تطبيق Claude PC وحده بملء الشاشة
  chrome    كروم سطح المكتب وحده
  shell     طرفية داخل الحاوية بدون واجهة رسومية

متغيرات مفيدة (أو عدّل $PREFIX/etc/s25-desktop.conf):
  S25_GPU=off     تعطيل Turnip واستخدام رسوميات المعالج
  S25_DPI=160     تكبير خطوط سطح المكتب
  S25_SCALE=1.6   تكبير واجهة كروم/Claude
EOF
        exit 0 ;;
    *) die "وضع غير معروف: $1 (استخدم --help)" ;;
esac

ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"
[ -d "$ROOTFS" ] || die "الحاوية '$DISTRO' غير مثبتة — شغّل: bash s25-desktop/install.sh"
command -v proot-distro >/dev/null || die "proot-distro غير مثبت"

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
if [ "$MODE" != "shell" ]; then
    if [ ! -e "$XSOCK" ]; then
        log "تشغيل خادم X على $XDISPLAY…"
        mkdir -p "$TMP/.X11-unix"
        termux-x11 "$XDISPLAY" >/dev/null 2>&1 &
    else
        log "خادم X يعمل مسبقاً على $XDISPLAY"
    fi

    # فتح واجهة العرض (تطبيق Termux:X11)
    if command -v am >/dev/null; then
        am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 \
            || warn "افتح تطبيق Termux:X11 يدوياً"
    fi

    for _ in $(seq 1 30); do
        [ -e "$XSOCK" ] && break
        sleep 1
    done
    [ -e "$XSOCK" ] || die "لم يبدأ خادم X.
تأكد من تثبيت تطبيق Termux:X11 (APK) وفتحه مرة واحدة:
  https://github.com/termux/termux-x11/releases"
fi

# ── الدخول إلى الحاوية وتشغيل الجلسة ───────────────────────────────────
BINDS=()
[ -d /sdcard ] && BINDS+=(--bind "/sdcard:/mnt/sdcard")
[ -e /dev/kgsl-3d0 ] || warn "‏/dev/kgsl-3d0 غير موجود — تسريع Turnip لن يعمل"

USER_ARG=()
if grep -q '^s25:' "$ROOTFS/etc/passwd" 2>/dev/null; then
    USER_ARG=(--user s25)
fi

ENV_PASS=""
for v in S25_GPU S25_DPI S25_SCALE S25_CLAUDE_URL S25_CHROME_FLAGS TU_DEBUG; do
    val="$(eval "printf '%s' \"\${$v:-}\"")"
    [ -n "$val" ] && ENV_PASS="$ENV_PASS $v=$(printf '%q' "$val")"
done

log "تشغيل الوضع: $MODE"
exec proot-distro login "$DISTRO" "${USER_ARG[@]}" --shared-tmp "${BINDS[@]}" -- \
    /bin/bash -lc "export DISPLAY=$XDISPLAY$ENV_PASS; exec /opt/s25/bin/s25-session $MODE $*"
