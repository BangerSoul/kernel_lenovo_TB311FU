# kernel_lenovo_TB311FU

[![License: GPL-2.0](https://img.shields.io/badge/License-GPL%202.0-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
[![Target: Lenovo Tab M11](https://img.shields.io/badge/Device-Lenovo%20Tab%20M11%20(TB311FU)-orange.svg)](https://www.lenovo.com)
[![Branch: main](https://img.shields.io/badge/Branch-main-success.svg)](https://github.com/BangerSoul/kernel_lenovo_TB311FU)
[![Kernel: Linux 6.6 LTS](https://img.shields.io/badge/Kernel-Linux%206.6%20GKI%202.0-teal.svg)](https://kernel.org)
[![Root: KernelSU-Next](https://img.shields.io/badge/Root-KernelSU--Next-violet.svg)](https://github.com/KernelSU-Next/KernelSU-Next)

Downstream Linux 6.6 GKI 2.0 kernel tree defconfigs, patches, KernelSU-Next root integration, permissive dm-verity, and Little Kernel (LK) AVB 2.0 boot vector assembly suite for the **Lenovo Tab M11** (`TB311FU`, codename `poplar`, MediaTek Helio G88 / MT8786 / MT6768).

---

## Highlights & Scope

- **Linux 6.6 Downstream / GKI 2.0 Defconfigs:**
  - `tb311fu_defconfig`: PoplarKernel Android 15/16 GKI 2.0 tree with `CONFIG_RFKILL=m` to satisfy MediaTek `modules.dep` vendor module loading (`wlan_drv_gen4m_6768.ko`).
  - `halium_tb311fu_defconfig`: Dedicated defconfig tailored for Ubuntu Touch / Halium and PostmarketOS environments (ThinLTO enabled, `CONFIG_TRIM_UNUSED_KSYMS=n`).
  - LCD panel driver patches and EVDI DRM support.
- **KernelSU-Next Integration:**
  - KernelSU-Next native syscall hooks integrated into the GKI kernel image for non-intrusive root authority.
- **Module Signature Bypass & Permissive dm-verity:**
  - `patches/0002-permissive-dm-verity.patch`: Permissive dm-verity error handler in `drivers/md/dm-verity-target.c`, preventing verity panics when booting repacked `vendor_a` and stripped `system_a` dynamic partitions.
  - Out-of-tree module signature verification bypasses in `kernel/module/signing.c` allowing custom modules to link cleanly.
- **Backlight Minimum Floor Clamp:**
  - `patches/0001-backlight-floor-clamp-48.patch`: Enforces minimum raw PWM >= 48 in `drivers/video/backlight/backlight.c` and `pwm_bl.c`, completely preventing 0-nit panel blackouts at low brightness slider values.
- **AVB 2.0 OEM RSA4096 VBMeta Alignment Suite:**
  - `tools/assemble_boot_vector.py`: Formats 32 MB Android Boot Header v4 images where $\text{VBMeta Offset} == \text{Raw Image Size} == 14,561,280$ bytes, eliminating the 2-second Orange State reboot loop on MediaTek tablets.
  - `tools/verify_avb_chain.py`: Cryptographically audits the AVB footer, OEM public key SHA1 (`8fcb864f11f53ed11284615fb67685522085d3a2`), and VBMeta header flags.
  - `tools/verify_lk_avb_invariant.py`: Validates page alignment and zero-padding invariants against live dumps.

---

## Boot Vector Geometry & LK AVB Invariant

Lenovo MediaTek Little Kernel (LK) enforces strict verified boot geometry:

```
+-------------------------------------------------------+ 0x00000000
| Android Boot Header v4 (Page 0, 4096 bytes)           |
+-------------------------------------------------------+ 0x00001000
| Kernel Payload (GKI 6.6 Image.lz4 / Image)            |
+-------------------------------------------------------+
| Zero Padding up to 0xDE3000 (14,561,280 bytes)        |
+-------------------------------------------------------+ 0x00DE3000
| Pristine OEM VBMeta Block (2,432 bytes, flags = 0x00) |
+-------------------------------------------------------+ 0x00DE3980
| Zero Padding up to 32 MB - 64 bytes                   |
+-------------------------------------------------------+ 0x01FFFFC0
| AVB Footer (64 bytes, Magic: 'AVBf')                  |
+-------------------------------------------------------+ 0x02000000 (33,554,432 B)
```

To assemble a compatible boot image:
```bash
python tools/assemble_boot_vector.py --kernel Image.lz4 --output boot.img
```

---

## Maintainer

- **Maintainer:** Azmathulla Shaik ([@BangerSoul](https://github.com/BangerSoul))
- **Email:** `iamshaikhazmathulla@outlook.com`
