#
# provides Web UI to shut down (power off) your device. 
# Copyright (C) 2022-2023 sirpdboy <herboy2008@gmail.com>
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-autoupdatehosts
PKG_VERSION:=$(shell cat $(CURDIR)/version.txt 2>/dev/null | tr -d 'v[:space:]' || echo "1.0.0")
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=Hienao

LUCI_TITLE:=LuCI support for Auto Update Hosts
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+wget

# 添加语言包依赖
PKG_DEPENDS:=+luci-i18n-autoupdatehosts-zh-cn

# 支持 OpenWrt 18.06 及以上版本
PKG_MINVERSION:=18.06

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

define Package/$(PKG_NAME)/conffiles
/etc/config/autoupdatehosts
endef

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

# 添加语言包定义
define Package/luci-i18n-autoupdatehosts-zh-cn
  $(call Package/$(PKG_NAME))
  TITLE:=luci-app-autoupdatehosts - zh-cn translation
  HIDDEN:=1
  DEFAULT:=LUCI_LANG_zh_Hans||(ALL&&m)
endef

define Package/luci-i18n-autoupdatehosts-zh-cn/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	po2lmo ./po/zh-cn/autoupdatehosts.po $(1)/usr/lib/lua/luci/i18n/autoupdatehosts.zh-cn.lmo
endef

# 语言包定义
define Package/$(PKG_NAME)-i18n-zh-cn
  $(call Package/$(PKG_NAME)/Default)
  TITLE:=$(PKG_NAME) - Chinese translation
  DEPENDS:=$(PKG_NAME)
endef

$(eval $(call BuildPackage,luci-i18n-autoupdatehosts-zh-cn))
