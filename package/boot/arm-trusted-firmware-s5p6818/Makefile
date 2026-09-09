# SPDX-License-Identifier: GPL-2.0-only
include $(TOPDIR)/rules.mk

PKG_NAME:=arm-trusted-firmware-s5p6818
PKG_VERSION:=2.12.14
PKG_LTS:=1
PKG_RELEASE:=1
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/oroliy/x6818-tfa.git
PKG_SOURCE_VERSION:=a7dae5badba79aad90d08e3fdd254a0cec855cea
PKG_LICENSE:=BSD-3-Clause
PKG_LICENSE_FILES:=docs/license.rst
PKG_FLAGS:=nonshared

X6818_TFA_SOURCE_DIR ?= $(wildcard $(TOPDIR)/../firmware-lts/tfa)
USE_SOURCE_DIR ?= $(X6818_TFA_SOURCE_DIR)

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

# The Nexell fork's commit is locally reproducible, but its remote commit and
# a release mirror hash are not verified here.  Require the reviewed source
# export until that download gate is opened.
define Build/Prepare
	@test -n "$(USE_SOURCE_DIR)" || { echo "arm-trusted-firmware-s5p6818: USE_SOURCE_DIR is required; release source gate is closed"; exit 1; }
	@test -d "$(USE_SOURCE_DIR)" || { echo "arm-trusted-firmware-s5p6818: missing USE_SOURCE_DIR=$(USE_SOURCE_DIR)"; exit 1; }
	$(Build/Prepare/Default)
endef

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
