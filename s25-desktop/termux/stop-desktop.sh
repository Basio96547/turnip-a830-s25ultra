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
pkill -f "installed-rootfs/$DISTRO" >/dev/null 2>&1 || true
sleep 1
pkill -9 -f "installed-rootfs/$DISTRO" >/dev/null 2>&1 || true

log "إيقاف خادم X…"
pkill -f 'termux-x11' >/dev/null 2>&1 || true
if command -v am >/dev/null; then
    am force-stop com.termux.x11 >/dev/null 2>&1 || true
fi

log "إيقاف خدمة الصوت…"
pulseaudio -k >/dev/null 2>&1 || true

command -v termux-wake-unlock >/dev/null && termux-wake-unlock >/dev/null 2>&1 || true

ok "تم إيقاف نظام سطح المكتب"
