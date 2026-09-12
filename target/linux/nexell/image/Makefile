# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 x6818 port

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

NEXELL_KERNEL_PARTSIZE:=$(if $(CONFIG_TARGET_KERNEL_PARTSIZE),$(CONFIG_TARGET_KERNEL_PARTSIZE),64)
NEXELL_ROOTFS_PARTSIZE:=$(if $(CONFIG_TARGET_ROOTFS_PARTSIZE),$(CONFIG_TARGET_ROOTFS_PARTSIZE),256)
NEXELL_PARTUUID:=$(if $(IMG_PART_SIGNATURE),$(IMG_PART_SIGNATURE),5452574F)

FAT32_BLOCK_SIZE=1024
FAT32_BLOCKS=$(shell echo $$(($(NEXELL_KERNEL_PARTSIZE)*1024*1024/$(FAT32_BLOCK_SIZE))))

### Image scripts ###
define Build/boot-common
	rm -rf $@.boot
	mkfs.fat -n boot -C $@.boot $(FAT32_BLOCKS)
	mmd -i $@.boot ::extlinux
	mcopy -i $@.boot $(IMAGE_KERNEL) ::Image
	mcopy -i $@.boot $(KDIR)/image-s5p6818-x6818-nexell-timer.dtb ::s5p6818-x6818-nexell-timer.dtb
	mcopy -i $@.boot ./logo.bmp ::logo.bmp
	printf '%s\n' 'TIMEOUT 1' 'DEFAULT x6818' 'LABEL x6818' '  KERNEL /Image' '  FDT /s5p6818-x6818-nexell-timer.dtb' '  APPEND console=ttySAC0,115200 earlycon=s5p6818,mmio,0xc00a1000 root=PARTUUID=$(NEXELL_PARTUUID)-02 rootwait rw fstools_overlay_fstype=ext4' > $@.extlinux
	mcopy -i $@.boot $@.extlinux ::extlinux/extlinux.conf
	rm -f $@.extlinux
endef

define Build/nexell-sdcard
	SIGNATURE="$(NEXELL_PARTUUID)" \
	./gen_nexell_disk_img.sh $@ \
		$@.boot \
		$(IMAGE_ROOTFS) \
		$(NEXELL_KERNEL_PARTSIZE) \
		$(NEXELL_ROOTFS_PARTSIZE) \
		0 \
		$(STAGING_DIR_IMAGE)/x6818-firmware-sd.img
	rm -rf $@.boot
endef

define Build/nexell-emmc
	SIGNATURE="$(NEXELL_PARTUUID)" \
	./gen_nexell_disk_img.sh $@ \
		$@.boot \
		$(IMAGE_ROOTFS) \
		$(NEXELL_KERNEL_PARTSIZE) \
		$(NEXELL_ROOTFS_PARTSIZE) \
		2 \
		$(STAGING_DIR_IMAGE)/x6818-firmware-emmc.img
	rm -rf $@.boot
endef

include ./$(SUBTARGET).mk

$(eval $(call BuildImage))
