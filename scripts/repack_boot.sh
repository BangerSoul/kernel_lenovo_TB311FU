#!/usr/bin/env bash
# ==============================================================================
# scripts/repack_boot.sh - Android Boot Image Repacker for Lenovo Tab M11
# Target: Lenovo Tab M11 (TB311FU / poplar, MediaTek MT8786 / MT6768 / MT6769)
# Supports: Android Boot Header v2, v3, v4 (GKI 2.0)
# Backends: magiskboot, mkbootimg/unpack_bootimg, and built-in Python fallback
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Geometry constants for Lenovo Tab M11 (poplar / tb8786p1_64_k66)
EXPECTED_BOOT_SIZE=33554432       # 32 MB
VBMETA_OFFSET=14561280            # 0xDE3000
VBMETA_SIZE=2432                  # Pristine OEM VBMeta block size
AVB_FOOTER_OFFSET=33554368        # 32 MB - 64 bytes
AVB_FOOTER_SIZE=64
BOOT_PAGE_SIZE=4096

# Defaults
BOOT_IMG=""
KERNEL_PAYLOAD=""
RAMDISK_PAYLOAD=""
DTB_PAYLOAD=""
OUTPUT_IMG="boot_repacked.img"
TOOL_CHOICE="auto"
CUSTOM_CMDLINE=""
PAD_32M="auto"
AVB_ALIGN="auto"
VERBOSE=0

print_usage() {
    cat << 'EOF'
Usage: repack_boot.sh -b <boot.img> -k <kernel> [options]

Required arguments:
  -b, --boot <path>       Original/stock boot.img to unpack
  -k, --kernel <path>     New kernel binary (Image, Image.gz, or Image.gz-dtb)

Optional arguments:
  -r, --ramdisk <path>    New or replacement ramdisk (.cpio or .cpio.gz)
  -d, --dtb <path>        New or replacement DTB image
  -o, --output <path>     Output repacked boot image path (default: boot_repacked.img)
  -t, --tool <backend>    Repack backend: auto (default), magiskboot, mkbootimg, python
  -c, --cmdline <string>  Override or append kernel command line
      --pad-32m           Enforce 32MB padding for Lenovo Tab M11 boot partition
      --no-pad            Do not pad output image
      --avb-align         Preserve OEM VBMeta block at 14,561,280 and AVB footer
  -v, --verbose           Enable verbose diagnostic logs
  -h, --help              Show this help message and exit

Examples:
  ./scripts/repack_boot.sh -b stock_boot.img -k out/Image.gz-dtb -o new_boot.img
  ./scripts/repack_boot.sh -b boot.img -k Image.gz -r ramdisk.cpio -t magiskboot
  ./scripts/repack_boot.sh -b boot.img -k Image.gz -t mkbootimg --pad-32m
EOF
}

log_info() {
    echo -e "\033[1;34m[INFO]\033[0m $*"
}

log_warn() {
    echo -e "\033[1;33m[WARN]\033[0m $*" >&2
}

log_err() {
    echo -e "\033[1;31m[ERROR]\033[0m $*" >&2
}

log_debug() {
    if [[ "${VERBOSE}" -eq 1 ]]; then
        echo -e "\033[1;30m[DEBUG]\033[0m $*"
    fi
}

# Parse Command-line Options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--boot)
            BOOT_IMG="$2"
            shift 2
            ;;
        -k|--kernel)
            KERNEL_PAYLOAD="$2"
            shift 2
            ;;
        -r|--ramdisk)
            RAMDISK_PAYLOAD="$2"
            shift 2
            ;;
        -d|--dtb)
            DTB_PAYLOAD="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_IMG="$2"
            shift 2
            ;;
        -t|--tool)
            TOOL_CHOICE="$2"
            shift 2
            ;;
        -c|--cmdline)
            CUSTOM_CMDLINE="$2"
            shift 2
            ;;
        --pad-32m)
            PAD_32M="true"
            shift
            ;;
        --no-pad)
            PAD_32M="false"
            shift
            ;;
        --avb-align)
            AVB_ALIGN="true"
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_err "Unknown argument: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate required inputs
if [[ -z "${BOOT_IMG}" ]]; then
    log_err "Missing required argument: --boot <boot.img>"
    print_usage
    exit 1
