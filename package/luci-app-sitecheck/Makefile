include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Site_Checker
LUCI_DEPENDS:=+luci-base +curl
PKG_NAME:=luci-app-sitecheck
PKG_VERSION:=1.2.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-sitecheck
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=$(LUCI_TITLE)
  DEPENDS:=$(LUCI_DEPENDS)
endef

define Package/luci-app-sitecheck/description
LuCI website checker for OpenWrt.
endef

define Build/Compile
endef

define Package/luci-app-sitecheck/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./files/controller/sitecheck.lua $(1)/usr/lib/lua/luci/controller/sitecheck.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/sitecheck
	$(INSTALL_DATA) ./files/view/index.htm $(1)/usr/lib/lua/luci/view/sitecheck/index.htm
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/sitecheck-check $(1)/usr/libexec/sitecheck-check
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/sitecheck.conf $(1)/etc/config/sitecheck
endef

$(eval $(call BuildPackage,luci-app-sitecheck))
