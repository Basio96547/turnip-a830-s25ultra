#!/usr/bin/env bash
# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════
#  common.sh — دوال مشتركة لسكربتات نظام سطح المكتب على Galaxy S25 Ultra
#  تُستخدم من سكربتات Termux ومن السكربتات التي تعمل داخل الحاوية
# ═══════════════════════════════════════════════════════════════════════

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_G=$'\033[0;32m'; C_Y=$'\033[0;33m'; C_R=$'\033[0;31m'
    C_B=$'\033[0;36m'; C_N=$'\033[0m'
else
    C_G=''; C_Y=''; C_R=''; C_B=''; C_N=''
fi

log()  { printf '%s\n' "${C_B}▶${C_N} $*"; }
ok()   { printf '%s\n' "${C_G}✓${C_N} $*"; }
warn() { printf '%s\n' "${C_Y}⚠${C_N} $*" >&2; }
err()  { printf '%s\n' "${C_R}✗${C_N} $*" >&2; }
die()  { err "$*"; exit 1; }
step() { printf '\n%s\n' "${C_G}═══ $* ═══${C_N}"; }

have() { command -v "$1" >/dev/null 2>&1; }

is_termux() {
    [ -n "${TERMUX_VERSION:-}" ] || [ -d /data/data/com.termux/files/usr/bin ]
}

is_arm64() { [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; }

need_root() {
    [ "$(id -u)" = "0" ] || die "هذا السكربت يحتاج صلاحيات root داخل الحاوية"
}

# retry <attempts> <command...> — إعادة المحاولة مع تأخير تصاعدي (2s,4s,8s,16s)
retry() {
    local attempts="$1"; shift
    local i=1 delay=2
    while true; do
        if "$@"; then return 0; fi
        if [ "$i" -ge "$attempts" ]; then
            err "فشل نهائياً بعد $attempts محاولات: $1"
            return 1
        fi
        warn "فشل ($i/$attempts) — إعادة المحاولة بعد ${delay}s"
        sleep "$delay"
        delay=$((delay * 2))
        i=$((i + 1))
    done
}

# ── مساعدات apt (داخل الحاوية) ─────────────────────────────────────────
apt_refresh() {
    export DEBIAN_FRONTEND=noninteractive
    retry 4 apt-get update -qq
}

apt_available() {
    apt-cache policy "$1" 2>/dev/null | grep -q 'Candidate: [^(]'
}

# apt_install <حزم...> — تثبيت إلزامي
apt_install() {
    export DEBIAN_FRONTEND=noninteractive
    retry 3 apt-get install -y -qq --no-install-recommends "$@"
}

# apt_install_soft <حزم...> — تثبيت كل حزمة متوفرة، وتجاهل غير المتوفر
apt_install_soft() {
    export DEBIAN_FRONTEND=noninteractive
    local pkgs=() p
    for p in "$@"; do
        if apt_available "$p"; then pkgs+=("$p"); fi
    done
    if [ "${#pkgs[@]}" -eq 0 ]; then
        warn "لا توجد حزمة متوفرة من: $*"
        return 0
    fi
    retry 3 apt-get install -y -qq --no-install-recommends "${pkgs[@]}" || \
        warn "فشل تثبيت بعض الحزم: ${pkgs[*]}"
}

# apt_install_any <بديل1> <بديل2> ... — يثبّت أول بديل متوفر فقط
# مفيد لأسماء الحزم التي تغيرت بين bookworm و trixie (مثل libgtk-3-0 / libgtk-3-0t64)
apt_install_any() {
    export DEBIAN_FRONTEND=noninteractive
    local p
    for p in "$@"; do
        if apt_available "$p"; then
            retry 3 apt-get install -y -qq --no-install-recommends "$p" && return 0
        fi
    done
    warn "لم يتوفر أي بديل من: $*"
    return 0
}

# ── مساعدات عامة ───────────────────────────────────────────────────────

# عدد المهام الموازية المناسب للبناء على الجهاز (محدود بالذاكرة)
build_jobs() {
    local cpus mem_kb by_mem j
    cpus="$(nproc 2>/dev/null || echo 4)"
    mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 4194304)"
    # ~1.5 غيغابايت لكل مهمة ترجمة كحد أقصى
    by_mem=$(( mem_kb / 1572864 ))
    [ "$by_mem" -lt 1 ] && by_mem=1
    j="$cpus"
    [ "$j" -gt "$by_mem" ] && j="$by_mem"
    [ "$j" -gt 8 ] && j=8
    echo "$j"
}

# version_ge <a> <b> — هل a >= b (مقارنة نسخ رقمية)
version_ge() {
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

confirm() {
    local prompt="${1:-متابعة؟}"
    if [ "${S25_ASSUME_YES:-0}" = "1" ] || [ ! -t 0 ]; then return 0; fi
    printf '%s [y/N] ' "$prompt"
    local a; read -r a
    case "$a" in [yY]*) return 0 ;; *) return 1 ;; esac
}

banner() {
    printf '%s' "$C_G"
    cat <<'EOF'
╔══════════════════════════════════════════════════════════════════╗
║   S25 Desktop — نظام لينكس + Claude PC + Chrome على الجوال       ║
║   Galaxy S25 Ultra · Snapdragon 8 Elite · Adreno 830v2 (Turnip)  ║
╚══════════════════════════════════════════════════════════════════╝
EOF
    printf '%s\n' "$C_N"
}
