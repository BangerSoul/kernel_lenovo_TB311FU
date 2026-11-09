# Custom Kernel CI/CD Pipeline for Lenovo Tab M11 (`TB311FU`)

Automated Custom Kernel build and packaging pipeline running on dedicated GitHub-hosted runners (`ubuntu-22.04`) for the **Lenovo Tab M11** (`TB311FU`, MediaTek Helio G88 / MT6769, board `tb8786p1_64_k66`).

---

## Hardware & Kernel Architecture

| Parameter | Specification |
| :--- | :--- |
| **Target Device** | Lenovo Tab M11 (`TB311FU` / `poplar`) |
| **SoC** | MediaTek Helio G88 (`MT6769H` / `MT8786`) |
| **CPU Architecture** | ARM64 (`aarch64-linux-gnu`) |
| **Kernel Model** | Generic Kernel Image (GKI 2.0 / Boot Header v4) |
| **Toolchain** | Google AOSP LLVM Clang (`clang-r450784d` / Android Clang 14+) |
| **Root Integration** | Built-in KernelSU-Next / KernelSU (kprobes + overlayfs) |
| **Packaging** | Flashable AnyKernel3 zip installer (TWRP / OrangeFox compatible) |

---

## Workflow Dispatch Options

The GitHub Actions workflow (`.github/workflows/build-kernel.yml`) exposes configurable parameters:

* **`KERNEL_REPO`**: URL of kernel source repository (default: AOSP Common Kernel `kernel/common` or MT6769 OEM kernel).
* **`KERNEL_BRANCH`**: Branch of kernel source (default: `android12-5.10`).
* **`DEFCONFIG`**: Target defconfig (e.g. `gki_defconfig` or `tb8786p1_64_k66_defconfig`).
* **`CLANG_VERSION`**: AOSP Clang release (default: `r450784d`).
* **`KERNELSU_MODE`**: `KernelSU-Next`, `KernelSU`, or `None`.
* **`BUILD_DTBO`**: Toggle compiling and packaging DTBO image (`true` / `false`).

---

## Flashing Instructions

### Via Custom Recovery (TWRP / OrangeFox):
1. Copy the generated `AnyKernel3-TB311FU-*.zip` to device storage or MicroSD card.
2. Boot into custom recovery (`fastboot reboot recovery`).
3. Select **Install** -> Choose the AnyKernel3 zip -> Swipe to confirm flash.
4. Reboot system.

### Via Fastboot (Raw Image):
```bash
# Flash raw GKI kernel image directly to boot partition
fastboot flash boot Image.gz

# If custom DTBO was compiled
fastboot flash dtbo dtbo.img

fastboot reboot
```
