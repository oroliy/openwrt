#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 x6818 port
#
# Generates a bootable SD card or eMMC raw image for S5P6818 x6818.
#
# Layout:
#   Sector 0:          MBR partition table (written by ptgen)
#   Sector 1..0x146E:  Firmware package (NSIH + BL2 + BL31 + U-Boot)
#   Sector 0x4800:     U-Boot persistent environment (reserved raw gap)
#   Sector 0x10000+:   Partition 1 (offset 32 MiB alignment = 65536 sectors):
#                      Boot partition (FAT32, contains kernel Image + DTB)
#   Partition 2:       Rootfs partition (SquashFS + OverlayFS / ext4)

set -e -x

if [ $# -ne 7 ]; then
    echo "SYNTAX: $0 <output_img> <bootfs> <rootfs> <bootfs_size_mb> <rootfs_size_mb> <firmware_channel> <firmware_pkg>"
    exit 1
fi

OUTPUT="$1"
BOOTFS="$2"
ROOTFS="$3"
BOOTFSSIZE="$4"
ROOTFSSIZE="$5"
FIRMWARE_CHANNEL="$6"
FIRMWARE="$7"

if [ -e "$OUTPUT" ] || [ -L "$OUTPUT" ]; then
    echo "refusing to replace existing output: $OUTPUT" >&2
    exit 1
fi
if [ ! -d "$(dirname "$OUTPUT")" ]; then
    echo "output parent is not a directory: $(dirname "$OUTPUT")" >&2
    exit 1
fi

case "$FIRMWARE_CHANNEL" in
    0|2) ;;
    *) echo "invalid firmware channel: $FIRMWARE_CHANNEL" >&2; exit 1 ;;
esac

case "$BOOTFSSIZE" in
    ''|*[!0-9]*) echo "partition sizes must be positive integers" >&2; exit 1 ;;
esac
case "$ROOTFSSIZE" in
    ''|*[!0-9]*) echo "partition sizes must be positive integers" >&2; exit 1 ;;
esac
if [ "$BOOTFSSIZE" -le 0 ] || [ "$ROOTFSSIZE" -le 0 ]; then
    echo "partition sizes must be positive integers" >&2
    exit 1
fi

if [ ! -f "$FIRMWARE" ]; then
    echo "missing firmware package: $FIRMWARE" >&2
    exit 1
fi
if [ ! -f "$BOOTFS" ] || [ ! -f "$ROOTFS" ]; then
    echo "bootfs and rootfs must be regular files" >&2
    exit 1
fi

FIRMWARE_SIZE="$(wc -c < "$FIRMWARE")"
FIRMWARE_FIELDS="$(python3 - "$FIRMWARE" <<'PY'
import struct
import sys

path = sys.argv[1]
data = open(path, "rb").read()
magic = 0x4849534e
bl31_device_addr = 0x10200
bl33_device_addr = 0x20200
bl31_loadaddr = 0x7fe7fc00
bl31_entry = 0x7fe80000
bl33_loadaddr = 0x43bffc00
bl33_entry = 0x43c00000
def nexell_crc(data, polynomial):
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = ((crc >> 1) ^ polynomial) if crc & 1 else crc >> 1
    return crc & 0xffffffff

if len(data) < 0x200:
    raise SystemExit("firmware package is truncated before NSIH")
if struct.unpack_from("<I", data, 0x1fc)[0] != magic:
    raise SystemExit("firmware NSIH magic mismatch at offset 0x1fc")
port = struct.unpack_from("<I", data, 0x50)[0]
if len(data) < 0x20400:
    raise SystemExit("firmware package is truncated before secure stages")
sizes = []
for offset, name in ((0x10000, "BL31"), (0x20000, "BL33")):
    if struct.unpack_from("<I", data, offset + 0x1fc)[0] != magic:
        raise SystemExit(f"{name} secure-header magic mismatch")
    size = struct.unpack_from("<I", data, offset + 0x50)[0]
    if not size or size % 4 or offset + 0x400 + size > len(data):
        raise SystemExit(f"{name} payload is truncated")
    sizes.append(size)
