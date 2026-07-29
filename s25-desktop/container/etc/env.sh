# shellcheck shell=sh
# ═══════════════════════════════════════════════════════════════════════
#  /opt/s25/etc/env.sh — بيئة نظام S25 Desktop داخل الحاوية
#
#  تُقرأ تلقائياً من كل جلسة (عبر /etc/profile.d/10-s25-desktop.sh)
#  ومن كل مُشغّل تطبيق في /opt/s25/bin.
#
#  المتغيرات القابلة للضبط من الخارج:
#    S25_GPU=auto|off     auto = استخدم Turnip إن توفر، off = رسوميات المعالج
#    S25_DPI=140          كثافة نقاط سطح المكتب
#    S25_SCALE=1.4        تكبير واجهة كروم / Claude PC
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

export S25_DPI="${S25_DPI:-140}"
export S25_SCALE="${S25_SCALE:-1.4}"
export S25_GPU="${S25_GPU:-auto}"

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
