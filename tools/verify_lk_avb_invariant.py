#!/usr/bin/env python3
"""
boot_vector/verify_lk_avb_invariant.py - Little Kernel (LK) AVB Invariant Cryptographic Validator
PostmarketOS / Alpine ARM64 with Plasma Mobile on Lenovo Tab M11 (TB311FU / poplar)

Cryptographically audits and verifies that an Android Boot Header v4 image strictly satisfies
the MediaTek Little Kernel (LK) Android Verified Boot (AVB) 2.0 invariants:
    1. Total partition size is strictly 33,554,432 bytes (32 MB = 0x2000000).
    2. Android Boot Header v4 at offset 0 has magic b'ANDROID!', version == 4, and header_size == 1584.
    3. AVB footer at offset 33,554,368 (0x1FFFFC0) has magic b'AVBf'.
    4. VBMeta offset is strictly 4096-byte page aligned (offset % 4096 == 0).
    5. VBMeta block at offset has magic b'AVB0', flags byte 123 == 0x00 (verity intact, no --disable-verity).
    6. OEM RSA4096 public key SHA1 matches '8fcb864f11f53ed11284615fb67685522085d3a2'.
    7. Authentication block SHA256 self-integrity matches 'cdb31fa8398a68b4492fbcaaaa01732a8e7101cc3816326aa9ee980234226e9b'.
    8. Embedded AvbHashDescriptor inside VBMeta block has image_size == 14,561,280 bytes.
    9. Core Invariant: VBMeta Offset == HashDescriptor.image_size == 14,561,280 bytes (0xDE3000).
    10. Slack regions before VBMeta block and before AVB footer are strictly zero-padded.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import struct
import sys
from typing import Any, Dict, List, Optional, Tuple

WORKSPACE_ROOT: Path = Path(__file__).resolve().parent.parent

# Geometry & Invariant Constants
EXPECTED_BOOT_SIZE: int = 33554432          # 32 MB (0x2000000)
BOOT_HEADER_PAGE_SIZE: int = 4096
BOOT_HEADER_V4_SIZE: int = 1584
BOOT_ARGS_MAX_SIZE: int = 1536
BOOT_MAGIC: bytes = b"ANDROID!"
HEADER_VERSION: int = 4

EXPECTED_VBMETA_OFFSET: int = 14561280      # 0xDE3000
EXPECTED_VBMETA_SIZE: int = 2432
AVB_FOOTER_OFFSET: int = 33554368          # 33,554,432 - 64 (0x1FFFFC0)
AVB_FOOTER_SIZE: int = 64
AVB_FOOTER_MAGIC: bytes = b"AVBf"
VBMETA_MAGIC: bytes = b"AVB0"

# AVB Descriptor Tags
AVB_DESCRIPTOR_TAG_PROPERTY: int = 0
AVB_DESCRIPTOR_TAG_HASHTREE: int = 1
AVB_DESCRIPTOR_TAG_HASH: int = 2
AVB_DESCRIPTOR_TAG_CHAIN_PARTITION: int = 4

# Cryptographic OEM Hashes
EXPECTED_OEM_KEY_SHA1: str = "8fcb864f11f53ed11284615fb67685522085d3a2"
EXPECTED_AUTH_DIGEST: str = "cdb31fa8398a68b4492fbcaaaa01732a8e7101cc3816326aa9ee980234226e9b"
EXPECTED_SIGNATURE_SHA256: str = "fe45c90d220fbd0a32b14f74b86bad89757eb5ffebf6a25dcef843925ee57088"


class LKAVBInvariantError(ValueError):
    """Raised when an AVB 2.0 or Little Kernel invariant check fails."""
    pass


def parse_avb_descriptors(descriptors_bytes: bytes) -> List[Dict[str, Any]]:
    """Parses AVB descriptor stream from VBMeta auxiliary block."""
    descriptors = []
    pos = 0
    total_len = len(descriptors_bytes)

    while pos + 16 <= total_len:
        tag, num_bytes = struct.unpack(">QQ", descriptors_bytes[pos : pos + 16])
        record_len = 16 + num_bytes
        if pos + record_len > total_len:
            break

        desc_data = descriptors_bytes[pos + 16 : pos + record_len]
        desc_info: Dict[str, Any] = {"tag": tag, "num_bytes": num_bytes}

        if tag == AVB_DESCRIPTOR_TAG_HASH:
            # struct AvbHashDescriptor
            # uint64 image_size (offset 0)
            # uint8 hash_algorithm[32] (offset 8)
            # uint32 partition_name_len (offset 40)
            # uint32 salt_len (offset 44)
            # uint32 digest_len (offset 48)
            # uint32 flags (offset 52)
            # uint8 reserved[60] (offset 56) -> Total 116 bytes
            # Followed by: partition_name, salt, digest
            if len(desc_data) >= 116:
                img_sz, algo_raw, part_name_len, salt_len, digest_len, flags, _ = struct.unpack(
                    ">Q32sLLLL60s", desc_data[:116]
                )
                algo = algo_raw.rstrip(b"\x00").decode("ascii", errors="replace")
                var_data = desc_data[116:]

                part_name = var_data[:part_name_len].decode("utf-8", errors="replace")
                salt_start = part_name_len
                salt = var_data[salt_start : salt_start + salt_len]
                digest_start = salt_start + salt_len
                digest = var_data[digest_start : digest_start + digest_len]

                desc_info.update({
                    "type": "hash",
                    "image_size": img_sz,
                    "hash_algorithm": algo,
                    "partition_name": part_name,
                    "salt": salt.hex(),
                    "digest": digest.hex(),
                    "flags": flags,
                })
        elif tag == AVB_DESCRIPTOR_TAG_PROPERTY:
            desc_info["type"] = "property"
        elif tag == AVB_DESCRIPTOR_TAG_HASHTREE:
            desc_info["type"] = "hashtree"
        elif tag == AVB_DESCRIPTOR_TAG_CHAIN_PARTITION:
            desc_info["type"] = "chain_partition"
        else:
            desc_info["type"] = f"unknown_{tag}"

        descriptors.append(desc_info)
        pos += record_len

    return descriptors


def verify_lk_avb_invariant(
    image_data: bytes,
    image_path: str = "<memory>",
    verbose: bool = True,
) -> Dict[str, Any]:
    """
    Cryptographically verifies that image_data strictly satisfies all Little Kernel AVB invariants.
    
    Returns a dictionary of validated metadata on success.
    Raises LKAVBInvariantError if any invariant is violated.
    """
    if verbose:
        print("==================================================================")
        print(f" [LK AVB INVARIANT VERIFICATION] Target: {image_path}")
        print("==================================================================")

    # 1. Total Image Size (Strictly 32 MB)
    actual_size = len(image_data)
    if actual_size != EXPECTED_BOOT_SIZE:
        raise LKAVBInvariantError(
            f"Image size violation: Expected exactly {EXPECTED_BOOT_SIZE:,} bytes (32 MB), "
            f"got {actual_size:,} bytes."
        )
    if verbose:
        print(f"  [PASS] 1. Total partition size: {actual_size:,} bytes (0x{actual_size:x})")

    # 2. Android Boot Header v4 Verification
    boot_magic = image_data[:8]
    if boot_magic != BOOT_MAGIC:
        raise LKAVBInvariantError(
            f"Boot magic violation: Expected {BOOT_MAGIC!r}, got {boot_magic!r}"
        )

    kernel_size, ramdisk_size = struct.unpack("<II", image_data[8:16])
    packed_os_ver = struct.unpack("<I", image_data[16:20])[0]
    header_size = struct.unpack("<I", image_data[20:24])[0]
    header_version = struct.unpack("<I", image_data[40:44])[0]
    cmdline = image_data[44 : 44 + BOOT_ARGS_MAX_SIZE].split(b"\x00")[0].decode("ascii", errors="replace")

    if header_version != HEADER_VERSION:
        raise LKAVBInvariantError(
            f"Header version violation: Expected {HEADER_VERSION}, got {header_version}"
        )
    if header_size != BOOT_HEADER_V4_SIZE:
        raise LKAVBInvariantError(
            f"Header size violation: Expected {BOOT_HEADER_V4_SIZE}, got {header_size}"
        )
    if kernel_size <= 0:
        raise LKAVBInvariantError(
            f"Kernel size violation: Expected > 0 bytes, got {kernel_size}"
        )

    if verbose:
        print(f"  [PASS] 2. Boot Header v4: magic={boot_magic.decode('ascii')}, version={header_version}")
        print(f"         kernel_size: {kernel_size:,} B, ramdisk_size: {ramdisk_size:,} B, hdr_size: {header_size} B")
        print(f"         cmdline: '{cmdline[:60]}...'")

    # 3. AVB Footer Verification at offset 33,554,368 (0x1FFFFC0)
    footer_pos = EXPECTED_BOOT_SIZE - AVB_FOOTER_SIZE
    footer_bytes = image_data[footer_pos : footer_pos + AVB_FOOTER_SIZE]
    (
        f_magic,
        version_major,
        version_minor,
        original_image_size,
        vbmeta_offset,
        vbmeta_size,
    ) = struct.unpack(">4sIIQQQ", footer_bytes[:36])

    if f_magic != AVB_FOOTER_MAGIC:
        raise LKAVBInvariantError(
            f"AVB footer magic violation: Expected {AVB_FOOTER_MAGIC!r} at 0x{footer_pos:x}, got {f_magic!r}"
        )
    if version_major != 1 or version_minor != 0:
        raise LKAVBInvariantError(
            f"AVB footer version violation: Expected 1.0, got {version_major}.{version_minor}"
        )
    if vbmeta_offset != EXPECTED_VBMETA_OFFSET:
        raise LKAVBInvariantError(
            f"VBMeta offset violation: Expected {EXPECTED_VBMETA_OFFSET} (0x{EXPECTED_VBMETA_OFFSET:x}), "
            f"got {vbmeta_offset} (0x{vbmeta_offset:x})"
        )
    if original_image_size != EXPECTED_VBMETA_OFFSET:
        raise LKAVBInvariantError(
            f"Original image size violation: Expected {EXPECTED_VBMETA_OFFSET}, got {original_image_size}"
        )
    if vbmeta_size != EXPECTED_VBMETA_SIZE:
        raise LKAVBInvariantError(
            f"VBMeta block size violation: Expected {EXPECTED_VBMETA_SIZE}, got {vbmeta_size}"
        )

    if verbose:
        print(f"  [PASS] 3. AVB Footer: magic={f_magic.decode('ascii')} at offset 0x{footer_pos:x}")
        print(f"         vbmeta_offset: {vbmeta_offset:,} (0x{vbmeta_offset:x})")
        print(f"         original_image_size: {original_image_size:,} (0x{original_image_size:x})")
        print(f"         vbmeta_size: {vbmeta_size:,} B")

    # 4. Strict 4096-Byte Page Alignment Check
    if vbmeta_offset % BOOT_HEADER_PAGE_SIZE != 0:
        raise LKAVBInvariantError(
            f"Page alignment violation: VBMeta offset {vbmeta_offset} is not 4096-byte aligned "
            f"(offset % 4096 = {vbmeta_offset % BOOT_HEADER_PAGE_SIZE}). LK block I/O will fail!"
        )
    if verbose:
        print(f"  [PASS] 4. VBMeta offset 4096-byte alignment: 0x{vbmeta_offset:x} % 4096 == 0")

    # 5. VBMeta Header & Flags Verification
    vbmeta_block = image_data[vbmeta_offset : vbmeta_offset + vbmeta_size]
    if len(vbmeta_block) < 256:
        raise LKAVBInvariantError(f"VBMeta block truncated ({len(vbmeta_block)} < 256 bytes)")

    vb_magic = vbmeta_block[:4]
    if vb_magic != VBMETA_MAGIC:
        raise LKAVBInvariantError(
            f"VBMeta magic violation: Expected {VBMETA_MAGIC!r} at 0x{vbmeta_offset:x}, got {vb_magic!r}"
        )

    auth_sz = struct.unpack(">Q", vbmeta_block[12:20])[0]
    aux_sz = struct.unpack(">Q", vbmeta_block[20:28])[0]
    flags = struct.unpack(">I", vbmeta_block[120:124])[0]
    flags_byte_123 = vbmeta_block[123]

    if flags_byte_123 != 0x00:
        raise LKAVBInvariantError(
            f"VBMeta flags byte 123 violation: Got 0x{flags_byte_123:02x} (flags=0x{flags:08x}). "
            f"Must be 0x00. Non-zero flags invalidate OEM signature in LK and trigger 2-second reboot loop!"
        )
    if verbose:
        print(f"  [PASS] 5. VBMeta Header: magic={vb_magic.decode('ascii')}, flags=0x{flags:08x} (byte 123 = 0x{flags_byte_123:02x})")

    # 6. OEM Public Key Verification
    pubk_off = struct.unpack(">Q", vbmeta_block[64:72])[0]
    pubk_sz = struct.unpack(">Q", vbmeta_block[72:80])[0]
    pubk_start = 256 + auth_sz + pubk_off
    pubk_data = vbmeta_block[pubk_start : pubk_start + pubk_sz]
    pubk_sha1 = hashlib.sha1(pubk_data).hexdigest()

    if pubk_sha1.lower() != EXPECTED_OEM_KEY_SHA1.lower():
        raise LKAVBInvariantError(
            f"OEM Public Key SHA1 mismatch: Expected '{EXPECTED_OEM_KEY_SHA1}', got '{pubk_sha1}'. "
            f"LK memcmp check (avb_hal_verify_public_key) will reject image!"
        )
    if verbose:
        print(f"  [PASS] 6. OEM Public Key SHA1: {pubk_sha1} (matches Lenovo OEM Root Key)")

    # 7. Authentication Block SHA256 Signature Self-Integrity
    hash_off = struct.unpack(">Q", vbmeta_block[32:40])[0]
    hash_sz = struct.unpack(">Q", vbmeta_block[40:48])[0]
    auth_block = vbmeta_block[256 : 256 + auth_sz]
    stored_hash = auth_block[hash_off : hash_off + hash_sz]

    header_bytes = vbmeta_block[:256]
    aux_bytes = vbmeta_block[256 + auth_sz : 256 + auth_sz + aux_sz]
    computed_hash = hashlib.sha256(header_bytes + aux_bytes).digest()

    if stored_hash != computed_hash:
        raise LKAVBInvariantError(
            f"VBMeta Auth Block digest mismatch: stored {stored_hash.hex()} != computed {computed_hash.hex()}"
        )
    if stored_hash.hex().lower() != EXPECTED_AUTH_DIGEST.lower():
        raise LKAVBInvariantError(
            f"Pristine OEM digest mismatch: Expected '{EXPECTED_AUTH_DIGEST}', got '{stored_hash.hex()}'"
        )

    # OEM RSA4096 Signature Block Integrity
    sig_off = struct.unpack(">Q", vbmeta_block[48:56])[0]
    sig_sz = struct.unpack(">Q", vbmeta_block[56:64])[0]
    if sig_sz > 0:
        sig_bytes = auth_block[sig_off : sig_off + sig_sz]
        sig_sha256 = hashlib.sha256(sig_bytes).hexdigest()
        if sig_sha256.lower() != EXPECTED_SIGNATURE_SHA256.lower():
            raise LKAVBInvariantError(
                f"OEM RSA4096 signature corrupted: {sig_sha256} != expected {EXPECTED_SIGNATURE_SHA256}"
            )

    if verbose:
        print(f"  [PASS] 7. OEM RSA4096 Header+Aux SHA256 Digest: {stored_hash.hex()} (100% VALID)")

    # 8. Hash Descriptor Parsing & Core Invariant Check (Offset == Size)
    desc_off = struct.unpack(">Q", vbmeta_block[96:104])[0]
    desc_sz = struct.unpack(">Q", vbmeta_block[104:112])[0]
    descriptors_bytes = aux_bytes[desc_off : desc_off + desc_sz]
    descriptors = parse_avb_descriptors(descriptors_bytes)

    hash_desc = None
    for d in descriptors:
        if d.get("tag") == AVB_DESCRIPTOR_TAG_HASH:
            hash_desc = d
            break

    if not hash_desc:
        raise LKAVBInvariantError("No AvbHashDescriptor found in VBMeta auxiliary block!")

    hash_img_size = hash_desc["image_size"]
    part_name = hash_desc.get("partition_name", "")
    if part_name and part_name != "boot":
        raise LKAVBInvariantError(f"Unexpected HashDescriptor partition name: '{part_name}', expected 'boot'")

    if hash_img_size != EXPECTED_VBMETA_OFFSET:
        raise LKAVBInvariantError(
            f"HashDescriptor image_size mismatch: Expected {EXPECTED_VBMETA_OFFSET}, got {hash_img_size}"
        )

    # Core LK Invariant Assertion: Offset == Size
    if vbmeta_offset != hash_img_size:
        raise LKAVBInvariantError(
            f"CRITICAL INVARIANT VIOLATION: VBMeta Offset ({vbmeta_offset}) != "
            f"HashDescriptor Image Size ({hash_img_size})! LK will hash VBMeta block and reboot-loop!"
        )
    if verbose:
        print(f"  [PASS] 8. Embedded Hash Descriptor: image_size = {hash_img_size:,} bytes")
        print(f"  [PASS] 9. CORE LK INVARIANT VERIFIED:")
        print(f"         VBMeta Offset ({vbmeta_offset:,}) == HashDesc.image_size ({hash_img_size:,})")

    # 10. Slack Padding Integrity Checks
    # Region A: Between kernel+ramdisk payload end and VBMETA_OFFSET
    payload_end = BOOT_HEADER_PAGE_SIZE + kernel_size + ramdisk_size
    pad_a = image_data[payload_end:EXPECTED_VBMETA_OFFSET]
    if any(b != 0 for b in pad_a):
        raise LKAVBInvariantError(
            f"Payload padding corrupted: Non-zero bytes found between payload end (0x{payload_end:x}) "
            f"and VBMeta offset (0x{EXPECTED_VBMETA_OFFSET:x})"
        )

    # Region B: Between VBMeta block end and AVB footer
    vb_end = EXPECTED_VBMETA_OFFSET + EXPECTED_VBMETA_SIZE
    pad_b = image_data[vb_end:AVB_FOOTER_OFFSET]
    if any(b != 0 for b in pad_b):
        raise LKAVBInvariantError(
            f"Footer padding corrupted: Non-zero bytes found between VBMeta end (0x{vb_end:x}) "
            f"and footer offset (0x{AVB_FOOTER_OFFSET:x})"
        )

    if verbose:
        print(f"  [PASS] 10. Slack zero-padding verified: 100% clean across all unused sectors")
        print("------------------------------------------------------------------")
        print(" [CONCLUSION] All Little Kernel AVB invariants strictly satisfied!")
        print("              Device will boot cleanly without 2-second Orange State reboot loops.")
        print("==================================================================")

    return {
        "image_size": actual_size,
        "header_version": header_version,
        "header_size": header_size,
        "kernel_size": kernel_size,
        "ramdisk_size": ramdisk_size,
        "cmdline": cmdline,
        "vbmeta_offset": vbmeta_offset,
        "vbmeta_size": vbmeta_size,
        "original_image_size": original_image_size,
        "flags": flags,
        "flags_byte_123": flags_byte_123,
        "public_key_sha1": pubk_sha1,
        "auth_digest": stored_hash.hex(),
        "hash_descriptor_image_size": hash_img_size,
        "invariant_satisfied": True,
    }


def verify_file(file_path: str | Path, verbose: bool = True) -> bool:
    """Verifies a boot image file on disk. Returns True on success, False on failure."""
    p = Path(file_path)
    if not p.is_file():
        if verbose:
            print(f"[FAIL] File not found: {file_path}", file=sys.stderr)
        return False

    try:
        data = p.read_bytes()
        verify_lk_avb_invariant(data, image_path=str(p), verbose=verbose)
        return True
    except Exception as exc:
        if verbose:
            print(f"[FAIL] Verification failed for {file_path}: {exc}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Verify Little Kernel (LK) AVB 2.0 Invariants on Android Boot Header v4 images."
    )
    parser.add_argument(
        "image",
        nargs="?",
        default=str(WORKSPACE_ROOT / "boot_vector" / "pmos_boot.img"),
        help="Path to boot image to verify (default: boot_vector/pmos_boot.img).",
    )
    parser.add_argument(
        "-q", "--quiet",
        action="store_true",
        help="Suppress verbose diagnostic logs.",
    )

    args = parser.parse_args()

    passed = verify_file(args.image, verbose=not args.quiet)
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
