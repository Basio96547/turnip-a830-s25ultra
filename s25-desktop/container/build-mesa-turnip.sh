#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  build-mesa-turnip.sh
#  يبني Mesa لـ glibc/aarch64 داخل الحاوية:
#     • Turnip (Vulkan) بخلفية KGSL — نفس باتشات A830v2 المستخدمة لأندرويد
#     • Zink (OpenGL/GLES فوق Vulkan) — حتى تعمل تطبيقات سطح المكتب
#
#  ملاحظة مهمة: تعريف أندرويد (bionic) الموجود في هذا المستودع لا يعمل داخل
#  حاوية glibc، لذلك نبني نسخة glibc منفصلة هنا وتُثبّت في /opt/s25/mesa.
#
#  الاستخدام (داخل الحاوية كـ root):
#     bash /opt/s25/src/build-mesa-turnip.sh [خيارات]
#
#  الخيارات:
#     --prefix <dir>        مسار التثبيت (افتراضي /opt/s25/mesa)
#     --jobs <N>            مهام الترجمة (افتراضي: حسب المعالج/الذاكرة)
#     --mesa-ref <ref>      فرع/وسم Mesa (افتراضي main)
#     --from-tarball <p|url> تثبيت حزمة مبنية مسبقاً بدل البناء
#     --tarball-out <path>  إنتاج حزمة .tar.gz من الناتج (لاستخدام CI)
#     --work <dir>          مجلد البناء (افتراضي /opt/s25/build)
#     --keep-source         عدم حذف مصادر البناء بعد الانتهاء
#     --skip-patches        عدم تطبيق باتشات A8xx (لو صار الدعم رسمياً في Mesa)
# ═══════════════════════════════════════════════════════════════════════

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# يعمل في الحالتين: منسوخاً داخل الحاوية (/opt/s25/src) أو من مستودع مستنسخ
if [ -r "$SRC_DIR/lib/common.sh" ]; then
    # shellcheck source=/dev/null
    . "$SRC_DIR/lib/common.sh"
else
    # shellcheck source=../lib/common.sh
    . "$SRC_DIR/../lib/common.sh"
fi

PREFIX_DIR="/opt/s25/mesa"
WORK="/opt/s25/build"
MESA_REF="${MESA_REF:-main}"
MESA_REPO="https://gitlab.freedesktop.org/mesa/mesa.git"
LIBDRM_REPO="https://gitlab.freedesktop.org/mesa/drm.git"
LIBDRM_TAG="${LIBDRM_TAG:-libdrm-2.4.124}"
LIBDRM_MIN="2.4.121"
MESON_MIN="1.4.0"
JOBS=""
FROM_TARBALL=""
TARBALL_OUT=""
KEEP_SOURCE=0
SKIP_PATCHES=0

# مواضع الباتشات: داخل الحاوية (mesa-patches) أو في جذر المستودع
A830_PATCH=""
PY_DIR=""
for _c in "${PATCH_DIR:-}" "$SRC_DIR/mesa-patches" "$SRC_DIR/../../patches-a830"; do
    [ -n "$_c" ] || continue
    if [ -r "$_c/adreno_830v2.patch" ]; then A830_PATCH="$_c/adreno_830v2.patch"; break; fi
done
for _c in "${PATCH_DIR:-}" "$SRC_DIR/mesa-patches" "$SRC_DIR/../.."; do
    [ -n "$_c" ] || continue
    if [ -r "$_c/apply_a830_gpus.py" ]; then PY_DIR="$_c"; break; fi
done
unset _c

TU8_PATCH_URL="https://raw.githubusercontent.com/The412Banner/Banners-Turnip/A8xx/tu8_kgsl_26.patch"
GEN8_PATCH_URL="https://raw.githubusercontent.com/The412Banner/Banners-Turnip/A8xx/tu_gen8.patch"

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)        PREFIX_DIR="${2:?}"; shift 2 ;;
        --jobs)          JOBS="${2:?}"; shift 2 ;;
        --mesa-ref)      MESA_REF="${2:?}"; shift 2 ;;
        --from-tarball)  FROM_TARBALL="${2:?}"; shift 2 ;;
        --tarball-out)   TARBALL_OUT="${2:?}"; shift 2 ;;
        --work)          WORK="${2:?}"; shift 2 ;;
        --keep-source)   KEEP_SOURCE=1; shift ;;
        --skip-patches)  SKIP_PATCHES=1; shift ;;
        -h|--help)       sed -n '2,40p' "$0"; exit 0 ;;
        *) die "خيار غير معروف: $1" ;;
    esac
