#!/bin/bash
set -euo pipefail
#
# ═══════════════════════════════════════════════════════════════════════
#  build-turnip-a830.sh
#  Turnip Vulkan Driver Builder for Adreno 830v2 (Galaxy S25 Ultra)
#
#  يبني libvulkan_freedreno.so من Mesa main + A8xx patches
#  يصدر ملف .zip جاهز للتثبيت في محاكيات Switch (Citron/Sudachi/Eden)
#
#  المتطلبات:
#   - Linux x86_64 (Ubuntu 22.04+ أو WSL2)
#   - Android NDK r29 (يُحمل تلقائياً)
#   - git, meson, ninja, patchelf, unzip, curl, flex, bison, glslang, zip
#
#  الاستخدام:
#   chmod +x build-turnip-a830.sh
#   ./build-turnip-a830.sh
# ═══════════════════════════════════════════════════════════════════════

# ── Configuration ──────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

BUILD_VERSION="${BUILD_VERSION:-custom}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$REPO_ROOT/turnip_workdir_a830"
NDK_VERSION="android-ndk-r29"
NDK_DIR="$WORKDIR/$NDK_VERSION"
NDK_BIN="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin"
SDK_VERSION="34"
MESA_REPO="https://gitlab.freedesktop.org/mesa/mesa"
MESA_DIR="mesa"
MESA_REF="${MESA_REF:-main}"

# A8xx patches from The412Banner/Banners-Turnip
TU8_PATCH_URL="https://raw.githubusercontent.com/The412Banner/Banners-Turnip/A8xx/tu8_kgsl_26.patch"
GEN8_PATCH_URL="https://raw.githubusercontent.com/The412Banner/Banners-Turnip/A8xx/tu_gen8.patch"

