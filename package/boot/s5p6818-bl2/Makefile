# SPDX-License-Identifier: GPL-2.0-only
include $(TOPDIR)/rules.mk

PKG_NAME:=s5p6818-bl2
PKG_VERSION:=2026.09.08
PKG_RELEASE:=2
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/oroliy/x6818-bl2.git
PKG_SOURCE_VERSION:=ae8be7c69f4acd50a0497d6e8feb4485ee2abe22
PKG_MIRROR_HASH:=3ab746f2277e479976d8ce0f19522ab16edcbdd431a0d0a8d477d9e8bd8162e3
PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=COPYING
PKG_FLAGS:=nonshared
PKG_CONFIG_DEPENDS += \
	X6818_ALLOW_NEXELL_TIMER_FALLBACK \
	X6818_BL2_SOURCE_DIR

X6818_BL2_SOURCE_DIR ?=
ifneq ($(strip $(X6818_BL2_SOURCE_DIR)),)
USE_SOURCE_DIR := $(X6818_BL2_SOURCE_DIR)
endif

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/nexell-source.mk

BL2_BUILD_BASE:=$(BUILD_DIR)/$(PKG_NAME)-build
# This product package explicitly opts into the accepted Nexell-timer chain.
# The standalone BL2 source retains its strict-counter default.
X6818_ALLOW_NEXELL_TIMER_FALLBACK ?= y
BL2_ARTIFACT_NAME:=$(if $(filter y,$(X6818_ALLOW_NEXELL_TIMER_FALLBACK)),bl1-x6818-nexell-timer.bin,bl1-x6818-strict-counter.bin)

define Package/s5p6818-bl2
  SECTION:=boot
  CATEGORY:=Boot Loaders
  TITLE:=Nexell S5P6818 AArch64 BL2
  DEPENDS:=@TARGET_nexell_s5p6818_arm64
  BUILDONLY:=1
endef

define Build/Compile
	$(INSTALL_DIR) $(BL2_BUILD_BASE)/obj $(BL2_BUILD_BASE)/out
	+$(MAKE) -C $(PKG_BUILD_DIR) $(PKG_JOBS) \
		DIR_OBJOUTPUT=$(BL2_BUILD_BASE)/obj \
		DIR_TARGETOUTPUT=$(BL2_BUILD_BASE)/out \
		CROSS_TOOL=$(TARGET_CROSS) \
		BOARD=X6818 OPMODE=aarch64 MEMTYPE=DDR3 \
		TARGET_NAME=$(patsubst %.bin,%,$(BL2_ARTIFACT_NAME)) \
		X6818_ALLOW_NEXELL_TIMER_FALLBACK=$(X6818_ALLOW_NEXELL_TIMER_FALLBACK) bin
endef

define Build/InstallDev
	$(INSTALL_DIR) $(STAGING_DIR_IMAGE)/x6818
	$(INSTALL_BIN) $(BL2_BUILD_BASE)/out/$(BL2_ARTIFACT_NAME) \
		$(STAGING_DIR_IMAGE)/x6818/bl2.bin
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/reference-nsih/x6818-sd-64.txt \
		$(STAGING_DIR_IMAGE)/x6818/nsih-sd.txt
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/reference-nsih/x6818-emmc-64.txt \
		$(STAGING_DIR_IMAGE)/x6818/nsih-emmc.txt
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/tools/x6818_sd_pack.py \
		$(STAGING_DIR_IMAGE)/x6818/x6818_sd_pack.py
endef

$(eval $(call BuildPackage,s5p6818-bl2))