done

need_root
export DEBIAN_FRONTEND=noninteractive
[ -n "$JOBS" ] || JOBS="$(build_jobs)"

# ── مسار التثبيت من حزمة جاهزة ─────────────────────────────────────────
if [ -n "$FROM_TARBALL" ]; then
    step "تثبيت Mesa من حزمة جاهزة"
    TB="$FROM_TARBALL"
    case "$FROM_TARBALL" in
        http://*|https://*)
            apt_refresh >/dev/null 2>&1 || true
            have curl || apt_install curl
            TB="/tmp/mesa-prebuilt.tar.gz"
            log "تنزيل $FROM_TARBALL"
            retry 4 curl -fL "$FROM_TARBALL" -o "$TB" || die "فشل التنزيل"
            ;;
    esac
    [ -r "$TB" ] || die "الملف غير موجود: $TB"
    rm -rf "$PREFIX_DIR"
    mkdir -p "$PREFIX_DIR"
    # ندعم حزمة تحوي lib/ و share/ في الجذر، أو داخل مجلد واحد
    tar -xzf "$TB" -C "$PREFIX_DIR" --strip-components=0
    if [ ! -d "$PREFIX_DIR/lib" ] && [ -d "$PREFIX_DIR/mesa/lib" ]; then
        mv "$PREFIX_DIR/mesa/"* "$PREFIX_DIR/"
        rmdir "$PREFIX_DIR/mesa" 2>/dev/null || true
    fi
    [ -f "$PREFIX_DIR/lib/libvulkan_freedreno.so" ] || \
        die "الحزمة لا تحوي lib/libvulkan_freedreno.so"
    # ملفات ICD تحمل مسارات مطلقة — نصلحها لتطابق مسار التثبيت
    for icd in "$PREFIX_DIR"/share/vulkan/icd.d/*.json; do
        [ -r "$icd" ] || continue
        sed -i "s#\"library_path\": \"[^\"]*libvulkan_freedreno.so\"#\"library_path\": \"$PREFIX_DIR/lib/libvulkan_freedreno.so\"#" "$icd"
    done
    ok "تم تثبيت Mesa في $PREFIX_DIR"
    "$SRC_DIR/bin/s25-doctor" 2>/dev/null | sed -n '/الرسوميات/,/العرض/p' || true
    exit 0
fi

# ── 1. متطلبات البناء ──────────────────────────────────────────────────
step "1/6 تثبيت متطلبات بناء Mesa"
apt_refresh
apt_install build-essential pkg-config git curl ca-certificates patch \
    ninja-build bison flex python3 python3-pip python3-setuptools \
    python3-mako python3-yaml python3-packaging \
    libexpat1-dev zlib1g-dev libzstd-dev \
    libx11-dev libx11-xcb-dev libxext-dev libxfixes-dev libxdamage-dev \
    libxshmfence-dev libxxf86vm-dev libxrandr-dev libxcb1-dev \
    libxcb-dri2-0-dev libxcb-dri3-dev libxcb-glx0-dev libxcb-present-dev \
    libxcb-randr0-dev libxcb-shm0-dev libxcb-sync-dev libxcb-xfixes0-dev \
    libxcb-keysyms1-dev
apt_install_soft glslang-tools libelf-dev libwayland-dev python3-ply cmake \
    libxcb-dri2-0-dev libxrender-dev

# meson حديث (نسخ التوزيعة قديمة على bookworm)
MESON_VER="$(meson --version 2>/dev/null || echo 0)"
if ! version_ge "$MESON_VER" "$MESON_MIN"; then
    log "تثبيت meson حديث عبر pip (الموجود: $MESON_VER، المطلوب >= $MESON_MIN)"
    pip3 install --break-system-packages --upgrade meson >/dev/null 2>&1 || \
        pip3 install --upgrade meson >/dev/null 2>&1 || \
        die "فشل تثبيت meson"
    hash -r
fi
ok "meson $(meson --version)"
ok "مهام الترجمة: $JOBS"

mkdir -p "$WORK"
export PKG_CONFIG_PATH="$PREFIX_DIR/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$PREFIX_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# ── 2. libdrm حديث إن لزم ──────────────────────────────────────────────
step "2/6 التحقق من libdrm"
DRM_VER="$(pkg-config --modversion libdrm 2>/dev/null || echo 0)"
if version_ge "$DRM_VER" "$LIBDRM_MIN"; then
    ok "libdrm $DRM_VER (كافٍ)"
else
    log "libdrm $DRM_VER قديم — بناء $LIBDRM_TAG في $PREFIX_DIR"
    rm -rf "$WORK/drm"
    if ! retry 3 git clone --depth 1 -b "$LIBDRM_TAG" "$LIBDRM_REPO" "$WORK/drm"; then
        warn "الوسم $LIBDRM_TAG غير متوفر — استخدام الفرع الرئيسي"
        retry 3 git clone --depth 1 "$LIBDRM_REPO" "$WORK/drm" || die "فشل تنزيل libdrm"
    fi
    ( cd "$WORK/drm"
      meson setup build --prefix="$PREFIX_DIR" --libdir=lib --buildtype=release \
          -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled \
          -Dvmwgfx=disabled -Domap=disabled -Dexynos=disabled -Dtegra=disabled \
          -Dvc4=disabled -Detnaviv=disabled -Dfreedreno=enabled \
          -Dfreedreno-kgsl=true \
          -Dman-pages=disabled -Dtests=false >/dev/null
      ninja -C build -j "$JOBS" install >/dev/null )
    ok "libdrm $(PKG_CONFIG_PATH=$PREFIX_DIR/lib/pkgconfig pkg-config --modversion libdrm) في $PREFIX_DIR"
fi

# ── 3. مصادر Mesa ──────────────────────────────────────────────────────
step "3/6 تنزيل مصادر Mesa ($MESA_REF)"
MESA_SRC="$WORK/mesa"
if [ -d "$MESA_SRC/.git" ]; then
    log "إعادة تعيين المصادر الموجودة…"
    ( cd "$MESA_SRC"
      git checkout . >/dev/null 2>&1 || true
      git clean -fdq >/dev/null 2>&1 || true
      retry 3 git fetch --depth 1 origin "$MESA_REF" >/dev/null 2>&1 || true
      git checkout FETCH_HEAD >/dev/null 2>&1 || git checkout "$MESA_REF" >/dev/null 2>&1 || true )
else
    retry 3 git clone --depth 1 -b "$MESA_REF" "$MESA_REPO" "$MESA_SRC" || \
        die "فشل تنزيل Mesa (تحقق من الاتصال)"
fi
MESA_HASH="$(cd "$MESA_SRC" && git rev-parse --short HEAD)"
MESA_VER="$(tr -d '[:space:]' < "$MESA_SRC/VERSION" 2>/dev/null || echo "?")"
ok "Mesa $MESA_VER ($MESA_HASH)"

# ── 4. باتشات A830v2 ───────────────────────────────────────────────────
step "4/6 باتشات Adreno 830v2 (KGSL + sysmem)"
DEVICES_PY="src/freedreno/common/freedreno_devices.py"

# دعم A8xx صار مدموجاً في Mesa upstream. تطبيق الباتشات الخارجية فوقه يفسد
# الملفات (hunks معكوسة أو fuzz في المكان الخطأ) — لذلك نتخطاها عند اكتشاف
# الدعم الرسمي. GMEM يبقى معطلاً عبر TU_DEBUG=sysmem في بيئة التشغيل.
if [ "$SKIP_PATCHES" != 1 ] && grep -qE 'a8xx_gen1_a830|0x44050001' "$MESA_SRC/$DEVICES_PY" 2>/dev/null; then
    ok "Mesa يدعم Adreno 830 رسمياً (وُجد في $DEVICES_PY)"
    log "تخطي باتشات A8xx الخارجية — تطبيقها فوق الدعم الرسمي يُفسد المصادر"
    log "GMEM يبقى معطلاً عبر TU_DEBUG=sysmem وقت التشغيل"
    SKIP_PATCHES=1
fi

if [ "$SKIP_PATCHES" = 1 ]; then
    warn "البناء بدعم Mesa الرسمي بلا باتشات خارجية"
else
    cd "$MESA_SRC"
    for spec in "tu8_kgsl_26.patch|$TU8_PATCH_URL" "tu_gen8.patch|$GEN8_PATCH_URL"; do
        pname="${spec%%|*}"; purl="${spec##*|}"
        if [ ! -s "$WORK/$pname" ]; then
            retry 3 curl -fsSL "$purl" -o "$WORK/$pname" || warn "تعذر تنزيل $pname"
        fi
        if [ -s "$WORK/$pname" ]; then
            if patch -p1 -N --fuzz=4 < "$WORK/$pname" >"$WORK/$pname.log" 2>&1; then
                ok "$pname"
            else
                warn "$pname: بعض الأجزاء فشلت (قد تكون مدموجة في Mesa بالفعل)"
                head -5 "$WORK/$pname.log" | sed 's/^/    /'
            fi
        fi
    done

    if grep -q 'a8xx_gen1_a830' "$DEVICES_PY" 2>/dev/null || grep -q '0x44050001' "$DEVICES_PY" 2>/dev/null; then
        ok "دعم A830 موجود — تخطي adreno_830v2.patch"
    elif [ -n "$A830_PATCH" ]; then
        if patch -p1 -N --fuzz=4 < "$A830_PATCH" >"$WORK/a830.log" 2>&1; then
            ok "adreno_830v2.patch"
        else
            warn "adreno_830v2.patch: بعض الأجزاء فشلت"
            head -10 "$WORK/a830.log" | sed 's/^/    /'
        fi
    else
        warn "adreno_830v2.patch غير موجود"
    fi

    for py in apply_a830_gpus.py fix_a830_dev_info.py; do
        if [ -n "$PY_DIR" ] && [ -r "$PY_DIR/$py" ]; then
            log "تشغيل $py"
            python3 "$PY_DIR/$py" || warn "$py أبلغ عن مشكلة"
        fi
    done

    if ! python3 -c "compile(open('$DEVICES_PY').read(),'d','exec')" 2>/dev/null; then
        warn "الباتشات أفسدت $DEVICES_PY — استرجاع المصادر النظيفة والبناء بدعم Mesa الرسمي"
        git -C "$MESA_SRC" checkout -- . 2>/dev/null || true
        git -C "$MESA_SRC" clean -fdq 2>/dev/null || true
        python3 -c "compile(open('$DEVICES_PY').read(),'d','exec')" \
            || die "المصادر لا تزال معطوبة — امسح مجلد البناء وأعد المحاولة:
    sudo rm -rf $WORK/mesa"
        ok "تم استرجاع المصادر النظيفة"
    else
        ok "المصادر جاهزة للبناء"
    fi
fi

# ── 5. البناء ──────────────────────────────────────────────────────────
step "5/6 بناء Mesa (Turnip/KGSL + Zink) — قد يستغرق وقتاً طويلاً"
cd "$MESA_SRC"
BUILD_DIR="$MESA_SRC/build-s25"
export CFLAGS="${CFLAGS:--O2} -Wno-error"
export CXXFLAGS="${CXXFLAGS:--O2} -Wno-error"

MESON_ARGS=(
    --prefix="$PREFIX_DIR"
    --libdir=lib
    --buildtype=release
    -Dstrip=true
    -Dplatforms=x11
    -Dvulkan-drivers=freedreno
    -Dgallium-drivers=zink
    -Dfreedreno-kmds=kgsl
    -Dvulkan-beta=true
    -Dglx=dri
    -Degl=enabled
    -Dgles1=disabled
    -Dgles2=enabled
    -Dgbm=disabled
    -Dglvnd=disabled
    -Dllvm=disabled
    -Dvideo-codecs=
    -Dtools=
    -Dvalgrind=disabled
    -Dlibunwind=disabled
)

# meson قد يرفض خياراً بحسب نسخة Mesa أو المنصة (مثل gbm الذي يحتاج DRM/KMS،
# أو خيار أُهمل). بدل إسقاط البناء نعطّل الخيار المعني ونعيد المحاولة.
meson_args_disable() {  # meson_args_disable <اسم الميزة>
    local i val
    for i in "${!MESON_ARGS[@]}"; do
        case "${MESON_ARGS[$i]}" in
            "-D$1="*)
                val="${MESON_ARGS[$i]#*=}"
                # الخيارات من نوع feature فقط تقبل disabled؛ غيرها (قوائم/combo) نحذفه
                case "$val" in
                    enabled|auto|disabled|true|false) MESON_ARGS[$i]="-D$1=disabled" ;;
                    *) meson_args_drop "$1" ;;
                esac
                return 0 ;;
        esac
    done
    MESON_ARGS+=("-D$1=disabled")
}

meson_args_drop() {     # meson_args_drop <اسم الخيار>
    local i new=()
    for i in "${!MESON_ARGS[@]}"; do
        case "${MESON_ARGS[$i]}" in
            "-D$1="*) ;;
            *) new+=("${MESON_ARGS[$i]}") ;;
        esac
    done
    MESON_ARGS=("${new[@]}")
}

MESON_LOG="$WORK/meson-setup.log"
setup_ok=0
for attempt in 1 2 3 4; do
    rm -rf "$BUILD_DIR"
    if meson setup "$BUILD_DIR" "${MESON_ARGS[@]}" >"$MESON_LOG" 2>&1; then
        setup_ok=1
        break
    fi
    grep -E 'ERROR|Unknown option' "$MESON_LOG" | head -4 | sed 's/^/    /'
    feat="$(grep -oE 'Feature [a-z0-9_-]+ cannot be enabled' "$MESON_LOG" | head -1 | awk '{print $2}')"
    unknown="$(grep -oE 'Unknown options?: *"?[a-z0-9_-]+' "$MESON_LOG" | head -1 | sed 's/.*: *"*//')"
    if [ -n "$feat" ]; then
        warn "محاولة $attempt: meson يرفض تفعيل الميزة «$feat» — تعطيلها وإعادة المحاولة"
        meson_args_disable "$feat"
    elif [ -n "$unknown" ]; then
        warn "محاولة $attempt: الخيار «$unknown» غير معروف في هذه النسخة — إزالته وإعادة المحاولة"
        meson_args_drop "$unknown"
    else
        tail -25 "$MESON_LOG" | sed 's/^/    /'
        die "فشل meson setup — السجل الكامل: $MESON_LOG"
    fi
