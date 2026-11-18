# kernel_lenovo_TB311FU

[![License: GPL-2.0](https://img.shields.io/badge/License-GPL%202.0-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)
[![Target: Lenovo Tab with Clear Case (TB311FU)](https://img.shields.io/badge/Device-Lenovo%20Tab%20with%20Clear%20Case%20(TB311FU)-orange.svg)](https://www.lenovo.com)
[![Branch: main](https://img.shields.io/badge/Branch-main-success.svg)](https://github.com/BangerSoul/kernel_lenovo_TB311FU)
[![Kernel: Linux 6.6 LTS](https://img.shields.io/badge/Kernel-Linux%206.6%20GKI%202.0-teal.svg)](https://kernel.org)
[![Root: KernelSU-Next](https://img.shields.io/badge/Root-KernelSU--Next-violet.svg)](https://github.com/KernelSU-Next/KernelSU-Next)

Downstream Linux 6.6 GKI 2.0 kernel tree defconfigs, patches, KernelSU-Next root integration, permissive dm-verity, and Little Kernel (LK) AVB 2.0 boot vector assembly suite for the **Lenovo Tab with Clear Case** (`TB311FU`, codename `poplar`, MediaTek Helio G88 / MT8786 / MT6768).

---

## 🌐 Lenovo Tab with Clear Case (TB311FU / poplar) Open-Source Bringup Ecosystem

The complete open-source software stack for the **Lenovo Tab with Clear Case** (`TB311FU`, codename `poplar`, MediaTek Helio G88 / MT8786 / MT6768) is organized into five specialized, interconnected repositories under [@BangerSoul](https://github.com/BangerSoul):

| Repository | Role & Subsystem Scope | Target Stack | Key Deliverables & Artifacts | Badges & Links |
| :--- | :--- | :--- | :--- | :---: |
| [**`device_lenovo_TB311FU`**](https://github.com/BangerSoul/device_lenovo_TB311FU) | **Device Tree & RRO Overlays**<br>LineageOS device configuration, 90Hz display profiles, SystemUI/Framework RRO overlays, super partition budget management, and 5-tier diagnostic test suite. | Android 16 QPR2<br>LineageOS 23.2 / 22.1 | `TrebleOverlayLenovoTB311FU.apk`<br>`TrebleOverlayLenovoTB311FUSystemUI.apk`<br>`flash_lineage23_fastbootd.ps1`<br>E2E Diagnostic Test Suite | [![Device Tree](https://img.shields.io/badge/Repo-device__lenovo__TB311FU-blue.svg?logo=android)](https://github.com/BangerSoul/device_lenovo_TB311FU)<br>[![Releases](https://img.shields.io/badge/Releases-v1.0--lineage23-blue.svg)](https://github.com/BangerSoul/device_lenovo_TB311FU/releases) |
| [**`vendor_lenovo_TB311FU`**](https://github.com/BangerSoul/vendor_lenovo_TB311FU) | **Vendor Blobs & Hardware Policies**<br>Proprietary blobs, 4-speaker surround audio routing (`AUDIO_CHANNEL_OUT_QUAD`), Dolby Atmos DAP/DRC trees, AP500U active stylus IDC configs, and EROFS vendor repacking tools. | Android 16 QPR2<br>LineageOS 23.2 HALs | `vendor_stabilized.img` (EROFS LZ4)<br>`audio_policy_configuration.xml`<br>`audio_effects.xml`<br>`himax-touchscreen.idc` / `NVT-ts.idc` | [![Vendor Blobs](https://img.shields.io/badge/Repo-vendor__lenovo__TB311FU-orange.svg?logo=android)](https://github.com/BangerSoul/vendor_lenovo_TB311FU)<br>[![Releases](https://img.shields.io/badge/Releases-Assets-orange.svg)](https://github.com/BangerSoul/vendor_lenovo_TB311FU/releases) |
| [**`kernel_lenovo_TB311FU`**](https://github.com/BangerSoul/kernel_lenovo_TB311FU) | **PoplarKernel GKI 2.0 & AVB Vector**<br>Downstream Linux 6.6 LTS kernel, KernelSU-Next native integration, module signature bypass (`CONFIG_RFKILL=m`), permissive dm-verity, PWM >= 48 floor clamp, and 32MB LK AVB boot vector builder. | Linux 6.6 LTS GKI 2.0<br>Android 15 / 16 & Halium | PoplarKernel v1.2 AnyKernel3 Zip<br>32MB AVB Chained `boot.img`<br>Halium `Image.gz` / `dtbo.img`<br>CI/CD Automated Build Actions | [![Kernel](https://img.shields.io/badge/Repo-kernel__lenovo__TB311FU-teal.svg?logo=linux)](https://github.com/BangerSoul/kernel_lenovo_TB311FU)<br>[![Releases](https://img.shields.io/badge/Releases-v1.2-teal.svg)](https://github.com/BangerSoul/kernel_lenovo_TB311FU/releases) |
| [**`recovery_lenovo_TB311FU`**](https://github.com/BangerSoul/recovery_lenovo_TB311FU) | **TWRP 3.7+ Recovery & Slot B Vector**<br>Non-destructive custom recovery deployment to secondary slot `boot_b`, pristine factory `vendor_boot` & `vbmeta` preservation, BCB staging, and zero-risk slot switching. | Android Header v4<br>TWRP 3.7+ / OrangeFox | Slot B Chained `recovery_boot.img`<br>Turnkey Hybrid `vendor_boot.img`<br>Bootloader Control Block Tools<br>CI/CD Automated Build Actions | [![Recovery](https://img.shields.io/badge/Repo-recovery__lenovo__TB311FU-blueviolet.svg?logo=twrp)](https://github.com/BangerSoul/recovery_lenovo_TB311FU)<br>[![Releases](https://img.shields.io/badge/Releases-v1.0--twrp-blueviolet.svg)](https://github.com/BangerSoul/recovery_lenovo_TB311FU/releases) |
| [**`linux-lenovo-tb311fu`**](https://github.com/BangerSoul/linux-lenovo-tb311fu) | **Native Linux / PostmarketOS Port**<br>Alpine ARM64 + KDE Plasma Mobile 6 port, KWin Wayland 24-bit True Color fallback & rotation fix (`libkwin.so.6.7.5`), WMT Wi-Fi/BT daemons, quad ALSA UCM scenarios, and Fastbootd direct `system_a` flasher. | PostmarketOS<br>Alpine ARM64 / Plasma Mobile 6 | `device-lenovo-tb311fu` package<br>`linux-lenovo-tb311fu` package<br>`libkwin.so.6.7.5.patched`<br>Fastbootd `-S 64M` Rootfs Flasher | [![Linux Port](https://img.shields.io/badge/Repo-linux--lenovo--tb311fu-success.svg?logo=postmarketos)](https://github.com/BangerSoul/linux-lenovo-tb311fu)<br>[![Releases](https://img.shields.io/badge/Releases-v1.0--alpha-success.svg)](https://github.com/BangerSoul/linux-lenovo-tb311fu/releases) |

---

## Highlights & Scope

- **Linux 6.6 Downstream / GKI 2.0 Defconfigs & Performance Tuning:**
  - `tb311fu_defconfig`: PoplarKernel Android 15/16 GKI 2.0 tree with `CONFIG_RFKILL=m` to satisfy MediaTek `modules.dep` vendor module loading (`wlan_drv_gen4m_6768.ko`).
  - `halium_tb311fu_defconfig`: Dedicated defconfig tailored for Ubuntu Touch / Halium and PostmarketOS environments (ThinLTO enabled, `CONFIG_TRIM_UNUSED_KSYMS=n`).
  - **CPU Governor:** `schedutil` default, Energy Model (`CONFIG_ENERGY_MODEL=y`), CPUFreq DT & MediaTek scaling drivers enabled.
  - **I/O Scheduler:** `mq-deadline` default, BFQ (`CONFIG_IOSCHED_BFQ=y`), Kyber (`CONFIG_MQ_IOSCHED_KYBER=y`).
  - **TCP Congestion Control:** BBR default (`CONFIG_TCP_CONG_BBR=y`, `CONFIG_DEFAULT_BBR=y`), FQ, FQ-CoDel packet schedulers.
  - **Memory & Swap:** zRAM with default LZ4 compression, `zsmalloc` built-in, `zswap` writeback cache enabled (`CONFIG_ZSWAP=y`).
  - **Filesystems:** F2FS with compression, exFAT, NTFS3 read/write support (`CONFIG_NTFS3_FS=y`).
  - **System Limits & Stripping:** Default inotify/fanotify watcher and instance quotas increased, debug symbols and KASAN stripped for minimal memory overhead and peak throughput.
  - LCD panel driver patches and EVDI DRM support.
- **Kernel Boot Repacking & AVB Suite:**
  - `scripts/repack_boot.sh`: Universal boot image repacker supporting `magiskboot`, `mkbootimg`, and built-in Python engine with automatic 32MB MediaTek LK AVB alignment.
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
