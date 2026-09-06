# SPDX-License-Identifier: GPL-2.0-only
#
# Nexell S5P6818 x6818 firmware package (binary blob)
#
# Packages pre-built BL2 (2ndboot), TF-A BL31, and U-Boot BL33 into
# composite firmware images for SD card and eMMC boot, using the
# x6818_sd_pack.py assembly tool.
#
# This is the "Option B" quick-integration approach. A future
# source-build package can replace this once the full OpenWrt build
# chain is validated.

include $(TOPDIR)/rules.mk

PKG_NAME:=nexell-firmware
PKG_VERSION:=2026.09.07
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-or-later BSD-3-Clause
PKG_FLAGS:=nonshared

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

# ── Source tree references (within the port workspace) ──
# These paths are relative to the port workspace root, resolved via
# the TOPDIR/../../ escape from openwrt/ back to port/.
PORT_ROOT:=$(TOPDIR)/..
BL2_SRC:=$(PORT_ROOT)/firmware-lts/bl2
TFA_SRC:=$(PORT_ROOT)/firmware-lts/tfa
UBOOT_SRC:=$(PORT_ROOT)/uboot-lts

BL2_BIN:=$(BL2_SRC)/out/bl1-x6818.bin
BL31_BIN:=$(TFA_SRC)/build/s5p6818/release/bl31.bin
# Use the AArch64 U-Boot from the staging build
BL33_BIN:=$(PORT_ROOT)/tmp/builds/uboot-x6818-arm64-stage3/u-boot.bin

NSIH_SD:=$(BL2_SRC)/reference-nsih/x6818-sd-64.txt
NSIH_EMMC:=$(BL2_SRC)/reference-nsih/x6818-emmc-64.txt
PACK_TOOL:=$(BL2_SRC)/tools/x6818_sd_pack.py

PYTHON_CMD:=$(if $(wildcard $(STAGING_DIR_HOST)/bin/python3),$(STAGING_DIR_HOST)/bin/python3,python3)

define Package/nexell-firmware
  SECTION:=boot
  CATEGORY:=Boot Loaders
  TITLE:=Nexell S5P6818 x6818 firmware
  DEPENDS:=@TARGET_nexell
  BUILDONLY:=1
endef

define Package/nexell-firmware/description
  Pre-built firmware components for the Nexell S5P6818 x6818 board:
  BL2 (2ndboot), ARM Trusted Firmware BL31, and U-Boot v2026.07 BL33.
  Assembled into composite SD card and eMMC boot images.
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
endef

define Build/Compile
	# ── Assemble SD card firmware image ──
	rm -f $(PKG_BUILD_DIR)/x6818-firmware-sd.img
	$(PYTHON_CMD) $(PACK_TOOL) \
		--nsih $(NSIH_SD) \
		--bl2 $(BL2_BIN) \
		--bl31 $(BL31_BIN) \
		--bl33 $(BL33_BIN) \
		--output $(PKG_BUILD_DIR)/x6818-firmware-sd.img
	# ── Assemble eMMC firmware image ──
	rm -f $(PKG_BUILD_DIR)/x6818-firmware-emmc.img
	$(PYTHON_CMD) $(PACK_TOOL) \
		--nsih $(NSIH_EMMC) \
		--bl2 $(BL2_BIN) \
		--bl31 $(BL31_BIN) \
		--bl33 $(BL33_BIN) \
		--output $(PKG_BUILD_DIR)/x6818-firmware-emmc.img
endef

define Build/InstallDev
	$(INSTALL_DIR) $(STAGING_DIR_IMAGE)
	$(CP) $(PKG_BUILD_DIR)/x6818-firmware-sd.img $(STAGING_DIR_IMAGE)/
	$(CP) $(PKG_BUILD_DIR)/x6818-firmware-emmc.img $(STAGING_DIR_IMAGE)/
endef

$(eval $(call BuildPackage,nexell-firmware))
