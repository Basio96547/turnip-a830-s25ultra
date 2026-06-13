#!/usr/bin/env python3
"""
fix_a830_dev_info.py
────────────────────
يطبق خصائص disable_gmem و has_image_processing على freedreno_dev_info.h
لضمان أن Adreno 830v2 يستخدم sysmem فقط (GMEM يسبب GPU hangs).

يُستخدم هذا السكربت بعد تطبيق الباتشات إذا فشلت بسبب drift في الكود.
"""

import re
import sys

DEV_INFO_H = "src/freedreno/common/freedreno_dev_info.h"

def apply():
    with open(DEV_INFO_H, 'r') as f:
        content = f.read()

    modified = False

    # 1. Add disable_gmem + has_image_processing to props struct
    # Look for the end of the props struct (before the closing })
    props_end_pattern = r'(bool\s+has_salu_int_narrowing_quirk;\s*\n)(\s*\}\s*props;)'
    replacement = (
        r'\1'
        r'      /* Whether the device supports the image processing opcode */\n'
        r'      bool has_image_processing;\n'
        r'      /* If GMEM needs to be disabled for this GPU */\n'
        r'      bool disable_gmem;\n'
        r'\2'
    )

    if 'disable_gmem' not in content:
        new_content = re.sub(props_end_pattern, replacement, content)
        if new_content != content:
            content = new_content
            modified = True
            print("  ✓ أضيفت disable_gmem + has_image_processing إلى fd_dev_info.props")
        else:
            print("  ⚠ لم يتم العثور على نمط props struct — قد يكون الكود تغير")
            sys.exit(1)
    else:
        print("  ✓ disable_gmem موجود مسبقاً في fd_dev_info.h")

    with open(DEV_INFO_H, 'w') as f:
        f.write(content)

    if not modified:
        print("  (لم يتم إجراء تغييرات — كل شيء موجود)")

if __name__ == "__main__":
    apply()
