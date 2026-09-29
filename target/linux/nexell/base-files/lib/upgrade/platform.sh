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

x6818_image_bytes() {
	local image="$1" dir bytes pid stream_ok=0

	dir="$(busybox mktemp -d /tmp/x6818-image.XXXXXX)" || return 1
	busybox mkfifo "$dir/stream" || { rmdir "$dir"; return 1; }
	get_image "$image" > "$dir/stream" &
	pid=$!
	if ! bytes="$(wc -c < "$dir/stream")"; then
		bytes=""
	fi
	if wait "$pid"; then
		stream_ok=1
	fi
	rm -f "$dir/stream"
	rmdir "$dir"
	[ "$stream_ok" -eq 1 ] || return 1
	set -- $bytes
	[ "$#" -eq 1 ] || return 1
	bytes="$1"
	case "$bytes" in
		''|*[!0-9]*) return 1 ;;
	esac
	printf '%s\n' "$bytes"
}

x6818_partition_sectors() {
	local dev="${1##*/}" sectors

	[ -r "/sys/class/block/$dev/size" ] || return 1
	read -r sectors < "/sys/class/block/$dev/size" || return 1
	case "$sectors" in
		''|*[!0-9]*) return 1 ;;
	esac
	printf '%s\n' "$sectors"
}

x6818_partition_start() {
	local dev="${1##*/}" start

	[ -r "/sys/class/block/$dev/start" ] || return 1
	read -r start < "/sys/class/block/$dev/start" || return 1
	case "$start" in
		''|*[!0-9]*) return 1 ;;
	esac
	printf '%s\n' "$start"
}

