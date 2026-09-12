# SPDX-License-Identifier: GPL-2.0-only
#
# U-Boot v2026.07 for the Nexell S5P6818 x6818 AArch64 chain.

include $(TOPDIR)/rules.mk

PKG_NAME:=uboot-s5p6818
PKG_VERSION:=2026.07
PKG_RELEASE:=2
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/oroliy/x6818-uboot.git
PKG_SOURCE_VERSION:=877cb2c828dd404aebb09eb3b4055e945c601590
PKG_MIRROR_HASH:=14589680d90b7a5b25144e07d65eadcb5c9e71f4a9a72c77f933906248514f4c
PKG_LICENSE:=GPL-2.0-only
PKG_CONFIG_DEPENDS += X6818_UBOOT_SOURCE_DIR

X6818_UBOOT_SOURCE_DIR ?=
ifneq ($(strip $(X6818_UBOOT_SOURCE_DIR)),)
USE_SOURCE_DIR := $(X6818_UBOOT_SOURCE_DIR)
endif

include $(INCLUDE_DIR)/u-boot.mk
include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/nexell-source.mk

UBOOT_OUTPUT_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)-output

define U-Boot/Default
  BUILD_TARGET:=nexell
  BUILD_SUBTARGET:=s5p6818_arm64
  BUILD_DEVICES:=nexell_x6818_arm64
  NAME:=Nexell S5P6818 x6818
  UBOOT_IMAGE:=u-boot.bin
  UBOOT_CONFIG:=x6818_arm64
endef

define Package/u-boot/install
	$(CP) $(UBOOT_OUTPUT_DIR)/u-boot.bin $(1)/
endef

UBOOT_TARGETS:=x6818_arm64
UBOOT_CONFIGURE_VARS += O=$(UBOOT_OUTPUT_DIR)
UBOOT_MAKE_FLAGS += O=$(UBOOT_OUTPUT_DIR)

define Build/InstallDev
	$(INSTALL_DIR) $(STAGING_DIR_IMAGE)/x6818
	$(INSTALL_BIN) $(UBOOT_OUTPUT_DIR)/u-boot.bin $(STAGING_DIR_IMAGE)/x6818/u-boot.bin
endef

$(eval $(call BuildPackage/U-Boot))