done
[ "$setup_ok" = 1 ] || die "فشل meson setup بعد عدة محاولات — السجل: $MESON_LOG"
grep -E '^(Project version|C compiler)' "$MESON_LOG" | head -2 | sed 's/^/  /' || true
ok "إعداد البناء جاهز"

if ! ninja -C "$BUILD_DIR" -j "$JOBS" 2>&1 | tail -30; then
    err "فشل البناء. جرّب تقليل المهام: --jobs 2"
    die "ninja فشل"
fi
ninja -C "$BUILD_DIR" install >/dev/null || die "فشل التثبيت"

# ── 6. تحقق + تنظيف ────────────────────────────────────────────────────
step "6/6 التحقق من الناتج"
[ -f "$PREFIX_DIR/lib/libvulkan_freedreno.so" ] || die "لم يتم بناء libvulkan_freedreno.so"
ok "libvulkan_freedreno.so ($(du -h "$PREFIX_DIR/lib/libvulkan_freedreno.so" | cut -f1))"

ICD="$(ls "$PREFIX_DIR"/share/vulkan/icd.d/freedreno_icd.*.json 2>/dev/null | head -1 || true)"
[ -n "$ICD" ] && ok "ICD: $ICD" || warn "لم يتم العثور على ملف ICD"

if ls "$PREFIX_DIR"/lib/dri/*zink* >/dev/null 2>&1 || [ -f "$PREFIX_DIR/lib/dri/libgallium_dri.so" ]; then
    ok "Zink (OpenGL فوق Vulkan) مثبت"
else
    warn "لم يتم العثور على تعريف Zink في $PREFIX_DIR/lib/dri"
fi

if [ -n "$TARBALL_OUT" ]; then
    log "إنشاء الحزمة: $TARBALL_OUT"
    mkdir -p "$(dirname "$TARBALL_OUT")"
    tar -czf "$TARBALL_OUT" -C "$PREFIX_DIR" lib share
    ok "$TARBALL_OUT ($(du -h "$TARBALL_OUT" | cut -f1))"
fi

if [ -e /dev/kgsl-3d0 ] && have vulkaninfo; then
    log "اختبار سريع لـ Vulkan…"
    if VK_DRIVER_FILES="$ICD" LD_LIBRARY_PATH="$PREFIX_DIR/lib" \
       timeout 90 vulkaninfo --summary 2>/dev/null | grep -m1 'deviceName'; then
        ok "Turnip يعمل"
    else
        warn "vulkaninfo لم يُبلغ عن جهاز — شغّل s25-doctor داخل جلسة سطح المكتب"
    fi
else
    warn "لا يوجد /dev/kgsl-3d0 هنا — سيتم التحقق عند تشغيل الجلسة"
fi

if [ "$KEEP_SOURCE" = 0 ]; then
    log "حذف مصادر البناء لتحرير المساحة (استخدم --keep-source للإبقاء عليها)"
    rm -rf "$MESA_SRC" "$WORK/drm"
fi

printf '\n'
ok "Mesa (Turnip A830 + Zink) مثبت في $PREFIX_DIR"
printf '  Mesa       : %s (%s)\n' "$MESA_VER" "$MESA_HASH"
printf '  الوضع      : sysmem فقط (TU_DEBUG=sysmem)\n'
printf '  OpenGL     : Zink فوق Vulkan\n\n'
