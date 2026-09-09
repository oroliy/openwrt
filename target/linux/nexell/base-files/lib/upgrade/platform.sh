# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copyright (C) 2026 x6818 port
#
# Safe, partition-based streaming sysupgrade for Nexell S5P6818 (x6818).
#
# Key Safety Principles:
# 1. Strictly avoid direct full-disk dd over raw block device.
#    Preserves Sector 0 (MBR), Sector 1..0x146E (Firmware package),
#    Sector 0x4800 (offset 0x900000 = U-Boot persistent environment),
#    and preserves the board's expanded Partition 2 boundary (e.g. 7.2GB).
# 2. Extract and stream write Partition 1 (Boot FAT32) and Partition 2 (Rootfs SquashFS)
#    directly into their respective partition block devices.
# 3. Preserve configuration via FAT32 Boot partition ($BACKUP_FILE / sysupgrade.tgz)
#    which is restored by preinit hook (79_move_config) on first boot.

REQUIRE_IMAGE_METADATA=1

platform_check_image() {
	local image="$1"
	local diskdev

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade boot disk"
		return 1
	}

	# Verify MBR signature at offset 510
	local magic
	magic="$(get_image "$image" | dd bs=1 skip=510 count=2 2>/dev/null | hexdump -v -n 2 -e '1/1 "%02x"')"
	if [ "$magic" != "55aa" ]; then
		echo "Image missing valid MBR signature (expected 55aa, got $magic)"
		return 1
	fi

	return 0
}

platform_copy_config() {
	local partdev p_node
	local mnt_dir="/tmp/sysupgrade_boot"

	if export_partdevice partdev 1; then
		case "$partdev" in
			/*) p_node="$partdev" ;;
			*)  p_node="/dev/$partdev" ;;
		esac
		mkdir -p "$mnt_dir"
		if mount -t vfat -o rw,noatime "$p_node" "$mnt_dir" 2>/dev/null || mount -o rw,noatime "$p_node" "$mnt_dir"; then
			cp -af "$UPGRADE_BACKUP" "$mnt_dir/$BACKUP_FILE"
			sync
			umount "$mnt_dir"
			rmdir "$mnt_dir" 2>/dev/null || true
			v "Configuration successfully stored to boot partition ($p_node)"
			return 0
		else
			rmdir "$mnt_dir" 2>/dev/null || true
			echo "Failed to mount $p_node for saving configuration"
			return 1
		fi
	fi
	return 1
}

platform_do_upgrade() {
	local image="$1"
	local diskdev partdev1 partdev2

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade boot disk"
		return 1
	}

	export_partdevice partdev1 1 || {
		echo "Unable to determine boot partition (p1) device"
		return 1
	}

	export_partdevice partdev2 2 || {
		echo "Unable to determine rootfs partition (p2) device"
		return 1
	}

	sync

	# Extract MBR partition table using dd + hexdump (works in minimal ramfs without python)
	local mbr_tmp
	mbr_tmp="$(mktemp -t mbr.XXXXXX 2>/dev/null || echo "/tmp/mbr.$$.bin")"
	get_image "$image" | dd of="$mbr_tmp" bs=512 count=1 2>/dev/null

	local p1_hex p1_sz_hex p2_hex p2_sz_hex
	local p1_start p1_size p2_start p2_size

	p1_hex="$(dd if="$mbr_tmp" bs=1 skip=454 count=4 2>/dev/null | hexdump -v -e '4/1 "%02x "')"
	p1_sz_hex="$(dd if="$mbr_tmp" bs=1 skip=458 count=4 2>/dev/null | hexdump -v -e '4/1 "%02x "')"
	p2_hex="$(dd if="$mbr_tmp" bs=1 skip=470 count=4 2>/dev/null | hexdump -v -e '4/1 "%02x "')"
	p2_sz_hex="$(dd if="$mbr_tmp" bs=1 skip=474 count=4 2>/dev/null | hexdump -v -e '4/1 "%02x "')"
	rm -f "$mbr_tmp"

	set -- $p1_hex
	p1_start=$((0x$4$3$2$1))
	set -- $p1_sz_hex
	p1_size=$((0x$4$3$2$1))

	set -- $p2_hex
	p2_start=$((0x$4$3$2$1))
	set -- $p2_sz_hex
	p2_size=$((0x$4$3$2$1))

	# Sanity check extracted geometry
	if [ "$p1_size" -le 0 ] || [ "$p2_size" -le 0 ] || [ "$p1_start" -ge "$p2_start" ]; then
		echo "Invalid partition table extracted from image (p1: $p1_start+$p1_size, p2: $p2_start+$p2_size)"
		return 1
	fi

	local p1_node p2_node
	case "$partdev1" in
		/*) p1_node="$partdev1" ;;
		*)  p1_node="/dev/$partdev1" ;;
	esac
	case "$partdev2" in
		/*) p2_node="$partdev2" ;;
		*)  p2_node="/dev/$partdev2" ;;
	esac

	v "Streaming partition 1 (Boot FAT32) to $p1_node (skip $p1_start, count $p1_size)..."
	get_image "$image" | dd of="$p1_node" ibs=512 obs=1M skip="$p1_start" count="$p1_size" conv=fsync 2>/dev/null || {
		echo "Failed writing boot partition $p1_node"
		return 1
	}

	v "Streaming partition 2 (Rootfs) to $p2_node (skip $p2_start, count $p2_size)..."
	get_image "$image" | dd of="$p2_node" ibs=512 obs=1M skip="$p2_start" count="$p2_size" conv=fsync 2>/dev/null || {
		echo "Failed writing rootfs partition $p2_node"
		return 1
	}

	# Clean stale overlay signature if requested to not keep settings
	if [ -z "$UPGRADE_BACKUP" ] || [ "${UPGRADE_OPT_SAVE_PARTITIONS:-1}" = "0" ]; then
		v "Clearing overlay signature on $p2_node after rootfs..."
		dd if=/dev/zero of="$p2_node" bs=512 seek="$p2_size" count=2048 conv=fsync 2>/dev/null || true
	fi

	sync
	return 0
}
