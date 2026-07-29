#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  install.sh — المُثبّت الرئيسي لنظام سطح المكتب على Galaxy S25 Ultra
#
#  يُشغّل داخل Termux على الجوال (بدون روت):
#     git clone https://github.com/basio96547/turnip-a830-s25ultra
#     cd turnip-a830-s25ultra
#     bash s25-desktop/install.sh
#
#  ما يقوم به:
#   1. تهيئة Termux (X11 + صوت + proot-distro)
#   2. تثبيت حاوية Debian arm64 وسطح مكتب XFCE
#   3. بناء/تثبيت Mesa (Turnip KGSL لـ A830 + Zink) لتشغيل OpenGL/Vulkan
#   4. تثبيت Chromium (كروم سطح المكتب) بتسريع GPU
#   5. تثبيت Claude PC (تطبيق سطح مكتب) + Claude Code CLI
# ═══════════════════════════════════════════════════════════════════════

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"

DISTRO="${S25_DISTRO:-debian}"
JOBS=""
MESA_REF="${MESA_REF:-main}"
MESA_TARBALL="${S25_MESA_TARBALL:-}"
CLAUDE_MODE="auto"
SKIP_MESA=0
SKIP_CHROMIUM=0
SKIP_CLAUDE=0
WITH_WINDOWS=0

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
  --claude-mode <mode>    auto | community | wrapper   (افتراضي: auto)
                            community = حزمة Claude Desktop من المجتمع
                            wrapper   = تطبيق Electron محلي لـ claude.ai
  --skip-mesa             تخطي Mesa/Turnip (سيعمل كل شيء بالمعالج فقط — أبطأ)
  --skip-chromium         تخطي تثبيت Chromium
  --skip-claude           تخطي تثبيت Claude PC
  --with-windows          إضافة طبقة ويندوز (Wine + box64 + DXVK) لتشغيل
                          ملفات .exe: Claude Desktop و Chrome لويندوز — تجريبي
  -y, --yes               عدم السؤال عن أي تأكيد
  -h, --help              هذه المساعدة

أمثلة:
  bash s25-desktop/install.sh
  bash s25-desktop/install.sh --mesa-tarball ~/storage/downloads/mesa-a830-glibc-arm64.tar.gz
  bash s25-desktop/install.sh --skip-mesa --claude-mode wrapper
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --distro)        DISTRO="${2:?}"; shift 2 ;;
        --jobs)          JOBS="${2:?}"; shift 2 ;;
        --mesa-ref)      MESA_REF="${2:?}"; shift 2 ;;
        --mesa-tarball)  MESA_TARBALL="${2:?}"; shift 2 ;;
        --claude-mode)   CLAUDE_MODE="${2:?}"; shift 2 ;;
        --skip-mesa)     SKIP_MESA=1; shift ;;
        --skip-chromium) SKIP_CHROMIUM=1; shift ;;
        --skip-claude)   SKIP_CLAUDE=1; shift ;;
        --with-windows)  WITH_WINDOWS=1; shift ;;
        -y|--yes)        export S25_ASSUME_YES=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *) err "خيار غير معروف: $1"; usage; exit 1 ;;
    esac
done

case "$CLAUDE_MODE" in auto|community|wrapper) ;; *) die "--claude-mode يجب أن يكون auto أو community أو wrapper" ;; esac

banner

is_termux || die "هذا السكربت يعمل داخل تطبيق Termux على الجوال فقط.
حمّل Termux من F-Droid أو GitHub (وليس من Play Store)."
is_arm64  || warn "المعمارية $(uname -m) غير aarch64 — تسريع Turnip لن يعمل"

log "التوزيعة       : $DISTRO"
log "Mesa           : ${MESA_TARBALL:+حزمة جاهزة: $MESA_TARBALL}${MESA_TARBALL:-فرع $MESA_REF}"
log "Claude PC      : $CLAUDE_MODE"
[ "$SKIP_MESA" = 1 ] && warn "سيتم تخطي Turnip — الرسوميات ستعمل على المعالج (بطيء)"

step "المرحلة 1/2 — تهيئة Termux"
bash "$HERE/termux/setup-termux.sh"

step "المرحلة 2/2 — تهيئة الحاوية والتطبيقات"
PROV_ARGS=(--distro "$DISTRO" --mesa-ref "$MESA_REF" --claude-mode "$CLAUDE_MODE")
[ -n "$JOBS" ]           && PROV_ARGS+=(--jobs "$JOBS")
[ -n "$MESA_TARBALL" ]   && PROV_ARGS+=(--mesa-tarball "$MESA_TARBALL")
[ "$SKIP_MESA" = 1 ]     && PROV_ARGS+=(--skip-mesa)
[ "$SKIP_CHROMIUM" = 1 ] && PROV_ARGS+=(--skip-chromium)
[ "$SKIP_CLAUDE" = 1 ]   && PROV_ARGS+=(--skip-claude)
[ "$WITH_WINDOWS" = 1 ] && PROV_ARGS+=(--with-windows)

bash "$HERE/termux/provision-container.sh" "${PROV_ARGS[@]}"

step "تم التثبيت ✓"
cat <<EOF

  ${C_G}طريقة التشغيل:${C_N}

    s25-desktop            # سطح مكتب XFCE كامل
    s25-desktop claude     # تطبيق Claude PC فقط (ملء الشاشة)
    s25-desktop chrome     # كروم سطح المكتب فقط
    s25-desktop shell      # طرفية داخل الحاوية (بدون واجهة)
    s25-stop               # إيقاف كل شيء وتحرير الذاكرة

  ${C_G}قبل أول تشغيل:${C_N}
    • ثبّت تطبيق ${C_B}Termux:X11${C_N} (APK من github.com/termux/termux-x11/releases)
    • افتحه مرة واحدة ثم ارجع إلى Termux وشغّل s25-desktop

  ${C_G}للتشخيص داخل الحاوية:${C_N}  s25-desktop shell  ثم  s25-doctor

  الدليل الكامل: s25-desktop/docs/README.md

EOF
