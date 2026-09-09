# SPDX-License-Identifier: GPL-2.0-only
#
# U-Boot v2026.07 for the Nexell S5P6818 x6818 AArch64 chain.

include $(TOPDIR)/rules.mk

PKG_NAME:=uboot-s5p6818
PKG_VERSION:=2026.07
PKG_RELEASE:=1
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/oroliy/x6818-uboot.git
PKG_SOURCE_VERSION:=0ef95b71f30aff73043b87ad2e5e4cb6ce553986
PKG_LICENSE:=GPL-2.0-only

X6818_UBOOT_SOURCE_DIR ?= $(wildcard $(TOPDIR)/../uboot-lts)
USE_SOURCE_DIR ?= $(X6818_UBOOT_SOURCE_DIR)

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

define Build/Prepare
	@test -n "$(USE_SOURCE_DIR)" || { echo "$(PKG_NAME) requires X6818_UBOOT_SOURCE_DIR=/path/to/x6818-20260908-source until the source is published" >&2; exit 1; }
	$(Build/Prepare/Default)
endef

define Build/InstallDev
	$(INSTALL_DIR) $(STAGING_DIR_IMAGE)/x6818
	$(INSTALL_BIN) $(UBOOT_OUTPUT_DIR)/u-boot.bin $(STAGING_DIR_IMAGE)/x6818/u-boot.bin
endef

$(eval $(call BuildPackage/U-Boot))
