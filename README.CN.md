[autoupdatehosts 自动订阅hosts更新](luci-app-autoupdatehosts)
==========================================

[![](https://img.shields.io/badge/-目录:-696969.svg)](#readme) [![](https://img.shields.io/badge/-使用说明-F5F5F5.svg)](#使用说明-) [![](https://img.shields.io/badge/-说明-F5F5F5.svg)](#说明-) [![](https://img.shields.io/badge/-捐助-F5F5F5.svg)](#捐助-) 

请 **认真阅读完毕** 本页面，本页面包含注意事项和如何使用。

autoupdatehosts是一款基于OPNEWRT编译的自动更新hosts源码插件。
-----------------------------------------

## 写在前面：
----------------------------------
此源码未经过大量测试，不确定是否能兼容哪些路由系统版本，建议有足够的动手能力再安装该插件，安装使用前请务必做好路由系统备份

## 设置截图

![设置截图](/screen/screen.png)

## 使用说明 [![](https://img.shields.io/badge/-使用说明-F5F5F5.svg)](#使用说明-) 

订阅中添加更新地址,如：https://raw.githubusercontent.com/cnwikee/CheckTMDB/refs/heads/main/Tmdb_host_ipv4，设置定时任务（也可以不用定时任务），���存设置或保存hosts文件即可

## 使用与授权相关说明
 
- 本人开源的所有源码，任何引用需注明本处出处，如需修改二次发布必告之本人，未经许可不得做于任何商用用途。

## 版本历史

### v1.0.0 (2024-03-21)
- 初始版本发布
- 支持自动更新 hosts 文件
- 支持多个订阅源
- 支持定时更新
- 支持备份和还原

<a href="#readme">
    <img src="https://img.shields.io/badge/-返回顶部-orange.svg" alt="图飞了😂" title="返回顶部" align="right"/>
</a> 