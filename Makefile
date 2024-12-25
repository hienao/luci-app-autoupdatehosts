#
# provides Web UI to shut down (power off) your device. 
# Copyright (C) 2022-2023 sirpdboy <herboy2008@gmail.com>
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-autoupdatehosts
PKG_VERSION:=1
PKG_RELEASE:=4

LUCI_TITLE:=LuCI support for autoupdatehosts
LUCI_DESCRIPTION:=Auto update hosts file from URLs
LUCI_DEPENDS:=+luci-base

# 修改语言包配置
LUCI_PKGARCH:=all
LUCI_LANG_zh-cn:=1

define Package/$(PKG_NAME)/conffiles
/etc/config/autoupdatehosts
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/autoupdatehosts
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/autoupdatehosts
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	
	$(INSTALL_DATA) ./luasrc/controller/*.lua $(1)/usr/lib/lua/luci/controller/
	$(INSTALL_DATA) ./luasrc/view/autoupdatehosts/* $(1)/usr/lib/lua/luci/view/autoupdatehosts/
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/autoupdatehosts/* $(1)/www/luci-static/resources/view/autoupdatehosts/
	$(INSTALL_DATA) ./root/etc/config/autoupdatehosts $(1)/etc/config/
	$(INSTALL_BIN) ./root/etc/init.d/autoupdatehosts $(1)/etc/init.d/
	$(INSTALL_BIN) ./root/usr/bin/autoupdatehosts.sh $(1)/usr/bin/
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/*.json $(1)/usr/share/rpcd/acl.d/
endef
