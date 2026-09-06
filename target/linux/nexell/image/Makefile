# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 x6818 port

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

FAT32_BLOCK_SIZE=1024
FAT32_BLOCKS=$(shell echo $$(($(CONFIG_TARGET_KERNEL_PARTSIZE)*1024*1024/$(FAT32_BLOCK_SIZE))))

### Image scripts ###
define Build/boot-common
	rm -rf $@.boot
	mkfs.fat -n boot -C $@.boot $(FAT32_BLOCKS)
	mcopy -i $@.boot $(IMAGE_KERNEL) ::Image
	mcopy -i $@.boot $(KDIR)/image-s5p6818-x6818.dtb ::s5p6818-x6818-arm64.dtb
endef

define Build/nexell-sdcard
	SIGNATURE="$(IMG_PART_SIGNATURE)" \
	./gen_nexell_disk_img.sh $@ \
		$@.boot \
		$(IMAGE_ROOTFS) \
		$(CONFIG_TARGET_KERNEL_PARTSIZE) \
		$(CONFIG_TARGET_ROOTFS_PARTSIZE) \
		$(STAGING_DIR_IMAGE)/x6818-firmware-sd.img
	rm -rf $@.boot
endef

define Build/nexell-emmc
	SIGNATURE="$(IMG_PART_SIGNATURE)" \
	./gen_nexell_disk_img.sh $@ \
		$@.boot \
		$(IMAGE_ROOTFS) \
		$(CONFIG_TARGET_KERNEL_PARTSIZE) \
		$(CONFIG_TARGET_ROOTFS_PARTSIZE) \
		$(STAGING_DIR_IMAGE)/x6818-firmware-emmc.img
	rm -rf $@.boot
endef

include ./$(SUBTARGET).mk

$(eval $(call BuildImage))
