# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2026 x6818 port

include $(TOPDIR)/rules.mk

BOARD:=nexell
BOARDNAME:=Nexell S5P6818
FEATURES:=fpu ramdisk ext4 squashfs rootfs-part boot-part
SUBTARGETS:=s5p6818 s5p6818_arm64

KERNEL_PATCHVER:=6.12

DEFAULT_PACKAGES += partx-utils mkf2fs e2fsprogs

include $(INCLUDE_DIR)/target.mk

$(eval $(call BuildTarget))
