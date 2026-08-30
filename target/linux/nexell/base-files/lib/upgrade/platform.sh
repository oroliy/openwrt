PART_NAME=firmware

platform_check_image() {
	echo "Sysupgrade is not supported on the x6818 RAM-initramfs target." >&2
	return 1
}

platform_do_upgrade() {
	# RAM bring-up milestone: sysupgrade is not supported yet.
	return 1
}
