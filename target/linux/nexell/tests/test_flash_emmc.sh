#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tool="$root/base-files/usr/sbin/x6818-flash-emmc"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
not_expect() { if "$@"; then fail "unexpected success: $*"; fi; }

[ -f "$tool" ] || fail "tool $tool missing"
[ -x "$tool" ] || fail "tool $tool not executable"

# 1. Missing arguments
not_expect "$tool"
echo "ok: missing arguments rejected"

# 2. Nonexistent image
not_expect "$tool" "$tmp/nonexistent.img"
echo "ok: nonexistent image rejected"

# 3. Invalid MBR
touch "$tmp/zero.img"
not_expect "$tool" "$tmp/zero.img" "$tmp/dummy_dev"
echo "ok: invalid MBR rejected"

# 4. Valid MBR but missing NSIH magic
python3 -c '
img = bytearray(2048)
img[510:512] = b"\x55\xaa"
open("'$tmp'/no_nsih.img", "wb").write(img)
'
not_expect "$tool" "$tmp/no_nsih.img" "$tmp/dummy_dev"
echo "ok: missing NSIH rejected"

# 5. SD Channel 0 firmware image (refuse to flash SD image to eMMC)
python3 -c '
import struct
img = bytearray(2048)
img[510:512] = b"\x55\xaa"
# NSIH magic at offset 0x200 + 0x1fc = 1020
struct.pack_into("<I", img, 1020, 0x4849534e)
# NSIH channel at offset 0x200 + 0x50 = 592 -> 0 (SD)
img[592] = 0
open("'$tmp'/sd_channel0.img", "wb").write(img)
'
not_expect "$tool" "$tmp/sd_channel0.img" "$tmp/dummy_dev"
echo "ok: channel 0 SD firmware refused for eMMC target"

# 6. Valid eMMC Channel 2 image
python3 -c '
import struct
img = bytearray(2048)
img[510:512] = b"\x55\xaa"
# NSIH magic at offset 1020
struct.pack_into("<I", img, 1020, 0x4849534e)
# NSIH channel at offset 592 -> 2 (eMMC)
img[592] = 2
open("'$tmp'/emmc_channel2.img", "wb").write(img)
'

# Create mock target device
touch "$tmp/mock_target_emmc"
# Set up a fake /proc/mounts mock
mock_proc="$tmp/proc"
mkdir -p "$mock_proc"
echo "/dev/mmcblk1p2 / overlay rw 0 0" > "$mock_proc/mounts"

# Run tool with mock target
# Override /proc/mounts check via subshell environment or file target
TARGET_DEV="$tmp/mock_target_emmc"
sh -c "$tool '$tmp/emmc_channel2.img' '$TARGET_DEV'"

# Check that mock target has been written and headers match
rb_mbr="$(dd if="$TARGET_DEV" bs=1 skip=510 count=2 2>/dev/null | hexdump -v -n 2 -e '1/1 "%02x"')"
[ "$rb_mbr" = "55aa" ] || fail "mock target MBR verification failed"

rb_nsih="$(dd if="$TARGET_DEV" bs=1 skip=1020 count=4 2>/dev/null | hexdump -v -n 4 -e '1/1 "%02x"')"
[ "$rb_nsih" = "4e534948" ] || fail "mock target NSIH verification failed"

echo "ok: valid eMMC image flashed and verified on target block device"
echo "flash emmc recovery tests: PASS"
