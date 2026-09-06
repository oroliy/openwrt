# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copyright (C) 2026 x6818 port
#
# Sysupgrade support for Nexell S5P6818 x6818 board.

. /lib/functions.sh

REQUIRE_IMAGE_METADATA=1

platform_check_image() {
	local diskdev partdev diff

	[ "$#" -gt 1 ] && return 1

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}

	get_partitions "/dev/$diskdev" bootdisk

	# Extract the boot sector (MBR) from the image
	get_image "$@" | dd of=/tmp/image.bs count=1 bs=512 2>/dev/null

	get_partitions /tmp/image.bs image

	# Compare partition tables
	diff="$(grep -F -x -v -f /tmp/partmap.bootdisk /tmp/partmap.image)"

	rm -f /tmp/image.bs /tmp/partmap.bootdisk /tmp/partmap.image

	if [ -n "$diff" ]; then
		echo "Partition layout has changed. Full image will be written."
		ask_bool 0 "Abort" && exit 1
		return 0
	fi

	return 0
}

platform_copy_config() {
	local partdev

	if export_partdevice partdev 1; then
		mkdir -p /boot
		[ -f /boot/Image ] || mount -t vfat -o rw,noatime "/dev/$partdev" /boot
		cp -af "$UPGRADE_BACKUP" "/boot/$BACKUP_FILE"
		sync
		umount /boot 2>/dev/null || true
	fi
}

platform_do_upgrade() {
	local diskdev partdev diff

	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device"
		return 1
	}

	sync

	if [ "$UPGRADE_OPT_SAVE_PARTITIONS" = "1" ]; then
		get_partitions "/dev/$diskdev" bootdisk

		# Extract boot sector from the image
		get_image "$@" | dd of=/tmp/image.bs count=1 bs=512 2>/dev/null

		get_partitions /tmp/image.bs image

		# Compare partition tables
		diff="$(grep -F -x -v -f /tmp/partmap.bootdisk /tmp/partmap.image)"
		rm -f /tmp/image.bs /tmp/partmap.bootdisk /tmp/partmap.image
	else
		diff=1
	fi

	if [ -n "$diff" ]; then
		echo "Writing full image to /dev/$diskdev..."
		get_image "$@" | dd of="/dev/$diskdev" bs=2M conv=fsync

		partx -d - "/dev/$diskdev" 2>/dev/null || true
		partx -a - "/dev/$diskdev" 2>/dev/null || true

		return 0
	fi

	# Write updated partitions
	while read part start size; do
		if export_partdevice partdev $part; then
			echo "Writing partition $part to /dev/$partdev..."
			get_image "$@" | dd of="/dev/$partdev" ibs=512 obs=1M skip="$start" count="$size" conv=fsync
		else
			echo "Unable to find partition $part device, skipped."
		fi
	done < /tmp/partmap.image
	rm -f /tmp/partmap.image

	# Preserve MBR signature
	echo "Writing MBR signature..."
	get_image "$@" | dd of="/dev/$diskdev" bs=1 skip=440 count=4 seek=440 conv=fsync
}
