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

if [ $# -ne 6 ]; then
    echo "SYNTAX: $0 <output_img> <bootfs> <rootfs> <bootfs_size_mb> <rootfs_size_mb> <firmware_pkg>"
    exit 1
fi

OUTPUT="$1"
BOOTFS="$2"
ROOTFS="$3"
BOOTFSSIZE="$4"
ROOTFSSIZE="$5"
FIRMWARE="$6"

# 32 MiB alignment ensures partitions start at sector 0x10000 (32 MiB),
# leaving plenty of unpartitioned space for:
# - Sector 0: MBR (512 B)
# - Sector 1..0x146E: Firmware package (~2.56 MiB)
# - Sector 0x4800: U-Boot persistent environment (offset 0x900000 = 9 MiB, 32 KiB)
align=32768
head=16
sect=63

# Create partition table: Partition 1 = FAT32 (type c), Partition 2 = Linux (type 83)
set $(ptgen -o "$OUTPUT" -h $head -s $sect -l $align -t c -p ${BOOTFSSIZE}M -t 83 -p ${ROOTFSSIZE}M ${SIGNATURE:+-S 0x$SIGNATURE})

BOOTOFFSET="$(($1 / 512))"
BOOTSIZE="$(($2 / 512))"
ROOTFSOFFSET="$(($3 / 512))"
ROOTFSSIZE="$(($4 / 512))"

# 1. Write firmware package starting at Sector 1 (offset 512 bytes), preserving Sector 0 MBR
if [ -n "$FIRMWARE" ] && [ -f "$FIRMWARE" ]; then
    dd bs=512 if="$FIRMWARE" of="$OUTPUT" seek=1 conv=notrunc
fi

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