fi

if [[ ! -f "${BOOT_IMG}" ]]; then
    log_err "Boot image file not found: ${BOOT_IMG}"
    exit 1
fi

if [[ -z "${KERNEL_PAYLOAD}" ]]; then
    log_err "Missing required argument: --kernel <kernel>"
    print_usage
    exit 1
fi

if [[ ! -f "${KERNEL_PAYLOAD}" ]]; then
    log_err "Kernel payload not found: ${KERNEL_PAYLOAD}"
    exit 1
fi

if [[ -n "${RAMDISK_PAYLOAD}" && ! -f "${RAMDISK_PAYLOAD}" ]]; then
    log_err "Ramdisk payload specified but not found: ${RAMDISK_PAYLOAD}"
    exit 1
fi

if [[ -n "${DTB_PAYLOAD}" && ! -f "${DTB_PAYLOAD}" ]]; then
    log_err "DTB payload specified but not found: ${DTB_PAYLOAD}"
    exit 1
fi

# Detect original boot image characteristics
ORIG_SIZE=$(stat -c%s "${BOOT_IMG}")
log_info "Input boot image: ${BOOT_IMG} (${ORIG_SIZE} bytes)"
log_info "New kernel payload: ${KERNEL_PAYLOAD} ($(stat -c%s "${KERNEL_PAYLOAD}") bytes)"

# Verify ANDROID! magic
MAGIC=$(head -c 8 "${BOOT_IMG}" 2>/dev/null || true)
if [[ "${MAGIC}" != "ANDROID!" ]]; then
    log_err "File ${BOOT_IMG} does not have valid 'ANDROID!' boot magic header!"
    exit 1
fi

# Auto-detect 32MB padding requirement
if [[ "${PAD_32M}" == "auto" ]]; then
    if [[ "${ORIG_SIZE}" -eq "${EXPECTED_BOOT_SIZE}" ]]; then
        log_info "Detected 32MB boot partition (Lenovo Tab M11 geometry). Enabling 32MB padding and LK AVB alignment."
        PAD_32M="true"
        if [[ "${AVB_ALIGN}" == "auto" ]]; then
            AVB_ALIGN="true"
        fi
    else
        PAD_32M="false"
        if [[ "${AVB_ALIGN}" == "auto" ]]; then
            AVB_ALIGN="false"
        fi
    fi
fi

# Locate Tools
find_tool() {
    local tool_name="$1"
    local candidates=(
        "${tool_name}"
        "${SCRIPT_DIR}/${tool_name}"
        "${REPO_ROOT}/tools/${tool_name}"
        "/usr/local/bin/${tool_name}"
        "/usr/bin/${tool_name}"
    )
    for c in "${candidates[@]}"; do
        if command -v "${c}" >/dev/null 2>&1; then
            echo "${c}"
            return 0
        elif [[ -x "${c}" ]]; then
            echo "${c}"
            return 0
        fi
    done
    return 1
}

MAGISKBOOT_BIN=$(find_tool "magiskboot" || true)
MKBOOTIMG_BIN=$(find_tool "mkbootimg" || find_tool "mkbootimg.py" || true)
UNPACK_BOOTIMG_BIN=$(find_tool "unpack_bootimg" || find_tool "unpack_bootimg.py" || true)

# Determine backend tool to use
SELECTED_BACKEND=""
if [[ "${TOOL_CHOICE}" == "magiskboot" ]]; then
    if [[ -z "${MAGISKBOOT_BIN}" ]]; then
        log_err "Requested tool 'magiskboot' not found on PATH or in repo tools!"
        exit 1
    fi
    SELECTED_BACKEND="magiskboot"
