#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  provision-container.sh — تثبيت حاوية Debian وتهيئتها من داخل Termux
# ═══════════════════════════════════════════════════════════════════════

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S25_DIR="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$S25_DIR/.." && pwd)"
# shellcheck source=../lib/common.sh
. "$S25_DIR/lib/common.sh"

DISTRO="debian"
JOBS=""
MESA_REF="main"
MESA_TARBALL=""
CLAUDE_MODE="auto"
SKIP_MESA=0
SKIP_CHROMIUM=0
SKIP_CLAUDE=0
WITH_WINDOWS=0

while [ $# -gt 0 ]; do
    case "$1" in
        --distro)          DISTRO="${2:?}"; shift 2 ;;
        --jobs)            JOBS="${2:?}"; shift 2 ;;
        --mesa-ref)        MESA_REF="${2:?}"; shift 2 ;;
        --mesa-tarball)    MESA_TARBALL="${2:?}"; shift 2 ;;
        --claude-mode)     CLAUDE_MODE="${2:?}"; shift 2 ;;
        --skip-mesa)       SKIP_MESA=1; shift ;;
        --skip-chromium)   SKIP_CHROMIUM=1; shift ;;
        --skip-claude)     SKIP_CLAUDE=1; shift ;;
        --with-windows)    WITH_WINDOWS=1; shift ;;
        *) die "خيار غير معروف: $1" ;;
    esac
done

is_termux || die "يجب تشغيل هذا السكربت داخل Termux"
have proot-distro || die "proot-distro غير مثبت — شغّل setup-termux.sh أولاً"

ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"

# ── 1. تثبيت التوزيعة ──────────────────────────────────────────────────
if [ -d "$ROOTFS" ]; then
    ok "حاوية $DISTRO مثبتة مسبقاً"
else
    log "تنزيل وتثبيت حاوية $DISTRO (قد يستغرق عدة دقائق)…"
    retry 3 proot-distro install "$DISTRO" || die "فشل تثبيت الحاوية $DISTRO"
    ok "تم تثبيت $DISTRO"
fi
[ -d "$ROOTFS" ] || die "لم يتم العثور على نظام الملفات: $ROOTFS"

# ── 2. نسخ حمولة التثبيت داخل الحاوية ──────────────────────────────────
PAYLOAD="$ROOTFS/opt/s25/src"
log "نسخ سكربتات النظام إلى /opt/s25/src داخل الحاوية…"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"
cp -r "$S25_DIR/container/." "$PAYLOAD/"
mkdir -p "$PAYLOAD/lib"
cp "$S25_DIR/lib/common.sh" "$PAYLOAD/lib/common.sh"

# باتشات Mesa وسكربتات بايثون من جذر المستودع (نفس تلك المستخدمة في بناء Android)
mkdir -p "$PAYLOAD/mesa-patches"
cp "$REPO_ROOT/patches-a830/"*.patch "$PAYLOAD/mesa-patches/" 2>/dev/null || \
    warn "لم يتم العثور على patches-a830/*.patch"
cp "$REPO_ROOT/apply_a830_gpus.py" "$REPO_ROOT/fix_a830_dev_info.py" "$PAYLOAD/mesa-patches/" 2>/dev/null || \
    warn "لم يتم العثور على سكربتات بايثون للباتشات"

find "$PAYLOAD" -type f -name '*.sh' -exec chmod +x {} +
[ -d "$PAYLOAD/bin" ] && chmod +x "$PAYLOAD/bin/"* || true
ok "تم نسخ الحمولة"

# حزمة Mesa جاهزة: انسخها للداخل إن كانت ملفاً محلياً
TARBALL_IN_CONTAINER=""
if [ -n "$MESA_TARBALL" ]; then
    case "$MESA_TARBALL" in
        http://*|https://*) TARBALL_IN_CONTAINER="$MESA_TARBALL" ;;
        *)
            [ -r "$MESA_TARBALL" ] || die "الملف غير موجود: $MESA_TARBALL"
            cp "$MESA_TARBALL" "$PAYLOAD/mesa-prebuilt.tar.gz"
            TARBALL_IN_CONTAINER="/opt/s25/src/mesa-prebuilt.tar.gz"
            ok "تم نسخ حزمة Mesa الجاهزة إلى الحاوية"
            ;;
    esac
fi

# ── 3. تشغيل خطوات التهيئة داخل الحاوية ────────────────────────────────
BINDS=()
[ -d /sdcard ] && BINDS+=(--bind "/sdcard:/mnt/sdcard")

