# shellcheck shell=sh
# ═══════════════════════════════════════════════════════════════════════
#  /opt/s25/etc/env.sh — بيئة نظام S25 Desktop داخل الحاوية
#
#  تُقرأ تلقائياً من كل جلسة (عبر /etc/profile.d/10-s25-desktop.sh)
#  ومن كل مُشغّل تطبيق في /opt/s25/bin.
#
#  المتغيرات القابلة للضبط من الخارج:
#    S25_GPU=auto|off     auto = استخدم Turnip إن توفر، off = رسوميات المعالج
#    S25_DPI=240          كثافة نقاط سطح المكتب (مبدئياً: محسوبة من عرض الشاشة)
#    S25_SCALE=2.5        تكبير واجهة كروم / Claude PC (مبدئياً: محسوب)
#    TU_DEBUG=sysmem      إلزامي على A830 (GMEM يسبب تعليق الـ GPU)
# ═══════════════════════════════════════════════════════════════════════

S25_PREFIX=/opt/s25
S25_MESA_DIR="${S25_MESA_DIR:-$S25_PREFIX/mesa}"

export DISPLAY="${DISPLAY:-:0}"
export PULSE_SERVER="${PULSE_SERVER:-tcp:127.0.0.1:4713}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-$(id -u)}"
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
    chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
fi

export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-XFCE}"
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export LANG="${LANG:-en_US.UTF-8}"

# كثافة النقاط والتكبير: يُحسبان من عرض شاشة X الفعلي بدل رقم ثابت، فيصلح
# النظام لأي وضع دقة يختاره المستخدم من تطبيق Termux:X11 (native أو scaled).
# المرجع: كل 480 بكسل عرضاً = ضعف واحد ← 1440 بكسل = ثلاثة أضعاف.
_s25_w=0
if command -v xdpyinfo >/dev/null 2>&1; then
    _s25_w="$(xdpyinfo 2>/dev/null | awk '/dimensions:/ {split($2,a,"x"); print a[1]; exit}')"
fi
case "$_s25_w" in ''|*[!0-9]*) _s25_w=0 ;; esac

if [ "$_s25_w" -ge 480 ]; then
    _s25_dpi=$(( 96 * _s25_w / 480 ))
    [ "$_s25_dpi" -lt 120 ] && _s25_dpi=120
    [ "$_s25_dpi" -gt 384 ] && _s25_dpi=384
    # تكبير البرامج بخطوة نصفية: 1.0 · 1.5 · 2.0 · 2.5 · 3.0
    _s25_scale="$(( _s25_w * 2 / 480 ))"
    [ "$_s25_scale" -lt 2 ] && _s25_scale=2
    [ "$_s25_scale" -gt 8 ] && _s25_scale=8
    case "$_s25_scale" in
        2) _s25_scale=1.0 ;; 3) _s25_scale=1.5 ;; 4) _s25_scale=2.0 ;;
        5) _s25_scale=2.5 ;; 6) _s25_scale=3.0 ;; 7) _s25_scale=3.5 ;;
        *) _s25_scale=4.0 ;;
    esac
else
    _s25_dpi=240
    _s25_scale=2.5
fi

export S25_DPI="${S25_DPI:-$_s25_dpi}"
export S25_SCALE="${S25_SCALE:-$_s25_scale}"
export S25_GPU="${S25_GPU:-auto}"
unset _s25_w _s25_dpi _s25_scale

# ── اكتشاف تعريف Turnip المبني لـ glibc ────────────────────────────────
_s25_icd=''
for _s25_f in "$S25_MESA_DIR"/share/vulkan/icd.d/freedreno_icd.*.json; do
    if [ -r "$_s25_f" ]; then _s25_icd="$_s25_f"; break; fi
done

if [ "$S25_GPU" != "off" ] && [ -n "$_s25_icd" ] && [ -e /dev/kgsl-3d0 ]; then
    # ── تسريع الأجهزة: Turnip (Vulkan) + Zink (OpenGL فوق Vulkan) ──
    export S25_GPU_ACTIVE=turnip
    export LD_LIBRARY_PATH="$S25_MESA_DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export LIBGL_DRIVERS_PATH="$S25_MESA_DIR/lib/dri"
    export VK_DRIVER_FILES="$_s25_icd"
    export VK_ICD_FILENAMES="$_s25_icd"
    export __EGL_VENDOR_LIBRARY_DIRS="$S25_MESA_DIR/share/glvnd/egl_vendor.d"

    # A830: العرض من الذاكرة الرئيسية فقط — GMEM يسبب تعليق الـ GPU
    export TU_DEBUG="${TU_DEBUG:-sysmem}"

    export MESA_LOADER_DRIVER_OVERRIDE=zink
    export GALLIUM_DRIVER=zink
    export ZINK_DESCRIPTORS="${ZINK_DESCRIPTORS:-lazy}"
    # Termux:X11 لا يوفر DRI3 — kopper يحتاج المسار القديم
    export LIBGL_KOPPER_DRI2=1
    export MESA_GL_VERSION_OVERRIDE="${MESA_GL_VERSION_OVERRIDE:-4.6COMPAT}"
    export MESA_GLSL_VERSION_OVERRIDE="${MESA_GLSL_VERSION_OVERRIDE:-460}"
    export MESA_SHADER_CACHE_DIR="${MESA_SHADER_CACHE_DIR:-$HOME/.cache/mesa_shader_cache}"
    export MESA_SHADER_CACHE_MAX_SIZE="${MESA_SHADER_CACHE_MAX_SIZE:-2G}"
    export vblank_mode=0
else
    # ── احتياطي: رسوميات على المعالج (llvmpipe/lavapipe من حزم التوزيعة) ──
    export S25_GPU_ACTIVE=software
    export LIBGL_ALWAYS_SOFTWARE=1
    unset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER VK_DRIVER_FILES VK_ICD_FILENAMES
fi

unset _s25_f _s25_icd