elif [[ "${TOOL_CHOICE}" == "mkbootimg" ]]; then
    if [[ -z "${MKBOOTIMG_BIN}" ]]; then
        log_warn "Requested tool 'mkbootimg' not found. Falling back to built-in Python mkbootimg engine."
        SELECTED_BACKEND="python"
    else
        SELECTED_BACKEND="mkbootimg"
    fi
elif [[ "${TOOL_CHOICE}" == "python" ]]; then
    SELECTED_BACKEND="python"
elif [[ "${TOOL_CHOICE}" == "auto" ]]; then
    if [[ -n "${MAGISKBOOT_BIN}" ]]; then
        SELECTED_BACKEND="magiskboot"
    elif [[ -n "${MKBOOTIMG_BIN}" ]]; then
        SELECTED_BACKEND="mkbootimg"
    else
        SELECTED_BACKEND="python"
    fi
else
    log_err "Unknown tool choice: ${TOOL_CHOICE}. Valid: auto, magiskboot, mkbootimg, python."
    exit 1
fi

log_info "Selected repack backend: ${SELECTED_BACKEND}"

# Create temporary working directory
WORK_DIR=$(mktemp -d "/tmp/repack_boot_XXXXXX")
cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT INT TERM

# Ensure absolute paths
ABS_BOOT_IMG="$(cd "$(dirname "${BOOT_IMG}")" && pwd)/$(basename "${BOOT_IMG}")"
ABS_KERNEL="$(cd "$(dirname "${KERNEL_PAYLOAD}")" && pwd)/$(basename "${KERNEL_PAYLOAD}")"
ABS_OUTPUT="$(cd "$(dirname "${OUTPUT_IMG}")" && pwd)/$(basename "${OUTPUT_IMG}")"
ABS_RAMDISK=""
if [[ -n "${RAMDISK_PAYLOAD}" ]]; then
    ABS_RAMDISK="$(cd "$(dirname "${RAMDISK_PAYLOAD}")" && pwd)/$(basename "${RAMDISK_PAYLOAD}")"
fi
ABS_DTB=""
if [[ -n "${DTB_PAYLOAD}" ]]; then
    ABS_DTB="$(cd "$(dirname "${DTB_PAYLOAD}")" && pwd)/$(basename "${DTB_PAYLOAD}")"
fi

# Execute Repacking Based on Selected Backend
cd "${WORK_DIR}"

if [[ "${SELECTED_BACKEND}" == "magiskboot" ]]; then
    log_info "Unpacking boot image using magiskboot (${MAGISKBOOT_BIN})..."
    cp "${ABS_BOOT_IMG}" boot.img
    "${MAGISKBOOT_BIN}" unpack boot.img

    log_info "Replacing kernel payload with ${ABS_KERNEL}..."
    cp -f "${ABS_KERNEL}" kernel

    if [[ -n "${ABS_RAMDISK}" ]]; then
        log_info "Replacing ramdisk payload with ${ABS_RAMDISK}..."
        cp -f "${ABS_RAMDISK}" ramdisk.cpio
    fi

    if [[ -n "${ABS_DTB}" ]]; then
        log_info "Replacing DTB payload with ${ABS_DTB}..."
        cp -f "${ABS_DTB}" dtb
    fi

    if [[ -n "${CUSTOM_CMDLINE}" ]]; then
        log_info "Updating cmdline in header..."
        if [[ -f "header" ]]; then
            sed -i "s|^cmdline=.*|cmdline=${CUSTOM_CMDLINE}|" header || true
        fi
    fi

    log_info "Repacking boot image using magiskboot..."
    "${MAGISKBOOT_BIN}" repack boot.img repacked_raw.img

    if [[ ! -f "repacked_raw.img" && -f "new-boot.img" ]]; then
        mv new-boot.img repacked_raw.img
    fi

