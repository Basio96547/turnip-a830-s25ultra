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
trap_errors

DISTRO="debian"
JOBS=""
MESA_REF="main"
MESA_TARBALL=""
SKIP_MESA=0
SKIP_WINDOWS=0
PAYLOAD_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --distro)          DISTRO="${2:?}"; shift 2 ;;
        --jobs)            JOBS="${2:?}"; shift 2 ;;
        --mesa-ref)        MESA_REF="${2:?}"; shift 2 ;;
        --mesa-tarball)    MESA_TARBALL="${2:?}"; shift 2 ;;
        --skip-mesa)       SKIP_MESA=1; shift ;;
        --skip-windows)    SKIP_WINDOWS=1; shift ;;
        --payload-only)    PAYLOAD_ONLY=1; shift ;;
        *) die "خيار غير معروف: $1" ;;
    esac
done

is_termux || die "يجب تشغيل هذا السكربت داخل Termux"
have proot-distro || die "proot-distro غير مثبت — شغّل setup-termux.sh أولاً"

ROOTFS="$PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"

# ── 1. تثبيت التوزيعة ──────────────────────────────────────────────────
# لا نعتمد على وجود المجلد: مسار نظام الملفات يختلف بين نسخ proot-distro.
# الفحص الحقيقي هو أن الدخول إلى الحاوية ينجح.
container_ok() {
    proot-distro login "$DISTRO" -- /bin/true >/dev/null 2>&1
}

# يعيد: 0 نجح · 2 موجودة مسبقاً (وقد تكون معطوبة) · 1 فشل حقيقي
try_install_container() {
    local out
    if out="$(proot-distro install "$DISTRO" 2>&1)"; then
        return 0
    fi
    printf '%s\n' "$out" | tail -4 | sed 's/^/    /'
    case "$out" in
        *"already exists"*) return 2 ;;
        *) return 1 ;;
    esac
}

if container_ok; then
    ok "حاوية $DISTRO موجودة وتعمل"
else
    log "تنزيل وتثبيت حاوية $DISTRO (قد يستغرق عدة دقائق)…"
    rc=0
    try_install_container || rc=$?
    if [ "$rc" = 2 ]; then
        warn "proot-distro يقول إن الحاوية موجودة، لكن الدخول إليها يفشل — أي أنها ناقصة"
        if [ "${S25_RESET_CONTAINER:-0}" = 1 ] || confirm "إعادة تهيئة الحاوية $DISTRO؟ (يحذف محتواها)"; then
            proot-distro reset "$DISTRO" >/dev/null 2>&1 || proot-distro remove "$DISTRO" >/dev/null 2>&1 || true
            retry 2 proot-distro install "$DISTRO" || die "فشل تثبيت الحاوية $DISTRO"
        else
            die "أعد التهيئة يدوياً ثم شغّل المُثبّت من جديد:
    proot-distro reset $DISTRO"
        fi
    elif [ "$rc" = 1 ]; then
        # فشل شبكة أو تنزيل — يستحق إعادة المحاولة
        retry 2 proot-distro install "$DISTRO" || die "فشل تثبيت الحاوية $DISTRO"
    fi
    container_ok || die "الحاوية $DISTRO لا تعمل بعد التثبيت.
جرّب:  proot-distro reset $DISTRO  ثم أعد تشغيل المُثبّت"
    ok "تم تثبيت $DISTRO"
fi

# جذر نظام الملفات: التخطيط يختلف بين نسخ proot-distro
#   قديم : installed-rootfs/<alias>
#   حديث : containers/<alias>/rootfs   (أو containers/<alias>)
# نتعرّف عليه بوجود etc/os-release لا بالتخمين.
detect_rootfs() {
    local base="$PREFIX/var/lib/proot-distro" cand
    for cand in \
        "$base/installed-rootfs/$DISTRO" \
        "$base/containers/$DISTRO/rootfs" \
        "$base/containers/$DISTRO/root" \
        "$base/containers/$DISTRO"; do
        if [ -r "$cand/etc/os-release" ]; then printf '%s' "$cand"; return 0; fi
    done
    cand="$(find "$base" -maxdepth 6 -type f -name os-release -path "*$DISTRO*" 2>/dev/null | head -1)"
    if [ -n "$cand" ]; then printf '%s' "$(dirname "$(dirname "$cand")")"; return 0; fi
    return 1
}

