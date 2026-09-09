#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
platform="$root/base-files/lib/upgrade/platform.sh"
preinit="$root/base-files/lib/preinit/79_move_config"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
not_expect() { if "$@"; then fail "unexpected success: $*"; fi; }

# Helper: mock get_image
get_image() {
	cat "$1"
}
v() { :; }

# 1. Test fail-closed behavior when boot device cannot be discovered
export_bootdevice() { return 1; }
export_partdevice() { return 1; }

. "$platform"

printf "bad_image" > "$tmp/bad_image"
not_expect platform_check_image "$tmp/bad_image"
not_expect platform_do_upgrade "$tmp/bad_image"
not_expect platform_copy_config
echo "ok: rejected upgrade when boot device is missing"

# 2. Test rejection of image with invalid MBR signature
export_bootdevice() { return 0; }
export_partdevice() {
	case "$2" in
		0) eval "$1=mmcblk0"; return 0 ;;
		1) eval "$1=mmcblk0p1"; return 0 ;;
		2) eval "$1=mmcblk0p2"; return 0 ;;
		*) return 1 ;;
	esac
}

python3 -c '
# Create invalid image (missing 0x55aa)
data = bytearray(512)
open("'$tmp'/invalid_mbr.img", "wb").write(data)
'
not_expect platform_check_image "$tmp/invalid_mbr.img"
echo "ok: rejected image with invalid MBR signature"

# 3. Create a valid mock disk image with MBR partition table
# p1: start 64 (sector 64 = 32KB), size 128 (64KB)
# p2: start 192 (sector 192 = 96KB), size 256 (128KB)
python3 -c '
import struct
total_sectors = 512
img = bytearray(total_sectors * 512)
# MBR signature
img[510:512] = b"\x55\xaa"
# Partition 1: type 0x0c (FAT32), start 64, size 128
struct.pack_into("<BxxxII", img, 446 + 4, 0x0c, 64, 128)
# Partition 2: type 0x83 (Linux), start 192, size 256
struct.pack_into("<BxxxII", img, 462 + 4, 0x83, 192, 256)

# Fill partition 1 payload with pattern "BOOT_PAYLOAD_"
p1_payload = b"BOOT_PAYLOAD_" * (128 * 512 // 13)
img[64 * 512:64 * 512 + len(p1_payload)] = p1_payload

# Fill partition 2 payload with pattern "ROOT_PAYLOAD_"
p2_payload = b"ROOT_PAYLOAD_" * (256 * 512 // 13)
img[192 * 512:192 * 512 + len(p2_payload)] = p2_payload

open("'$tmp'/valid_test.img", "wb").write(img)
'

# Test platform_check_image succeeds on valid MBR
platform_check_image "$tmp/valid_test.img" || fail "valid image check failed"
echo "ok: platform_check_image passed on valid image"

# 4. Test platform_do_upgrade:
# Set up mock target block devices
mkdir -p "$tmp/dev"
touch "$tmp/dev/mmcblk0"
touch "$tmp/dev/mmcblk0p1"
touch "$tmp/dev/mmcblk0p2"

# Mock export_partdevice to point to mock files
export_partdevice() {
	case "$2" in
		0) eval "$1=$tmp/dev/mmcblk0"; return 0 ;;
		1) eval "$1=$tmp/dev/mmcblk0p1"; return 0 ;;
		2) eval "$1=$tmp/dev/mmcblk0p2"; return 0 ;;
		*) return 1 ;;
	esac
}

export UPGRADE_BACKUP=""
export UPGRADE_OPT_SAVE_PARTITIONS=1

platform_do_upgrade "$tmp/valid_test.img" || fail "platform_do_upgrade failed"

# Verify that Partition 1 and Partition 2 received the exact payloads
[ -s "$tmp/dev/mmcblk0p1" ] || fail "boot partition device mmcblk0p1 is empty"
[ -s "$tmp/dev/mmcblk0p2" ] || fail "rootfs partition device mmcblk0p2 is empty"

# Verify mmcblk0 (raw disk) was NOT overwritten directly
[ ! -s "$tmp/dev/mmcblk0" ] || fail "raw disk device mmcblk0 was touched! direct dd must not be used!"

# Verify payload contents
grep -q "BOOT_PAYLOAD_" "$tmp/dev/mmcblk0p1" || fail "mmcblk0p1 does not contain boot payload"
grep -q "ROOT_PAYLOAD_" "$tmp/dev/mmcblk0p2" || fail "mmcblk0p2 does not contain root payload"
echo "ok: platform_do_upgrade stream-wrote p1 and p2 without touching raw disk device"

# 5. Test platform_copy_config
export BACKUP_FILE="sysupgrade.tgz"
export UPGRADE_BACKUP="$tmp/test_backup.tgz"
echo "MOCK_BACKUP_CONTENT" > "$UPGRADE_BACKUP"

copied_backup=""
mount() {
	local target
	for target in "$@"; do :; done
	cp "$UPGRADE_BACKUP" "$target/$BACKUP_FILE"
	copied_backup="$target/$BACKUP_FILE"
	return 0
}
umount() {
	# Verify that backup file was indeed written before umount
	[ -f "$copied_backup" ] || return 1
	return 0
}
rmdir() { return 0; }

platform_copy_config || fail "platform_copy_config failed"
echo "ok: platform_copy_config preserved configuration"

# 6. Test 79_move_config (preinit hook)
[ -f "$preinit" ] || fail "79_move_config missing"
boot_hook_add() { :; }
. "$preinit"

# Mock mount to place backup file in mounted boot partition
mount() {
	local target
	for target in "$@"; do :; done
	echo "MOCK_BACKUP_FOR_RESTORE" > "$target/$BACKUP_FILE"
	return 0
}
umount() { return 0; }

# Mock root / target by running in test environment
restored_in_root=0
mv() {
	# When 79_move_config calls: mv -f "$mnt_dir/$BACKUP_FILE" /
	if [ "$3" = "/" ]; then
		restored_in_root=1
	fi
	return 0
}

move_config
[ "$restored_in_root" -eq 1 ] || fail "79_move_config failed to restore backup archive to /"
echo "ok: 79_move_config successfully restored backup file from boot partition"

echo "all upgrade tests: PASS"