elif [[ "${SELECTED_BACKEND}" == "mkbootimg" && -n "${UNPACK_BOOTIMG_BIN}" ]]; then
    log_info "Unpacking boot image using unpack_bootimg (${UNPACK_BOOTIMG_BIN})..."
    mkdir -p unpacked
    "${UNPACK_BOOTIMG_BIN}" --boot_img "${ABS_BOOT_IMG}" --out unpacked

    # Detect header version
    HEADER_VERSION="4"
    if [[ -f "unpacked/header_version" ]]; then
        HEADER_VERSION=$(cat "unpacked/header_version")
    fi

    MKBOOT_ARGS=()
    MKBOOT_ARGS+=(--header_version "${HEADER_VERSION}")
    MKBOOT_ARGS+=(--kernel "${ABS_KERNEL}")

    # Ramdisk
    if [[ -n "${ABS_RAMDISK}" ]]; then
        MKBOOT_ARGS+=(--ramdisk "${ABS_RAMDISK}")
    elif [[ -f "unpacked/ramdisk" && $(stat -c%s "unpacked/ramdisk") -gt 0 ]]; then
        MKBOOT_ARGS+=(--ramdisk "unpacked/ramdisk")
    elif [[ -f "unpacked/ramdisk.cpio" ]]; then
        MKBOOT_ARGS+=(--ramdisk "unpacked/ramdisk.cpio")
    fi

    # DTB
    if [[ -n "${ABS_DTB}" ]]; then
        MKBOOT_ARGS+=(--dtb "${ABS_DTB}")
    elif [[ -f "unpacked/dtb" && $(stat -c%s "unpacked/dtb") -gt 0 ]]; then
        MKBOOT_ARGS+=(--dtb "unpacked/dtb")
    fi

    # Cmdline
    if [[ -n "${CUSTOM_CMDLINE}" ]]; then
        MKBOOT_ARGS+=(--cmdline "${CUSTOM_CMDLINE}")
    elif [[ -f "unpacked/cmdline" ]]; then
        CMDLINE_VAL=$(cat "unpacked/cmdline")
        MKBOOT_ARGS+=(--cmdline "${CMDLINE_VAL}")
    fi

    # OS Version / Patch Level
    if [[ -f "unpacked/os_version" ]]; then
        MKBOOT_ARGS+=(--os_version "$(cat unpacked/os_version)")
    fi
    if [[ -f "unpacked/os_patch_level" ]]; then
        MKBOOT_ARGS+=(--os_patch_level "$(cat unpacked/os_patch_level)")
    fi
    if [[ -f "unpacked/pagesize" ]]; then
        MKBOOT_ARGS+=(--pagesize "$(cat unpacked/pagesize)")
    fi

    log_info "Repacking boot image using mkbootimg (${MKBOOTIMG_BIN})..."
    "${MKBOOTIMG_BIN}" "${MKBOOT_ARGS[@]}" --output repacked_raw.img

else
    # Python built-in unpacker and repacker
    log_info "Unpacking and repacking boot image using built-in Python engine..."
    python3 - << 'PYEOF' "${ABS_BOOT_IMG}" "${ABS_KERNEL}" "${ABS_RAMDISK}" "${ABS_DTB}" "${CUSTOM_CMDLINE}" "repacked_raw.img"
import sys
import struct
import os

boot_path = sys.argv[1]
kernel_path = sys.argv[2]
ramdisk_path = sys.argv[3] if len(sys.argv) > 3 and sys.argv[3] else None
dtb_path = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else None
custom_cmdline = sys.argv[5] if len(sys.argv) > 5 and sys.argv[5] else None
output_path = sys.argv[6]