ROOTFS="$(detect_rootfs)" || die "لم يتم العثور على جذر نظام ملفات الحاوية داخل
    $PREFIX/var/lib/proot-distro
جرّب: proot-distro reset $DISTRO ثم أعد تشغيل المُثبّت"
log "نظام ملفات الحاوية: $ROOTFS"

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
BIND_SDCARD=0
if [ -d /sdcard ] && ! proot-distro login "$DISTRO" -- test -d /mnt/sdcard >/dev/null 2>&1; then
    # النسخ الحديثة تربط التخزين تلقائياً — لا نكرّر الربط لتجنّب تحذير التعارض
    BINDS+=(--bind "/sdcard:/mnt/sdcard")
    BIND_SDCARD=1
fi

# plogin <أمر داخل الحاوية>
plogin() {
    proot-distro login "$DISTRO" --shared-tmp "${BINDS[@]}" -- /bin/bash -c "$1"
}

# تحقق أن ما نسخناه يُرى فعلاً من داخل الحاوية (يكشف مسار جذر خاطئ فوراً)
if ! plogin "test -r /opt/s25/src/bootstrap-debian.sh" >/dev/null 2>&1; then
    die "الحمولة نُسخت إلى $PAYLOAD لكنها غير مرئية داخل الحاوية.
هذا يعني أن جذر نظام الملفات المكتشف غير صحيح. أبلغ عن المسار التالي:
    $ROOTFS"
fi
ok "الحمولة مرئية داخل الحاوية"

if [ "$PAYLOAD_ONLY" = 1 ]; then
    ok "تم تحديث سكربتات النظام داخل الحاوية (/opt/s25/src)"
    exit 0
fi

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

if [ "$SKIP_WINDOWS" = 1 ]; then
    warn "تخطي طبقة ويندوز بناءً على طلبك — لن تعمل ملفات .exe"
else
    step "تثبيت طبقة ويندوز (Wine + box64 + DXVK)"
    warn "تنزيل ~1.5 غيغابايت وقد يأخذ 20–40 دقيقة"
    plogin "S25_ASSUME_YES=1 bash /opt/s25/src/install-windows-layer.sh" \
        || warn "فشل تثبيت طبقة ويندوز — راجع docs/WINDOWS.md"
fi

# ── 4. تثبيت أوامر التشغيل في Termux ───────────────────────────────────
step "تثبيت أوامر التشغيل في Termux"
install -Dm755 "$HERE/start-desktop.sh"    "$PREFIX/bin/s25-desktop"
install -Dm755 "$HERE/stop-desktop.sh"     "$PREFIX/bin/s25-stop"
install -Dm755 "$HERE/update-container.sh" "$PREFIX/bin/s25-update"
mkdir -p "$PREFIX/etc"
cat > "$PREFIX/etc/s25-desktop.conf" <<EOF
# إعدادات نظام S25 Desktop — عدّلها كما تشاء
S25_DISTRO=$DISTRO
S25_REPO=$REPO_ROOT
S25_ROOTFS=$ROOTFS
S25_BIND_SDCARD=$BIND_SDCARD
# S25_GPU=auto        # auto | off  (off = رسوميات بالمعالج)
# S25_DPI=140         # كثافة النقاط داخل سطح المكتب
# S25_SCALE=1.4       # تكبير واجهة البرامج
# TU_DEBUG=sysmem     # مطلوب لـ A830 (GMEM يسبب تعليق الـ GPU)
EOF
ok "s25-desktop · s25-stop · s25-update جاهزة"


step "التشخيص النهائي"
plogin "/opt/s25/bin/s25-doctor" 2>&1 | sed -n '/الرسوميات/,$p' | head -40 || \
    warn "تعذر تشغيل s25-doctor — شغّله يدوياً: s25-desktop shell ثم s25-doctor"

ok "اكتملت تهيئة الحاوية"