x6818_disk_signature() {
	local disk="$1"

	case "$disk" in
		/*) ;;
		*) disk="/dev/$disk" ;;
	esac
	[ -b "$disk" ] || return 1
	dd if="$disk" bs=1 skip=440 count=4 2>/dev/null |
		hexdump -v -e '4/1 "%02x"'
}

x6818_write_partition() {
	local image="$1" node="$2" start="$3" sectors="$4"
	local log records full partial

	log="$(busybox mktemp /tmp/x6818-dd.XXXXXX)" || return 1
	if ! get_image "$image" 2>/dev/null |
		dd of="$node" ibs=512 obs=1M iflag=fullblock \
			skip="$start" count="$sectors" conv=fsync 2>"$log"; then
		cat "$log" >&2
		rm -f "$log"
		return 1
	fi
	records="$(sed -n '1s/ records in$//p' "$log")"
	rm -f "$log"
	case "$records" in
		*+*) ;;
		*) echo "Missing dd input-record count for $node" >&2; return 1 ;;
	esac
	full="${records%%+*}"
	partial="${records#*+}"
	case "$full:$partial" in
		*[!0-9:]*|:*|*:) echo "Invalid dd input-record count: $records" >&2; return 1 ;;
	esac
	[ "$full" -eq "$sectors" ] && [ "$partial" -eq 0 ] || {
		echo "Short partition write to $node: $records of $sectors records in" >&2
		return 1
	}
	return 0
}

platform_check_image() {
	local image="$1"
	local diskdev partdev1 partdev2

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade boot disk"
		return 1
	}

	# Verify MBR signature at offset 510
	local magic
	magic="$(get_image "$image" 2>/dev/null | dd bs=1 skip=510 count=2 2>/dev/null | hexdump -v -n 2 -e '1/1 "%02x"')"
	if [ "$magic" != "55aa" ]; then
		echo "Image missing valid MBR signature (expected 55aa, got $magic)"
		return 1
	fi
	local image_signature target_signature
	image_signature="$(get_image "$image" 2>/dev/null |
		dd bs=1 skip=440 count=4 2>/dev/null | hexdump -v -e '4/1 "%02x"')"
	target_signature="$(x6818_disk_signature "$diskdev")" || {
		echo "Unable to read installed disk signature"
		return 1
	}
	case "$image_signature" in
		''|00000000) echo "Image disk signature is missing"; return 1 ;;
	esac
	[ "$image_signature" = "$target_signature" ] || {
		echo "Image disk signature does not match installed MBR"
		return 1
	}
	local p1_start p1_size p2_start p2_size image_bytes expected_bytes
	local target_p1_start target_p2_start target_p1_size target_p2_size
	set -- $(get_image "$image" 2>/dev/null | dd bs=1 skip=454 count=8 2>/dev/null |
		hexdump -v -e '8/1 "%02x "')
	[ "$#" -eq 8 ] || { echo "Image boot partition entry is truncated"; return 1; }
	p1_start=$((0x$4$3$2$1))
	p1_size=$((0x$8$7$6$5))
	set -- $(get_image "$image" 2>/dev/null | dd bs=1 skip=470 count=8 2>/dev/null |
		hexdump -v -e '8/1 "%02x "')
	[ "$#" -eq 8 ] || { echo "Image partition table is truncated"; return 1; }
	p2_start=$((0x$4$3$2$1))
	p2_size=$((0x$8$7$6$5))
	[ "$p1_start" -gt 0 ] && [ "$p1_size" -gt 0 ] &&
		[ "$p2_start" -ge "$((p1_start + p1_size))" ] &&
		[ "$p2_size" -gt 0 ] || {
		echo "Image partition layout is invalid or overlapping"
		return 1
	}
	export_partdevice partdev1 1 && export_partdevice partdev2 2 || {
		echo "Unable to determine installed partitions"
		return 1
	}
	target_p1_size="$(x6818_partition_sectors "$partdev1")" &&
		target_p2_size="$(x6818_partition_sectors "$partdev2")" &&
		target_p1_start="$(x6818_partition_start "$partdev1")" &&
		target_p2_start="$(x6818_partition_start "$partdev2")" || {
		echo "Unable to read installed partition geometry"
		return 1
	}
	[ "$p1_start" -eq "$target_p1_start" ] &&
		[ "$p2_start" -eq "$target_p2_start" ] || {
		echo "Image partition starts differ from installed MBR"
		return 1
	}
	[ "$p1_size" -le "$target_p1_size" ] &&
		[ "$p2_size" -le "$target_p2_size" ] || {
		echo "Image partitions exceed installed capacities (p1 $p1_size/$target_p1_size, p2 $p2_size/$target_p2_size sectors)"
		return 1
	}
	expected_bytes=$(( (p2_start + p2_size) * 512 ))
	image_bytes="$(x6818_image_bytes "$image")" || {
		echo "Unable to read the complete image"
		return 1
	}
	[ "$image_bytes" -eq "$expected_bytes" ] || {
		echo "Image length $image_bytes does not match partition end $expected_bytes"
		return 1
	}

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
			if ! cp -af "$UPGRADE_BACKUP" "$mnt_dir/$BACKUP_FILE"; then
				umount "$mnt_dir" || true
				rmdir "$mnt_dir" 2>/dev/null || true
				echo "Failed copying configuration archive to $p_node"
				return 1
			fi
			sync
			if ! umount "$mnt_dir"; then
				echo "Failed unmounting $p_node after configuration copy"
				return 1
			fi
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

	# Stage2 must revalidate before the first write: the image may have changed
	# since procd ran platform_check_image in the normal userspace.
	platform_check_image "$image" || return 1

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
	mbr_tmp="$(busybox mktemp -t mbr.XXXXXX 2>/dev/null || echo "/tmp/mbr.$$.bin")"
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
	x6818_write_partition "$image" "$p1_node" "$p1_start" "$p1_size" || {
		echo "Failed writing boot partition $p1_node"
		return 1
	}

	v "Streaming partition 2 (Rootfs) to $p2_node (skip $p2_start, count $p2_size)..."
	x6818_write_partition "$image" "$p2_node" "$p2_start" "$p2_size" || {
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
