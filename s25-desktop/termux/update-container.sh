#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  s25-update — يحدّث سكربتات النظام داخل الحاوية ثم ينفّذ ما تطلبه
#
#  المشكلة التي يحلها: /opt/s25/src داخل الحاوية نسخة من المستودع، فـ
#  git pull في Termux لا يحدّثها — وتشغيل سكربت قديم يعطي نتائج مضللة.
#
#  الاستخدام:
#     s25-update                                   # سحب التحديث + تحديث الحاوية
#     s25-update install-windows-layer.sh --prefix-only
#     s25-update build-mesa-turnip.sh --from-tarball <رابط>
#     s25-update --no-pull bootstrap-debian.sh     # بلا git pull
# ═══════════════════════════════════════════════════════════════════════

C_G=$'\033[0;32m'; C_Y=$'\033[0;33m'; C_R=$'\033[0;31m'; C_N=$'\033[0m'
log()  { printf '%s\n' "${C_G}▶${C_N} $*"; }
ok()   { printf '%s\n' "${C_G}✓${C_N} $*"; }
warn() { printf '%s\n' "${C_Y}⚠${C_N} $*" >&2; }
die()  { printf '%s\n' "${C_R}✗${C_N} $*" >&2; exit 1; }

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
CONF="$PREFIX/etc/s25-desktop.conf"
# shellcheck source=/dev/null
[ -r "$CONF" ] && . "$CONF"

DISTRO="${S25_DISTRO:-debian}"
REPO="${S25_REPO:-$HOME/turnip-a830-s25ultra}"
DO_PULL=1

while [ $# -gt 0 ]; do
    case "$1" in
        --no-pull) DO_PULL=0; shift ;;
        -h|--help) sed -n '3,18p' "$0"; exit 0 ;;
        *) break ;;
    esac
done

[ -d "$REPO/.git" ] || die "لم يتم العثور على المستودع في $REPO
حدّد مساره:  S25_REPO=/path/to/turnip-a830-s25ultra s25-update ..."

if [ "$DO_PULL" = 1 ]; then
    log "سحب أحدث نسخة من المستودع…"
    git -C "$REPO" pull --ff-only || warn "تعذر السحب — سنستخدم النسخة الحالية"
fi

log "تحديث سكربتات النظام داخل الحاوية…"
bash "$REPO/s25-desktop/termux/provision-container.sh" --distro "$DISTRO" --payload-only \
    || die "فشل تحديث الحمولة"

[ $# -eq 0 ] && exit 0

SCRIPT="$1"; shift
case "$SCRIPT" in
    */*) die "اكتب اسم السكربت فقط، مثل: install-windows-layer.sh" ;;
esac

BINDS=()
if [ "${S25_BIND_SDCARD:-0}" = "1" ] && [ -d /sdcard ]; then
    BINDS+=(--bind "/sdcard:/mnt/sdcard")
fi

log "تشغيل $SCRIPT داخل الحاوية…"
exec proot-distro login "$DISTRO" --shared-tmp "${BINDS[@]}" -- \
    /bin/bash "/opt/s25/src/$SCRIPT" "$@"
