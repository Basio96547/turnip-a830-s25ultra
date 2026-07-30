#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  install.sh — مُثبّت نظام تشغيل برامج ويندوز على Galaxy S25 Ultra
#
#  يُشغّل داخل Termux على الجوال (بدون روت):
#     git clone -b claude/s25-ultra-emulator-system-fs4ozh https://github.com/basio96547/turnip-a830-s25ultra
#     cd turnip-a830-s25ultra
#     bash s25-desktop/install.sh
#
#  ما يقوم به:
#   1. تهيئة Termux (X11 + صوت + proot-distro)
#   2. تثبيت حاوية Debian arm64 وسطح مكتب XFCE
#   3. بناء/تثبيت Mesa (Turnip KGSL لـ A830 + Zink) — تسريع الرسوميات
#   4. تثبيت طبقة ويندوز (Wine + box64 + DXVK) لتشغيل ملفات .exe
#      → Claude Desktop لويندوز · Google Chrome لويندوز · أي برنامج ويندوز
# ═══════════════════════════════════════════════════════════════════════

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

DISTRO="${S25_DISTRO:-debian}"
JOBS=""
MESA_REF="${MESA_REF:-main}"
MESA_TARBALL="${S25_MESA_TARBALL:-}"
SKIP_MESA=0
SKIP_WINDOWS=0

usage() {
    cat <<'EOF'
الاستخدام: bash s25-desktop/install.sh [خيارات]

الخيارات:
  --distro <alias>        توزيعة الحاوية (افتراضي: debian)
  --jobs <N>              عدد مهام الترجمة عند بناء Mesa (افتراضي: تلقائي)
  --mesa-ref <ref>        فرع/وسم Mesa المستخدم في البناء (افتراضي: main)
  --mesa-tarball <path|url>
                          استخدام حزمة Mesa مبنية مسبقاً (أسرع بكثير من البناء
                          على الجهاز — انظر GitHub Actions: build-mesa-glibc-arm64)
  --skip-mesa             تخطي Mesa/Turnip (رسوميات على المعالج — أبطأ بكثير)
  --skip-windows          تخطي طبقة ويندوز (تثبيت الحاوية وسطح المكتب فقط)
  -y, --yes               عدم السؤال عن أي تأكيد
  -h, --help              هذه المساعدة

أمثلة:
  bash s25-desktop/install.sh
  bash s25-desktop/install.sh --mesa-tarball ~/storage/downloads/mesa-a830-glibc-arm64.tar.gz
  bash s25-desktop/install.sh --jobs 2
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --distro)        DISTRO="${2:?}"; shift 2 ;;
        --jobs)          JOBS="${2:?}"; shift 2 ;;
        --mesa-ref)      MESA_REF="${2:?}"; shift 2 ;;
        --mesa-tarball)  MESA_TARBALL="${2:?}"; shift 2 ;;
        --skip-mesa)     SKIP_MESA=1; shift ;;
        --skip-windows)  SKIP_WINDOWS=1; shift ;;
        -y|--yes)        export S25_ASSUME_YES=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *) err "خيار غير معروف: $1"; usage; exit 1 ;;
    esac
done

banner

is_termux || die "هذا السكربت يعمل داخل تطبيق Termux على الجوال فقط.
حمّل Termux من F-Droid أو GitHub (وليس من Play Store)."
is_arm64  || warn "المعمارية $(uname -m) غير aarch64 — تسريع Turnip لن يعمل"

log "التوزيعة       : $DISTRO"
log "Mesa           : ${MESA_TARBALL:+حزمة جاهزة: $MESA_TARBALL}${MESA_TARBALL:-فرع $MESA_REF}"
log "طبقة ويندوز    : $([ "$SKIP_WINDOWS" = 1 ] && echo "متخطاة" || echo "Wine + box64 + DXVK")"
[ "$SKIP_MESA" = 1 ] && warn "سيتم تخطي Turnip — الرسوميات ستعمل على المعالج (بطيء)"

step "المرحلة 1/2 — تهيئة Termux"
bash "$HERE/termux/setup-termux.sh"

step "المرحلة 2/2 — تهيئة الحاوية وطبقة ويندوز"
PROV_ARGS=(--distro "$DISTRO" --mesa-ref "$MESA_REF")
[ -n "$JOBS" ]           && PROV_ARGS+=(--jobs "$JOBS")
[ -n "$MESA_TARBALL" ]   && PROV_ARGS+=(--mesa-tarball "$MESA_TARBALL")
[ "$SKIP_MESA" = 1 ]     && PROV_ARGS+=(--skip-mesa)
[ "$SKIP_WINDOWS" = 1 ]  && PROV_ARGS+=(--skip-windows)

bash "$HERE/termux/provision-container.sh" "${PROV_ARGS[@]}"

step "تم التثبيت ✓"
cat <<EOF

  ${C_G}طريقة التشغيل:${C_N}

    s25-desktop win-claude   # Claude Desktop لويندوز (.exe)
    s25-desktop win-chrome   # Chrome لويندوز (.exe)
    s25-desktop windows      # winecfg — للتأكد أن طبقة ويندوز تعمل
    s25-desktop              # سطح مكتب XFCE كامل
    s25-desktop shell        # طرفية داخل الحاوية
    s25-stop                 # إيقاف كل شيء وتحرير الذاكرة
    s25-update               # تحديث السكربتات داخل الحاوية بعد git pull

  ${C_G}قبل أول تشغيل:${C_N}
    • ثبّت تطبيق ${C_B}Termux:X11${C_N} (APK من github.com/termux/termux-x11/releases)
    • أو ثبّت تطبيق ${C_B}S25 Desktop${C_N} (s25-launcher) لتشغيل كل شيء بأيقونة واحدة

  ${C_G}أول تشغيل لبرنامج ويندوز${C_N} ينزّل مُثبّته الرسمي داخل بيئة ويندوز — كن صبوراً.

  ${C_G}للتشخيص:${C_N}  s25-desktop shell  ثم  s25-doctor

  الدليل: s25-desktop/docs/WINDOWS.md

EOF
