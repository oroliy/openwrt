# SPDX-License-Identifier: GPL-2.0-only
include $(TOPDIR)/rules.mk

PKG_NAME:=arm-trusted-firmware-s5p6818
PKG_VERSION:=2.12.14
PKG_LTS:=1
PKG_RELEASE:=2
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/oroliy/x6818-tfa.git
PKG_SOURCE_VERSION:=a7dae5badba79aad90d08e3fdd254a0cec855cea
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-lts-v$(PKG_VERSION)
PKG_MIRROR_HASH:=c4e297f9943611b382d2d865d5887840bfeb68508f5eb0e3be3e0c1fcc68a667
PKG_LICENSE:=BSD-3-Clause
PKG_LICENSE_FILES:=docs/license.rst
PKG_FLAGS:=nonshared
PKG_CONFIG_DEPENDS += X6818_TFA_SOURCE_DIR

X6818_TFA_SOURCE_DIR ?=
ifneq ($(strip $(X6818_TFA_SOURCE_DIR)),)
USE_SOURCE_DIR := $(X6818_TFA_SOURCE_DIR)
endif

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/trusted-firmware-a.mk
include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/nexell-source.mk

TFA_BUILD_BASE:=$(BUILD_DIR)/$(PKG_NAME)-build

define Trusted-Firmware-A/Default
	BUILD_TARGET:=nexell
	BUILD_SUBTARGET:=s5p6818_arm64
	BUILD_DEVICES:=nexell_x6818_arm64
endef

define Trusted-Firmware-A/s5p6818
	NAME:=Nexell S5P6818
	PLAT:=s5p6818
	TFA_IMAGE:=bl31.bin
endef

TFA_TARGETS:=s5p6818
TFA_MAKE_FLAGS+= \
	DEBUG=0 \
	BUILD_BASE=$(TFA_BUILD_BASE) \
	BL31_BASE=0x7fe80000 \
	PRELOADED_BL33_BASE=0x43c00000
TFA_MAKE_FLAGS+= bl31

define Build/InstallDev
	$(INSTALL_DIR) $(STAGING_DIR_IMAGE)/x6818
	$(INSTALL_BIN) $(TFA_BUILD_BASE)/s5p6818/release/bl31.bin \
		$(STAGING_DIR_IMAGE)/x6818/bl31.bin
endef

define Package/trusted-firmware-a-s5p6818/install
	$(INSTALL_DIR) $(1)
	$(INSTALL_BIN) $(TFA_BUILD_BASE)/s5p6818/release/bl31.bin $(1)/bl31.bin
endef

$(eval $(call BuildPackage/Trusted-Firmware-A))
