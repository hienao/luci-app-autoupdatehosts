#
# provides Web UI to shut down (power off) your device. 
# Copyright (C) 2022-2023 sirpdboy <herboy2008@gmail.com>
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

NAME:=autoupdatehosts
PKG_NAME:=luci-app-$(NAME)
LUCI_TITLE:=LuCI support for autoupdatehosts
LUCI_DESCRIPTION:=Auto update hosts file from URLs

LUCI_PKGARCH:=all
PKG_VERSION:=1
PKG_RELEASE:=4

define Package/$(PKG_NAME)/conffiles
/etc/AutoUpdateHosts.yaml
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