with open(boot_path, "rb") as f:
    hdr = f.read(4096)
    magic = hdr[:8]
    if magic != b"ANDROID!":
        raise ValueError("Invalid boot magic")

    k_sz = struct.unpack("<I", hdr[8:12])[0]
    # Header version at offset 40 (v0/v1/v2/v3/v4)
    h_ver = struct.unpack("<I", hdr[40:44])[0]

    with open(kernel_path, "rb") as kf:
        new_k = kf.read()

    new_k_sz = len(new_k)

    if h_ver >= 3:
        # Header v3/v4:
        # 0..8: ANDROID!
        # 8..12: kernel_size
        # 12..16: ramdisk_size
        # 16..20: os_version
        # 20..24: header_size
        # 24..40: reserved
        # 40..44: header_version (3 or 4)
        # 44..1580: cmdline (1536 bytes)
        # 1580..1584: signature_size (v4)
        ramdisk_size = struct.unpack("<I", hdr[12:16])[0]
        os_version = struct.unpack("<I", hdr[16:20])[0]
        header_size = struct.unpack("<I", hdr[20:24])[0]
        cmdline = hdr[44:1580].split(b"\x00")[0].decode("utf-8", errors="ignore")
        if custom_cmdline:
            cmdline = custom_cmdline

        sig_size = struct.unpack("<I", hdr[1580:1584])[0] if h_ver >= 4 else 0

        # Read ramdisk if not overridden
        f.seek(4096 + ((k_sz + 4095) // 4096) * 4096)
        orig_ramdisk = f.read(ramdisk_size)

        new_ramdisk = orig_ramdisk
        if ramdisk_path and os.path.isfile(ramdisk_path):
            with open(ramdisk_path, "rb") as rf:
                new_ramdisk = rf.read()

        # Build new header
        new_hdr = bytearray(4096)
        new_hdr[:8] = b"ANDROID!"
        struct.pack_into("<I", new_hdr, 8, new_k_sz)
        struct.pack_into("<I", new_hdr, 12, len(new_ramdisk))
        struct.pack_into("<I", new_hdr, 16, os_version)
        struct.pack_into("<I", new_hdr, 20, header_size)
        struct.pack_into("<I", new_hdr, 40, h_ver)
        cmd_bytes = cmdline.encode("utf-8")[:1535]
        new_hdr[44:44+len(cmd_bytes)] = cmd_bytes
        if h_ver >= 4:
            struct.pack_into("<I", new_hdr, 1580, sig_size)

        with open(output_path, "wb") as out:
            out.write(new_hdr)
            out.write(new_k)
            # pad kernel to 4096
            k_pad = (4096 - (new_k_sz % 4096)) % 4096
            out.write(b"\x00" * k_pad)
            if len(new_ramdisk) > 0:
                out.write(new_ramdisk)
                r_pad = (4096 - (len(new_ramdisk) % 4096)) % 4096
                out.write(b"\x00" * r_pad)
    else:
        # Header v0/v1/v2
        kernel_addr, ramdisk_size, ramdisk_addr, second_size, second_addr, tags_addr, page_size = struct.unpack("<IIIIIII", hdr[12:40])
        # Build v0-v2 image
        f.seek(page_size)
        f.seek(page_size + ((k_sz + page_size - 1) // page_size) * page_size)
        orig_ramdisk = f.read(ramdisk_size)
        new_ramdisk = orig_ramdisk
        if ramdisk_path and os.path.isfile(ramdisk_path):
            with open(ramdisk_path, "rb") as rf:
                new_ramdisk = rf.read()

        new_hdr = bytearray(hdr)
        struct.pack_into("<I", new_hdr, 8, new_k_sz)
        struct.pack_into("<I", new_hdr, 16, len(new_ramdisk))
        if custom_cmdline:
            c_bytes = custom_cmdline.encode("utf-8")[:511]
            new_hdr[64:64+len(c_bytes)] = c_bytes
            new_hdr[64+len(c_bytes):576] = b"\x00" * (512 - len(c_bytes))

        with open(output_path, "wb") as out:
            out.write(new_hdr[:page_size])
            out.write(new_k)
            k_pad = (page_size - (new_k_sz % page_size)) % page_size
            out.write(b"\x00" * k_pad)
            if len(new_ramdisk) > 0:
                out.write(new_ramdisk)
                r_pad = (page_size - (len(new_ramdisk) % page_size)) % page_size
                out.write(b"\x00" * r_pad)

print("Python repack completed successfully.")
PYEOF
fi

if [[ ! -f "repacked_raw.img" ]]; then
    log_err "Failed to produce repacked boot image!"
    exit 1
fi

RAW_SIZE=$(stat -c%s "repacked_raw.img")
log_info "Raw repacked boot image size: ${RAW_SIZE} bytes"

# Handle Lenovo Tab M11 LK AVB 2.0 Invariant & 32MB Padding
if [[ "${PAD_32M}" == "true" ]]; then
    log_info "Enforcing 32MB boot vector alignment (Lenovo Tab M11 AVB 2.0 Invariant)..."

    python3 - << 'PYEOF' "${ABS_BOOT_IMG}" "repacked_raw.img" "${ABS_OUTPUT}" "${AVB_ALIGN}"
import sys
import struct
import os

orig_boot_path = sys.argv[1]
raw_repacked_path = sys.argv[2]
final_output_path = sys.argv[3]
do_avb_align = (sys.argv[4].lower() == "true")

TARGET_SIZE = 33554432       # 32 MB
VBMETA_OFFSET = 14561280     # 0xDE3000
VBMETA_SIZE = 2432
AVB_FOOTER_OFFSET = 33554368 # 32 MB - 64 bytes
AVB_FOOTER_SIZE = 64

with open(raw_repacked_path, "rb") as rf:
    raw_data = rf.read()

if len(raw_data) > VBMETA_OFFSET and do_avb_align:
    raise ValueError(f"Repacked image size ({len(raw_data)} bytes) exceeds VBMETA_OFFSET ({VBMETA_OFFSET} bytes)!")

final_data = bytearray(TARGET_SIZE)

# Copy raw repacked payload (header + kernel + ramdisk)
final_data[:len(raw_data)] = raw_data

if do_avb_align:
    # Check if original boot image contains OEM VBMeta block and AVB footer
    with open(orig_boot_path, "rb") as orig_f:
        orig_size = orig_f.seek(0, os.SEEK_END)
        if orig_size >= TARGET_SIZE:
            # Extract OEM VBMeta block
            orig_f.seek(VBMETA_OFFSET)
            vbmeta_block = orig_f.read(VBMETA_SIZE)

            # Extract AVB footer
            orig_f.seek(AVB_FOOTER_OFFSET)
            avb_footer = orig_f.read(AVB_FOOTER_SIZE)

            if vbmeta_block[:4] == b"AVB0":
                print(f"[INFO] Injecting pristine OEM VBMeta block (2,432 bytes) at offset {VBMETA_OFFSET} (0xDE3000)...")
                final_data[VBMETA_OFFSET:VBMETA_OFFSET + VBMETA_SIZE] = vbmeta_block
            else:
                print("[WARN] Original boot image does not contain AVB0 magic at VBMeta offset.")

            if avb_footer[:4] == b"AVBf":
                print(f"[INFO] Injecting AVB footer (64 bytes) at offset {AVB_FOOTER_OFFSET}...")
                final_data[AVB_FOOTER_OFFSET:AVB_FOOTER_OFFSET + AVB_FOOTER_SIZE] = avb_footer
            else:
                print("[WARN] Original boot image does not contain AVBf magic at footer offset.")

with open(final_output_path, "wb") as out:
    out.write(final_data)

print(f"[SUCCESS] Final 32MB aligned boot image written to: {final_output_path}")
PYEOF

else
    log_info "Writing unpadded repacked image to ${ABS_OUTPUT}..."
    cp -f repacked_raw.img "${ABS_OUTPUT}"
fi

# Verification & Summary
FINAL_SIZE=$(stat -c%s "${ABS_OUTPUT}")
FINAL_SHA256=$(sha256sum "${ABS_OUTPUT}" | awk '{print $1}')

echo ""
echo "================================================================="
echo "       PoplarKernel Boot Image Repacking Complete                "
echo "================================================================="
echo " Output Path : ${ABS_OUTPUT}"
echo " File Size   : ${FINAL_SIZE} bytes ($(( FINAL_SIZE / 1024 / 1024 )) MB)"
echo " SHA-256     : ${FINAL_SHA256}"
echo " Backend     : ${SELECTED_BACKEND}"
if [[ "${PAD_32M}" == "true" ]]; then
    echo " Geometry    : 32 MB Aligned (MediaTek Little Kernel AVB 2.0 Invariant)"
fi
echo "================================================================="
echo ""