bl2_size = struct.unpack_from("<I", data, 0x44)[0]
if bl2_size < 0x200 or bl2_size > len(data) or bl2_size > 0x10000:
    raise SystemExit("BL2 payload size is outside firmware package")
if (struct.unpack_from("<I", data, 0x40)[0] != bl31_device_addr or
        struct.unpack_from("<I", data, 0x48)[0] != 0xffff0000 or
        struct.unpack_from("<I", data, 0x4c)[0] != 0xffff0000 or
        data[0x57] != 3):
    raise SystemExit("BL2 load/entry/boot-device contract mismatch")
bl2_crc = struct.unpack_from("<I", data, 0x58)[0]
bl2_source = bytes(0x200) + data[0x200:bl2_size]
if nexell_crc(bl2_source, 0x04c11db7) != bl2_crc:
    raise SystemExit("BL2 payload CRC mismatch")
for offset, size, name, polynomial in (
        (0x10000, sizes[0], "BL31", 0xedb88320),
        (0x20000, sizes[1], "BL33", 0xedb88320)):
    payload = data[offset + 0x400:offset + 0x400 + size]
    expected = struct.unpack_from("<I", data, offset + 0x54)[0]
    if nexell_crc(payload, polynomial) != expected:
        raise SystemExit(f"{name} payload CRC mismatch")
secure_contracts = (
    (0x10000, bl31_loadaddr, bl31_entry, bl33_device_addr),
    (0x20000, bl33_loadaddr, bl33_entry, 0),
)
for offset, loadaddr, entry, next_addr in secure_contracts:
    got_loadsize, _, got_loadaddr, got_entry = struct.unpack_from(
        "<IIQQ", data, offset + 0x50)
    got_next = struct.unpack_from("<Q", data, offset + 0xa0)[0]
    if (got_loadaddr != loadaddr or got_entry != entry or
            got_entry != got_loadaddr + 0x400 or got_next != next_addr):
        raise SystemExit("secure image load/entry/next-stage contract mismatch")
if 0x10000 + 0x400 + sizes[0] > 0x20000:
    raise SystemExit("BL31 payload overlaps BL33 header")
print(magic, port, bl2_size, *sizes)
PY
)"
set -- $FIRMWARE_FIELDS
FIRMWARE_MAGIC="$1"
FIRMWARE_PORT="$2"
BL2_SIZE="$3"
BL31_SIZE="$4"
BL33_SIZE="$5"
if [ "$FIRMWARE_PORT" != "$FIRMWARE_CHANNEL" ]; then
    echo "firmware channel $FIRMWARE_PORT does not match expected $FIRMWARE_CHANNEL" >&2
    exit 1
fi

# 32 MiB alignment ensures partitions start at sector 0x10000 (32 MiB),
# leaving plenty of unpartitioned space for:
# - Sector 0: MBR (512 B)
# - Sector 1..0x146E: Firmware package (~2.56 MiB)
# - Sector 0x4800: U-Boot persistent environment (offset 0x900000 = 9 MiB, 32 KiB)
align=32768
head=16
sect=63

# Create partition table: Partition 1 = FAT32 (type c), Partition 2 = Linux (type 83).
if ! PTGEN_FIELDS="$(ptgen -o "$OUTPUT" -h $head -s $sect -l $align -t c -p ${BOOTFSSIZE}M -t 83 -p ${ROOTFSSIZE}M ${SIGNATURE:+-S 0x$SIGNATURE})"; then
    echo "ptgen failed" >&2
    exit 1
fi
set -- $PTGEN_FIELDS
if [ "$#" -ne 4 ]; then
    echo "ptgen returned an invalid partition layout" >&2
    exit 1
fi
for field in "$@"; do
    case "$field" in
        ''|*[!0-9]*) echo "ptgen returned non-numeric offsets" >&2; exit 1 ;;
    esac
done

