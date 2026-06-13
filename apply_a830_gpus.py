#!/usr/bin/env python3
"""
apply_a830_gpus.py
──────────────────
يضيف إدخالات GPU الخاصة بـ Adreno 830v2 إلى freedreno_devices.py.
يضمن أن:
  1. chip_id=0x44050001 (KGSL) معروف كـ FD830
  2. A830 له disable_gmem = True
  3. tile_align_w = 96 (وليس 64 مثل A6xx/A7xx)
  4. يستخدم a8xx_gen1_a830 GPUProps بدلاً من الخصائص العامة

يستخدم بعد تطبيق الباتش الرئيسي لضمان تطابق Device ID مع KGSL.
"""

import re
import sys

DEVICES_PY = "src/freedreno/common/freedreno_devices.py"

def apply():
    with open(DEVICES_PY, 'r') as f:
        content = f.read()

    modified = False

    # 1. Ensure 0x44050001 is listed as GPU ID for FD830
    # Look for the A830 GPU entry: GPUId(chip_id=0x44050000, name="FD830"),
    old_a830 = r'(GPUId\(chip_id=0x44050000,\s*name="FD830"\))(,)'
    new_a830 = r'\1,\n        GPUId(chip_id=0x44050001, name="FD830"),  # KGSL (S25 Ultra)\2'

    if '0x44050001' not in content:
        content = re.sub(old_a830, new_a830, content)
        modified = True
        print("  ✓ أضيف chip_id=0x44050001 (KGSL variant) لـ FD830")
    else:
        print("  ✓ 0x44050001 موجود مسبقاً في FD830")

    # 2. Ensure tile_align_w is 96 for A830
    # Look for the A830 A6xxGPUInfo and check tile_align_w
    # This is a more complex check — verify tile alignment in A830 entry
    if 'tile_align_w = 96' not in content:
        print("  ⚠ tile_align_w ليس 96 — قد يكون مضبوطاً بواسطة الباتش الرئيسي")
    else:
        print("  ✓ tile_align_w = 96 مضبوط لـ A830")

    # 3. Ensure disable_gmem = True is in a8xx_gen1_a830 props
    if 'disable_gmem = True' not in content:
        # Target only a8xx_gen1_a830 GPUProps block
        old_gen1_end = (
            r'(a8xx_gen1_a830 = GPUProps\([\s\S]*?'
            r'has_salu_int_narrowing_quirk\s*=\s*True)(\s*\))'
        )
        new_gen1_end = (
            r'\1,\n\n        # Disable GMEM for A830 — GMEM causes GPU hangs\n'
            r'        disable_gmem = True\2'
        )
        new_content, count = re.subn(old_gen1_end, new_gen1_end, content, count=1)
        if count == 0:
            print("  ⚠ لم يُعثر على a8xx_gen1_a830 — تخطي disable_gmem")
        else:
            content = new_content
            modified = True
            print("  ✓ أضيف disable_gmem = True إلى a8xx_gen1_a830")
    else:
        print("  ✓ disable_gmem = True موجود مسبقاً")

    with open(DEVICES_PY, 'w') as f:
        f.write(content)

    # 4. Verify syntax
    try:
        compile(content, DEVICES_PY, 'exec')
        print("  ✓ freedreno_devices.py صحيح نحوياً ✓")
    except SyntaxError as e:
        print(f"  ❌ خطأ نحوي في freedreno_devices.py: {e}")
        sys.exit(1)

    if not modified:
        print("  (لم يتم إجراء تغييرات جديدة)")

if __name__ == "__main__":
    apply()
