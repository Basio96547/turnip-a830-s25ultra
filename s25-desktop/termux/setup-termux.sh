#!/usr/bin/env bash
set -euo pipefail
# ═══════════════════════════════════════════════════════════════════════
#  setup-termux.sh — تهيئة جانب Termux (خادم X، صوت، proot)
# ═══════════════════════════════════════════════════════════════════════

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"

is_termux || die "يجب تشغيل هذا السكربت داخل Termux"

log "تحديث فهرس حزم Termux…"
retry 3 pkg update -y >/dev/null 2>&1 || warn "تعذر تحديث الفهرس بالكامل — المتابعة"

log "تفعيل مستودع x11-repo…"
retry 3 pkg install -y x11-repo >/dev/null 2>&1 || warn "x11-repo قد يكون مفعلاً مسبقاً"
retry 3 pkg update -y >/dev/null 2>&1 || true

log "تثبيت حزم Termux المطلوبة…"
TERMUX_PKGS=(
    proot-distro
    termux-x11-nightly
    pulseaudio
    termux-api
    termux-tools
    git curl wget tar unzip zip
    openssl
    nano
)
for p in "${TERMUX_PKGS[@]}"; do
    if pkg list-installed 2>/dev/null | grep -q "^$p/"; then
        ok "$p (مثبت)"
    elif retry 3 pkg install -y "$p" >/dev/null 2>&1; then
        ok "$p"
    else
        case "$p" in
            termux-x11-nightly)
                die "فشل تثبيت termux-x11-nightly.
تأكد من تفعيل x11-repo: pkg install x11-repo && pkg update" ;;
            proot-distro|pulseaudio)
                die "فشل تثبيت الحزمة الأساسية: $p" ;;
            *)  warn "تعذر تثبيت $p — غير حرج" ;;
        esac
    fi
done

# ── التحقق من تطبيق Termux:X11 المرافق ─────────────────────────────────
if have pm && pm list packages 2>/dev/null | grep -q 'com.termux.x11'; then
    ok "تطبيق Termux:X11 مثبت على الجهاز"
else
    warn "تطبيق Termux:X11 غير مثبت (مطلوب لعرض سطح المكتب)"
    cat <<'EOF'
    حمّل ملف APK باسم app-arm64-v8a-debug.apk من:
      https://github.com/termux/termux-x11/releases
    ثبّته، افتحه مرة واحدة، ثم ارجع إلى Termux.
EOF
fi

# ── وصول التخزين المشترك (للملفات والتنزيلات) ──────────────────────────
if [ ! -d "$HOME/storage" ] && have termux-setup-storage; then
    log "طلب صلاحية التخزين (اقبل النافذة التي تظهر)…"
    termux-setup-storage >/dev/null 2>&1 || warn "تعذر طلب صلاحية التخزين — يمكنك تشغيل termux-setup-storage لاحقاً"
fi

# ── السماح لتطبيق المُشغّل بتنفيذ الأوامر داخل Termux ───────────────────
# مطلوب لتطبيق S25 Desktop (s25-launcher) الذي يشغّل النظام من أيقونة على
# الشاشة الرئيسية عبر خدمة RUN_COMMAND.
TERMUX_PROPS="$HOME/.termux/termux.properties"
mkdir -p "$HOME/.termux"
if grep -qE '^\s*allow-external-apps\s*=\s*true' "$TERMUX_PROPS" 2>/dev/null; then
    ok "allow-external-apps مفعّل مسبقاً"
else
    # نزيل أي سطر معطّل/معلّق ثم نضيف السطر الصحيح
    if [ -f "$TERMUX_PROPS" ]; then
        sed -i '/allow-external-apps/d' "$TERMUX_PROPS"
    fi
    printf 'allow-external-apps=true\n' >> "$TERMUX_PROPS"
    have termux-reload-settings && termux-reload-settings >/dev/null 2>&1 || true
    ok "تم تفعيل allow-external-apps (لتطبيق المُشغّل)"
fi

# ── ملف إعدادات النظام ─────────────────────────────────────────────────
mkdir -p "$PREFIX/etc"
ok "جانب Termux جاهز"
