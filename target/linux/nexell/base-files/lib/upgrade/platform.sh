# SPDX-License-Identifier: GPL-2.0-or-later

# The x6818 disk layout, image metadata and recovery/config-restore path have
# not completed board acceptance.  Keep every sysupgrade entry point closed:
# no partition probe, mount, or block-device write is safe to expose yet.
REQUIRE_IMAGE_METADATA=1

platform_check_image() {
	echo "Nexell x6818 sysupgrade is not yet supported; refusing image"
	return 1
}

platform_copy_config() {
	echo "Nexell x6818 configuration restore is not yet supported"
	return 1
}

platform_do_upgrade() {
	echo "Nexell x6818 sysupgrade is not yet supported; refusing upgrade"
	return 1
}
