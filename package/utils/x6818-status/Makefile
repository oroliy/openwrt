include $(TOPDIR)/rules.mk

PKG_NAME:=x6818-status
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/x6818-status
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=x6818 LCD4Linux system status screen
  DEPENDS:=+lcd4linux-custom +terminfo +kmod-input-evdev
endef

define Package/x6818-status/conffiles
/etc/x6818-status.conf
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) -Wall -Wextra -Werror $(TARGET_LDFLAGS) \
		-o $(PKG_BUILD_DIR)/x6818-status-vt $(PKG_BUILD_DIR)/status-vt.c
	$(TARGET_CC) $(TARGET_CFLAGS) -Wall -Wextra -Werror $(TARGET_LDFLAGS) \
		-o $(PKG_BUILD_DIR)/x6818-beep-once $(PKG_BUILD_DIR)/beep-once.c
endef

define Package/x6818-status/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/init.d $(1)/etc/uci-defaults $(1)/etc/rc.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/x6818-status-vt $(1)/usr/sbin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/x6818-beep-once $(1)/usr/sbin/
	$(INSTALL_BIN) ./files/x6818-status.init $(1)/etc/init.d/x6818-status
	$(INSTALL_BIN) ./files/95-x6818-status $(1)/etc/uci-defaults/
	$(INSTALL_CONF) ./files/x6818-status.conf $(1)/etc/x6818-status.conf
	chmod 600 $(1)/etc/x6818-status.conf
endef

$(eval $(call BuildPackage,x6818-status))