# plogin <أمر داخل الحاوية>
plogin() {
    proot-distro login "$DISTRO" --shared-tmp "${BINDS[@]}" -- /bin/bash -c "$1"
}

step "تهيئة النظام الأساسي وسطح مكتب XFCE"
plogin "S25_ASSUME_YES=1 bash /opt/s25/src/bootstrap-debian.sh" \
    || die "فشلت تهيئة الحاوية (bootstrap-debian.sh)"

if [ "$SKIP_MESA" = 1 ]; then
    warn "تخطي بناء Mesa/Turnip بناءً على طلبك"
elif [ -n "$TARBALL_IN_CONTAINER" ]; then
    step "تثبيت Mesa/Turnip من حزمة جاهزة"
    plogin "bash /opt/s25/src/build-mesa-turnip.sh --from-tarball '$TARBALL_IN_CONTAINER'" \
        || warn "فشل تثبيت حزمة Mesa الجاهزة — سيعمل النظام بالمعالج فقط"
else
    step "بناء Mesa (Turnip KGSL + Zink) داخل الحاوية"
    warn "هذه أطول مرحلة: من 40 دقيقة إلى ساعتين على الجهاز. أبقِ الشاشة موصولة بالشاحن."
    MESA_ARGS="--mesa-ref '$MESA_REF'"
    [ -n "$JOBS" ] && MESA_ARGS="$MESA_ARGS --jobs '$JOBS'"
    plogin "bash /opt/s25/src/build-mesa-turnip.sh $MESA_ARGS" \
        || warn "فشل بناء Mesa — سيعمل النظام بالمعالج فقط (راجع docs/TROUBLESHOOTING.md)"
fi

if [ "$SKIP_CHROMIUM" = 1 ]; then
    warn "تخطي تثبيت Chromium بناءً على طلبك"
else
    step "تثبيت كروم سطح المكتب (Chromium arm64)"
    plogin "bash /opt/s25/src/install-chromium.sh" \
        || warn "فشل تثبيت Chromium"
fi

if [ "$SKIP_CLAUDE" = 1 ]; then
    warn "تخطي تثبيت Claude PC بناءً على طلبك"
else
    step "تثبيت Claude PC + Claude Code CLI"
    plogin "bash /opt/s25/src/install-claude-desktop.sh --mode '$CLAUDE_MODE'" \
        || warn "فشل تثبيت Claude PC"
fi

if [ "$WITH_WINDOWS" = 1 ]; then
    step "تثبيت طبقة ويندوز (Wine + box64 + DXVK)"
    warn "تنزيل ~1.5 غيغابايت وقد يأخذ وقتاً طويلاً"
    plogin "S25_ASSUME_YES=1 bash /opt/s25/src/install-windows-layer.sh" \
        || warn "فشل تثبيت طبقة ويندوز — راجع docs/WINDOWS.md"
fi

# ── 4. تثبيت أوامر التشغيل في Termux ───────────────────────────────────
step "تثبيت أوامر التشغيل في Termux"
install -Dm755 "$HERE/start-desktop.sh" "$PREFIX/bin/s25-desktop"
install -Dm755 "$HERE/stop-desktop.sh"  "$PREFIX/bin/s25-stop"
mkdir -p "$PREFIX/etc"
cat > "$PREFIX/etc/s25-desktop.conf" <<EOF
# إعدادات نظام S25 Desktop — عدّلها كما تشاء
S25_DISTRO=$DISTRO
# S25_GPU=auto        # auto | off  (off = رسوميات بالمعالج)
# S25_DPI=140         # كثافة النقاط داخل سطح المكتب
# S25_SCALE=1.4       # تكبير واجهة كروم/Claude
# TU_DEBUG=sysmem     # مطلوب لـ A830 (GMEM يسبب تعليق الـ GPU)
EOF
ok "s25-desktop و s25-stop جاهزان"

# اختصارات Termux:Widget (اختياري — تظهر كأيقونات على الشاشة الرئيسية)
if [ -d "$S25_DIR/termux/shortcuts" ]; then
    mkdir -p "$HOME/.shortcuts"
    for f in "$S25_DIR/termux/shortcuts/"*.sh; do
        [ -r "$f" ] || continue
        install -m700 "$f" "$HOME/.shortcuts/$(basename "$f")"
    done
    ok "اختصارات Termux:Widget في ~/.shortcuts"
fi

ok "اكتملت تهيئة الحاوية"
