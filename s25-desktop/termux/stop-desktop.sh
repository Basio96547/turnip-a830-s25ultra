#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  s25-stop — إيقاف جلسة سطح المكتب وتحرير الذاكرة والبطارية
# ═══════════════════════════════════════════════════════════════════════

C_G=$'\033[0;32m'; C_Y=$'\033[0;33m'; C_N=$'\033[0m'
log()  { printf '%s\n' "${C_G}▶${C_N} $*"; }
ok()   { printf '%s\n' "${C_G}✓${C_N} $*"; }
warn() { printf '%s\n' "${C_Y}⚠${C_N} $*" >&2; }

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
CONF="$PREFIX/etc/s25-desktop.conf"
# shellcheck source=/dev/null
[ -r "$CONF" ] && . "$CONF"
DISTRO="${S25_DISTRO:-debian}"

log "إيقاف جلسات الحاوية…"
# تخطيط proot-distro يختلف بين النسخ: installed-rootfs/<alias> أو
# containers/<alias>/rootfs — مطابقة الأول وحده كانت تترك الجلسات تعمل
# على الأجهزة ذات التخطيط الجديد، فيبقى خادم X مشغولاً ولا يبدأ من جديد.
for pat in "installed-rootfs/$DISTRO" "containers/$DISTRO" "proot-distro login $DISTRO"; do
    pkill -f "$pat" >/dev/null 2>&1 || true
done
sleep 1
for pat in "installed-rootfs/$DISTRO" "containers/$DISTRO" "proot-distro login $DISTRO"; do
    pkill -9 -f "$pat" >/dev/null 2>&1 || true
done

log "إيقاف خادم X…"
pkill -f 'termux-x11' >/dev/null 2>&1 || true
if command -v am >/dev/null; then
    am force-stop com.termux.x11 >/dev/null 2>&1 || true
fi
# ملف القفل والمقبس: إن بقيا بلا خادم يعمل، يرفض termux-x11 البدء لاحقاً
TMP="${TMPDIR:-$PREFIX/tmp}"
XDISPLAY="${S25_XDISPLAY:-:0}"
rm -f "$TMP/.X${XDISPLAY#:}-lock" "$TMP/.X11-unix/X${XDISPLAY#:}" 2>/dev/null || true

log "إيقاف خدمة الصوت…"
pulseaudio -k >/dev/null 2>&1 || true

command -v termux-wake-unlock >/dev/null && termux-wake-unlock >/dev/null 2>&1 || true

ok "تم إيقاف نظام سطح المكتب"