BOOTOFFSET="$(($1 / 512))"
BOOTSIZE="$(($2 / 512))"
ROOTFSOFFSET="$(($3 / 512))"
ROOTFSSIZE="$(($4 / 512))"
for field in "$1" "$2" "$3" "$4"; do
    if [ "$((field % 512))" -ne 0 ]; then
        echo "ptgen returned unaligned partition fields" >&2
        exit 1
    fi
done
if [ "$BOOTSIZE" -le 0 ] || [ "$ROOTFSSIZE" -le 0 ] ||
   [ "$BOOTOFFSET" -lt "$((32 * 1024 * 1024 / 512))" ]; then
    echo "ptgen returned an invalid partition start or size" >&2
    exit 1
fi
BOOTEND="$((BOOTOFFSET + BOOTSIZE))"
if [ "$ROOTFSOFFSET" -lt "$BOOTEND" ]; then
    echo "ptgen returned overlapping partitions" >&2
    exit 1
fi
ENVSTART="$((0x900000 / 512))"
if [ "$BOOTOFFSET" -le "$ENVSTART" ] && [ "$ENVSTART" -lt "$BOOTEND" ]; then
    echo "boot partition overlaps reserved environment" >&2
    exit 1
fi

if [ "$FIRMWARE_SIZE" -gt "$((0x900000 - 512))" ]; then
    echo "firmware package overlaps reserved environment at 0x900000" >&2
    exit 1
fi
BOOTFS_SIZE="$(wc -c < "$BOOTFS")"
ROOTFS_SIZE="$(wc -c < "$ROOTFS")"
if [ "$BOOTFS_SIZE" -gt "$((BOOTSIZE * 512))" ]; then
    echo "bootfs exceeds partition 1 capacity" >&2
    exit 1
fi
if [ "$ROOTFS_SIZE" -gt "$((ROOTFSSIZE * 512))" ]; then
    echo "rootfs exceeds partition 2 capacity" >&2
    exit 1
fi

# 1. Write firmware package starting at Sector 1 (offset 512 bytes), preserving Sector 0 MBR
dd bs=512 if="$FIRMWARE" of="$OUTPUT" seek=1 conv=notrunc

# Verify that the source header survived the sector-1 placement, using
# explicit little-endian decoding rather than host-endian od output.
python3 - "$OUTPUT" "$FIRMWARE_CHANNEL" <<'PY'
import struct
import sys

data = open(sys.argv[1], "rb").read()
channel = int(sys.argv[2])
if (struct.unpack_from("<I", data, 0x3fc)[0] != 0x4849534e or
        struct.unpack_from("<I", data, 0x250)[0] != channel):
    raise SystemExit("firmware header verification failed after placement")
PY

# 2. Write boot partition
dd bs=512 if="$BOOTFS" of="$OUTPUT" seek="$BOOTOFFSET" conv=notrunc

# 3. Write rootfs partition (with sync to guarantee complete write)
dd bs=512 if="$ROOTFS" of="$OUTPUT" seek="$ROOTFSOFFSET" conv=notrunc,sync

# 4. Zero out padding area after rootfs to avoid stale filesystem signatures
ROOTFSIMGSIZE="$((($(wc -c < "$ROOTFS") + 511) / 512))"
ROOTFSPADDINGSIZE="$(($ROOTFSSIZE - $ROOTFSIMGSIZE))"
ROOTFSPADDINGOFFSET="$(($ROOTFSOFFSET + $ROOTFSIMGSIZE))"
if [ "$ROOTFSPADDINGSIZE" -gt 0 ]; then
    if [ "$ROOTFSPADDINGSIZE" -gt 2048 ]; then
        ROOTFSPADDINGSIZE=2048
    fi
    dd bs=512 if=/dev/zero of="$OUTPUT" seek="$ROOTFSPADDINGOFFSET" count="$ROOTFSPADDINGSIZE" conv=notrunc
fi

# ptgen may leave the tail sparse; retain the complete logical disk size so
# the declared rootfs partition is present through its final sector.
DISKSIZE="$((ROOTFSOFFSET + ROOTFSSIZE))"
truncate -s "$((DISKSIZE * 512))" "$OUTPUT"
