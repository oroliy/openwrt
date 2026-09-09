# SPDX-License-Identifier: GPL-2.0-only
#
# Nexell S5P6818 x6818 firmware composite package
#
# Packages source-built/staged BL2 (2ndboot), TF-A BL31, and U-Boot BL33 into
# composite firmware images for SD card and eMMC boot, using the
# x6818_sd_pack.py assembly tool.
#
include $(TOPDIR)/rules.mk

PKG_NAME:=nexell-firmware
PKG_VERSION:=2026.09.07
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-or-later BSD-3-Clause
PKG_FLAGS:=nonshared
PKG_TARGETS:=bin

PKG_BUILD_DEPENDS:=s5p6818-bl2 arm-trusted-firmware-s5p6818 uboot-s5p6818

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

X6818_STAGE:= $(STAGING_DIR_IMAGE)/x6818
BL2_BIN:=$(X6818_STAGE)/bl2.bin
BL31_BIN:=$(X6818_STAGE)/bl31.bin
BL33_BIN:=$(X6818_STAGE)/u-boot.bin
NSIH_SD:=$(X6818_STAGE)/nsih-sd.txt
NSIH_EMMC:=$(X6818_STAGE)/nsih-emmc.txt
PACK_TOOL:=$(X6818_STAGE)/x6818_sd_pack.py
PYTHON_CMD:=$(if $(wildcard $(STAGING_DIR_HOST)/bin/python3),$(STAGING_DIR_HOST)/bin/python3,$(shell which python3))
STAMP_BUILT_DEPENDS += $(BL2_BIN) $(BL31_BIN) $(BL33_BIN) $(NSIH_SD) $(NSIH_EMMC) $(PACK_TOOL)

define Package/nexell-firmware
  SECTION:=boot
  CATEGORY:=Boot Loaders
  TITLE:=Nexell S5P6818 x6818 firmware
  DEPENDS:=@TARGET_nexell_s5p6818_arm64
endef

define Package/nexell-firmware/description
  Source-built/staged firmware components for the Nexell S5P6818 x6818 board:
  BL2 (2ndboot), ARM Trusted Firmware BL31, and U-Boot v2026.07 BL33.
  Assembled into composite SD card and eMMC boot images.
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
endef

define Build/Compile
	@test -x $(PYTHON_CMD) || { echo "missing staged host python3: $(PYTHON_CMD)" >&2; exit 1; }
	@test -x $(PACK_TOOL) || { echo "missing staged x6818_sd_pack.py" >&2; exit 1; }
	@test -f $(BL2_BIN) -a -f $(BL31_BIN) -a -f $(BL33_BIN) || { echo "missing staged x6818 boot component" >&2; exit 1; }
	@test -f $(NSIH_SD) -a -f $(NSIH_EMMC) || { echo "missing staged x6818 NSIH" >&2; exit 1; }
	# ── Assemble SD card firmware image ──
	rm -f $(PKG_BUILD_DIR)/x6818-firmware-sd.img $(PKG_BUILD_DIR)/x6818-firmware-emmc.img
	$(PYTHON_CMD) $(PACK_TOOL) \
		--nsih $(NSIH_SD) \
		--bl2 $(BL2_BIN) \
		--bl31 $(BL31_BIN) \
		--bl33 $(BL33_BIN) \
		--output $(PKG_BUILD_DIR)/x6818-firmware-sd.img
	$(PYTHON_CMD) $(PACK_TOOL) \
		--nsih $(NSIH_EMMC) \
		--bl2 $(BL2_BIN) \
		--bl31 $(BL31_BIN) \
		--bl33 $(BL33_BIN) \
		--output $(PKG_BUILD_DIR)/x6818-firmware-emmc.img
endef

define Build/InstallDev
	$(INSTALL_DIR) $(STAGING_DIR_IMAGE)/x6818
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/x6818-firmware-sd.img $(STAGING_DIR_IMAGE)/x6818-firmware-sd.img
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/x6818-firmware-emmc.img $(STAGING_DIR_IMAGE)/x6818-firmware-emmc.img
endef

define Package/nexell-firmware/install
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/x6818-firmware-sd.img $(1)/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/x6818-firmware-emmc.img $(1)/
endef

$(eval $(call BuildPackage,nexell-firmware))
