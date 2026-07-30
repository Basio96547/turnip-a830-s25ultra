# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════
#  lib-multiarch.sh — تمكين مكتبات x86_64 داخل حاوية arm64 لاستخدامها مع box64
#  يُستدعى من install-windows-layer.sh
# ═══════════════════════════════════════════════════════════════════════

# install_box64 — تثبيت box64 (مترجم تعليمات x86_64 لحظياً)
install_box64() {
    if have box64; then
        ok "box64 مثبت مسبقاً"
        return 0
    fi
    apt_install curl ca-certificates gnupg
    if apt_available box64; then
        apt_install box64
    else
        log "إضافة مستودع box64…"
        curl -fsSL https://ryanfortner.github.io/box64-debs/KEY.gpg \
            | gpg --dearmor -o /usr/share/keyrings/box64-archive-keyring.gpg 2>/dev/null \
            || warn "تعذر تنزيل مفتاح المستودع"
        printf 'deb [signed-by=/usr/share/keyrings/box64-archive-keyring.gpg] https://ryanfortner.github.io/box64-debs/debian ./\n' \
            > /etc/apt/sources.list.d/box64.list
        apt_refresh
        apt_install_any box64-generic-arm box64
    fi
    have box64 || return 1
    ok "box64: $(box64 --version 2>&1 | head -1)"
}

# enable_amd64_multiarch — إضافة معمارية amd64 إلى apt
#
# الطريقة الصحيحة هي الأبسط: نضيف المعمارية فقط ولا نلمس مصادر التوزيعة.
# عندما لا يحدد المصدر حقل Architectures، يجلب apt فهارس كل المعماريات
# المُضافة عبر dpkg — فلا حاجة لمصدر منفصل.
#
# المصدر المنفصل كان يسبب فشلاً حقيقياً على trixie:
#   E: Conflicting values set for option Signed-By … debian-archive-keyring.gpg
#      != … debian-archive-keyring.pgp
# لأن اسم ملف المفاتيح تغيّر بين الإصدارات. لذلك نزيل أي أثر لتلك الطريقة.
enable_amd64_multiarch() {
    if dpkg --print-foreign-architectures 2>/dev/null | grep -qx amd64; then
        ok "معمارية amd64 مضافة مسبقاً"
    else
        dpkg --add-architecture amd64
        ok "أُضيفت معمارية amd64"
    fi

    # تنظيف آثار الطريقة القديمة (مصدر amd64 منفصل بمفتاح مختلف)
    if [ -f /etc/apt/sources.list.d/amd64.sources ]; then
        rm -f /etc/apt/sources.list.d/amd64.sources
        log "أُزيل مصدر amd64 المنفصل — كان يتعارض مع مفاتيح التوزيعة"
    fi

    # وإلغاء أي تقييد للمصادر بـ arm64 وحدها، حتى تُجلب فهارس amd64 من نفس المصدر
    local f
    for f in /etc/apt/sources.list.d/*.sources; do
        [ -r "$f" ] || continue
        if grep -qE '^Architectures:[[:space:]]*arm64[[:space:]]*$' "$f"; then
            sed -i -E '/^Architectures:[[:space:]]*arm64[[:space:]]*$/d' "$f"
            log "أُلغي تقييد $(basename "$f") بـ arm64"
        fi
    done
    if [ -f /etc/apt/sources.list ]; then
        sed -i 's/^deb \[arch=arm64\] /deb /' /etc/apt/sources.list
    fi

    apt_refresh
}

# install_amd64_runtime_libs — مكتبات x86_64 التي تحتاجها برامج ويندوز/كروم عبر box64
install_amd64_runtime_libs() {
    apt_install_soft \
        libc6:amd64 libstdc++6:amd64 libgcc-s1:amd64 \
        libglib2.0-0:amd64 libx11-6:amd64 libxext6:amd64 libxrender1:amd64 \
        libxrandr2:amd64 libxi6:amd64 libxcursor1:amd64 libxcomposite1:amd64 \
        libxdamage1:amd64 libxfixes3:amd64 libxinerama1:amd64 libxcb1:amd64 \
        libxkbcommon0:amd64 libfreetype6:amd64 libfontconfig1:amd64 \
        libgnutls30:amd64 libgnutls30t64:amd64 \
        libpng16-16:amd64 libpng16-16t64:amd64 libjpeg62-turbo:amd64 \
        libasound2:amd64 libasound2t64:amd64 libpulse0:amd64 \
        libvulkan1:amd64 libgl1:amd64 libglx-mesa0:amd64 libegl1:amd64 \
        libnss3:amd64 libnspr4:amd64 libdrm2:amd64 libgbm1:amd64 \
        libexpat1:amd64 libudev1:amd64 zlib1g:amd64 libbz2-1.0:amd64 \
        libsdl2-2.0-0:amd64 libusb-1.0-0:amd64 libodbc2:amd64
}