# ── Banner ─────────────────────────────────────────────────────────────
banner() {
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Turnip Vulkan Driver Builder — Adreno 830v2             ║"
    echo "║     Samsung Galaxy S25 Ultra | Snapdragon 8 Elite (SM8750)  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ── Check Dependencies ─────────────────────────────────────────────────
check_deps() {
    echo -e "${YELLOW}[1/6] التحقق من المتطلبات...${NC}"
    local missing=0
    local deps="git meson ninja patchelf unzip curl flex bison zip glslangValidator python3"

    for dep in $deps; do
        if command -v "$dep" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $dep"
        else
            echo -e "  ${RED}✗${NC} $dep — غير موجود"
            missing=1
        fi
    done

    # Check glslangValidator alternative names
    if ! command -v glslangValidator &>/dev/null && ! command -v glslang &>/dev/null; then
        echo -e "  ${RED}✗${NC} glslangValidator/glslang — غير موجود"
        missing=1
    else
        echo -e "  ${GREEN}✓${NC} glslang"
    fi

    if [ "$missing" -eq 1 ]; then
        echo -e "\n${RED}الرجاء تثبيت المتطلبات الناقصة:${NC}"
        echo "  sudo apt-get update"
        echo "  sudo apt-get install -y ninja-build patchelf unzip flex bison git python3-pip glslang-tools curl zip"
        echo "  pip3 install --break-system-packages meson mako"
        exit 1
    fi

    # Install mako if needed
    pip3 install --break-system-packages mako &>/dev/null 2>&1 || true
    echo -e "  ${GREEN}✓${NC} mako (Python module)"
    echo ""
}

# ── Prepare Work Directory ─────────────────────────────────────────────
prepare_workdir() {
    echo -e "${YELLOW}[2/6] تجهيز مجلد العمل...${NC}"

    mkdir -p "$WORKDIR"
    cd "$WORKDIR"

    # Download NDK if not present
    if [ ! -d "$NDK_DIR" ]; then
        echo "  تحميل Android NDK r29..."
        curl -sL "https://dl.google.com/android/repository/${NDK_VERSION}-linux.zip" \
            -o "${NDK_VERSION}-linux.zip"
        echo "  فك الضغط..."
        unzip -q "${NDK_VERSION}-linux.zip"
        rm "${NDK_VERSION}-linux.zip"
    else
        echo "  ${GREEN}✓${NC} NDK موجود مسبقاً"
    fi

    # Clone Mesa if not present, else reset
    if [ ! -d "$MESA_DIR/.git" ]; then
        echo "  تحميل مستودع Mesa (${MESA_REF})..."
        git clone --depth=1 -b "$MESA_REF" "$MESA_REPO" "$MESA_DIR"
    else
        echo "  ${GREEN}✓${NC} Mesa موجود مسبقاً — إعادة تعيين (${MESA_REF})..."
        cd "$MESA_DIR"
        git checkout .
        git fetch --depth=1 origin "$MESA_REF" 2>/dev/null || true
        git checkout "$MESA_REF" 2>/dev/null || git checkout main
        git pull --depth=1 origin "$MESA_REF" 2>/dev/null || true
        cd "$WORKDIR"
    fi

    echo ""
}

# ── Apply A8xx Patches ─────────────────────────────────────────────────
apply_patches() {
    echo -e "${YELLOW}[3/6] تطبيق باتشات A8xx لدعم Adreno 830...${NC}"

    cd "$WORKDIR/$MESA_DIR"

    # Download patches
    echo "  تحميل الباتشات..."
    curl -sL "$TU8_PATCH_URL" -o /tmp/tu8_kgsl_26.patch
    curl -sL "$GEN8_PATCH_URL" -o /tmp/tu_gen8.patch

    # Apply tu8_kgsl_26 patch (UBWC, disable_gmem, A8xx magic regs, A830 tuning)
    echo "  تطبيق tu8_kgsl_26.patch (UBWC + disable_gmem + A8xx regs + A830)..."
    if patch -p1 -N --fuzz=4 < /tmp/tu8_kgsl_26.patch 2>/tmp/patch_err.log; then
        echo -e "    ${GREEN}✓${NC} tu8_kgsl_26.patch تم بنجاح"
    else
        echo -e "    ${YELLOW}⚠${NC} بعض أجزاء الباتش فشلت (قد تكون مطبقة مسبقاً من upstream)"
        cat /tmp/patch_err.log | head -5
    fi

    # Apply tu_gen8 patch (additional gen8 fixes)
    echo "  تطبيق tu_gen8.patch (إصلاحات إضافية)..."
    if patch -p1 -N --fuzz=4 < /tmp/tu_gen8.patch 2>/tmp/patch_err2.log; then
        echo -e "    ${GREEN}✓${NC} tu_gen8.patch تم بنجاح"
    else
        echo -e "    ${YELLOW}⚠${NC} بعض أجزاء الباتش فشلت (قد تكون مطبقة مسبقاً)"
        cat /tmp/patch_err2.log | head -5
    fi

    echo "  تطبيق باتش Adreno 830v2 المخصص..."
    if grep -q "a8xx_gen1_a830" src/freedreno/common/freedreno_devices.py 2>/dev/null; then
        echo -e "    ${YELLOW}⚠${NC} a8xx_gen1_a830 موجود مسبقاً — تخطي adreno_830v2.patch"
    elif grep -q "0x44050001" src/freedreno/common/freedreno_devices.py 2>/dev/null; then
        echo -e "    ${YELLOW}⚠${NC} 0x44050001 موجود مسبقاً (tu8_kgsl_26) — تخطي adreno_830v2.patch"
    elif patch -p1 -N --fuzz=4 < "$REPO_ROOT/patches-a830/adreno_830v2.patch" 2>/tmp/patch_a830.log; then
        echo -e "    ${GREEN}✓${NC} adreno_830v2.patch تم بنجاح"
    else
        echo -e "    ${YELLOW}⚠${NC} بعض أجزاء الباتش فشلت"
        cat /tmp/patch_a830.log | head -10
    fi

    echo "  تشغيل apply_a830_gpus.py..."
    python3 "$REPO_ROOT/apply_a830_gpus.py"

    echo "  تشغيل fix_a830_dev_info.py..."
    python3 "$REPO_ROOT/fix_a830_dev_info.py"

    # Ensure freedreno_devices.py is syntactically valid
    if ! python3 -c "compile(open('src/freedreno/common/freedreno_devices.py').read(),'f','exec')"; then
        echo -e "    ${RED}✗${NC} freedreno_devices.py syntax error — aborting build"
        exit 1
    fi
    echo -e "    ${GREEN}✓${NC} freedreno_devices.py صحيح نحوياً"

    # Preventive fixes for NDK r29
    echo "  إصلاحات توافق NDK r29..."
    sed -i 's/typedef const native_handle_t\* buffer_handle_t;/typedef void\* buffer_handle_t;/g' \
        include/android_stub/cutils/native_handle.h 2>/dev/null || true
    sed -i 's/, hnd->handle/, (void \*)hnd->handle/g' \
        src/util/u_gralloc/u_gralloc_fallback.c 2>/dev/null || true
    sed -i -E 's/([a-z_]+)->handle->/((const native_handle_t *)\1->handle)->/g' \
        src/vulkan/runtime/vk_android.c 2>/dev/null || true

    cd "$WORKDIR"
    echo ""
}

# ── Build ───────────────────────────────────────────────────────────────
build_driver() {
    echo -e "${YELLOW}[4/6] بناء libvulkan_freedreno.so...${NC}"

    cd "$WORKDIR/$MESA_DIR"

    # Setup symlinks
    mkdir -p "$WORKDIR/bin"
    ln -sf "$NDK_BIN/clang" "$WORKDIR/bin/cc"
    ln -sf "$NDK_BIN/clang++" "$WORKDIR/bin/c++"

    export PATH="$WORKDIR/bin:$NDK_BIN:$PATH"
    export CC=clang
    export CXX=clang++
    export AR=llvm-ar
    export RANLIB=llvm-ranlib
    export STRIP=llvm-strip
    export OBJDUMP=llvm-objdump
    export OBJCOPY=llvm-objcopy
    export LDFLAGS="-fuse-ld=lld"
    export CFLAGS="-D__ANDROID__ -Wno-error -Wno-deprecated-declarations -Wno-incompatible-pointer-types-discards-qualifiers -Wno-incompatible-pointer-types"
    export CXXFLAGS="-D__ANDROID__ -Wno-error -Wno-deprecated-declarations -Wno-incompatible-pointer-types-discards-qualifiers -Wno-incompatible-pointer-types"

    # Get git hash for versioning
    GITHASH=$(git rev-parse --short HEAD)

    # Cross-compilation file for aarch64 Android
    cat <<EOF > "$WORKDIR/android-aarch64.txt"
[binaries]
ar = '$NDK_BIN/llvm-ar'
c = ['$NDK_BIN/aarch64-linux-android${SDK_VERSION}-clang']
cpp = ['$NDK_BIN/aarch64-linux-android${SDK_VERSION}-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = '$NDK_BIN/ld.lld'
cpp_ld = '$NDK_BIN/ld.lld'
strip = '$NDK_BIN/llvm-strip'
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=$NDK_BIN/pkg-config', '/usr/bin/pkg-config']
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

    # Native compilation file
    cat <<EOF > "$WORKDIR/native.txt"
[build_machine]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
c_ld = 'ld.lld'
cpp_ld = 'ld.lld'
system = 'linux'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

    echo "  إعداد Meson build..."
    meson setup build-android-aarch64 \
        --cross-file "$WORKDIR/android-aarch64.txt" \
        --native-file "$WORKDIR/native.txt" \
        --prefix /tmp/turnip-a830 \
        -Dbuildtype=release \
        -Dstrip=true \
        -Dplatforms=android \
        -Dvideo-codecs= \
        -Dplatform-sdk-version="$SDK_VERSION" \
        -Dandroid-stub=true \
        -Dgallium-drivers= \
        -Dvulkan-drivers=freedreno \
        -Dvulkan-beta=true \
        -Dfreedreno-kmds=kgsl \
        -Degl=disabled \
        -Dandroid-libbacktrace=disabled \
        --reconfigure 2>&1 | tail -3

    echo "  بناء بالمترجم (ninja)..."
    ninja -C build-android-aarch64 install 2>&1 | tee "$WORKDIR/ninja.log"
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo -e "${RED}  ✗ فشل ninja!${NC}"
        tail -50 "$WORKDIR/ninja.log"
        exit 1
    fi

    if [ ! -f /tmp/turnip-a830/lib/libvulkan_freedreno.so ]; then
        echo -e "${RED}  ✗ فشل البناء! لم يتم العثور على libvulkan_freedreno.so${NC}"
        exit 1
    fi

    echo -e "  ${GREEN}✓${NC} تم بناء libvulkan_freedreno.so بنجاح"
    cd "$WORKDIR"
    echo ""
}

# ── Package ─────────────────────────────────────────────────────────────
package_driver() {
    echo -e "${YELLOW}[5/6] تجهيز الحزمة...${NC}"

    cd /tmp/turnip-a830/lib

    local githash=$(cd "$WORKDIR/$MESA_DIR" && git rev-parse --short HEAD)
    local vk_header="$WORKDIR/$MESA_DIR/include/vulkan/vulkan_core.h"
    local vk_patch=$(grep '^#define VK_HEADER_VERSION ' "$vk_header" | awk '{print $3}')
    local driver_ver="Vulkan 1.3.${vk_patch}"

    # Create meta.json for adrenotools compatibility
    cat > meta.json <<EOF
{
  "schemaVersion": 1,
  "name": "Turnip A830v2 - Galaxy S25 Ultra",
  "description": "Turnip Vulkan driver for Adreno 830v2 (Snapdragon 8 Elite / SM8750). Built with sysmem-only (GMEM disabled). Supports Samsung Galaxy S25 Ultra.",
  "author": "Custom Build",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "${driver_ver}",
  "minApi": 28,
  "files": [
    {
      "source": "libvulkan_freedreno.so",
      "target": "libvulkan_freedreno.so"
    }
  ]
}
EOF

    local zip_name="Turnip-A830v2-V${BUILD_VERSION}-${githash}.zip"
    zip -q "/tmp/${zip_name}" libvulkan_freedreno.so meta.json

    # Copy to workdir
    cp "/tmp/${zip_name}" "$WORKDIR/"

    echo -e "  ${GREEN}✓${NC} الحزمة: ${zip_name}"
    echo -e "  ${GREEN}✓${NC} نسخة Vulkan: ${driver_ver}"
    echo -e "  ${GREEN}✓${NC} مكان الملف: ${WORKDIR}/${zip_name}"
    echo ""
}

# ── Summary ─────────────────────────────────────────────────────────────
print_summary() {
    local githash=$(cd "$WORKDIR/$MESA_DIR" && git rev-parse --short HEAD)
    local mesa_ver=$(cat "$WORKDIR/$MESA_DIR/VERSION" 2>/dev/null | sed 's/-devel.*//' | tr -d '[:space:]' || echo "unknown")
    local so_size=$(stat --printf="%s" /tmp/turnip-a830/lib/libvulkan_freedreno.so 2>/dev/null || echo "?")
    local so_size_mb=$(echo "scale=2; $so_size / 1048576" | bc 2>/dev/null || echo "?")

    echo -e "${GREEN}[6/6] ✓ تم البناء بنجاح!${NC}"
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   ملخص البناء                              ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    printf "║  Mesa Version     : %-40s ║\n" "$mesa_ver"
    printf "║  Git Commit       : %-40s ║\n" "$githash"
    printf "║  Build Version    : %-40s ║\n" "$BUILD_VERSION"
    printf "║  SO Size          : %-40s ║\n" "${so_size_mb} MB"
    printf "║  Target GPU       : %-40s ║\n" "Adreno 830v2 (0x44050001)"
    printf "║  Mode             : %-40s ║\n" "sysmem-only (GMEM disabled)"
    printf "║  Output           : %-40s ║\n" "$WORKDIR/Turnip-A830v2-*.zip"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${YELLOW}⚠️  ملاحظات مهمة:${NC}"
    echo "  • استخدم TU_DEBUG=sysmem في إعدادات المحاكي (GMEM يسبب GPU hangs)"
    echo "  • التعريف تجريبي — A8xx support لا يزال قيد التطوير في Mesa"
    echo "  • للحصول على أفضل أداء: فعّل Async Shaders + Disk Shader Cache"
    echo "  • للمشاكل: جرب TU_DEBUG=nolrz,sysmem"
    echo ""
}

# ── Main ────────────────────────────────────────────────────────────────
main() {
    banner
    check_deps
    prepare_workdir
    apply_patches
    build_driver
    package_driver
    print_summary
}

main "$@"
