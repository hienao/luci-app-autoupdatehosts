#!/bin/sh

# 调用 LuCI 的 save_hosts_etc 接口
curl -s "http://localhost/cgi-bin/luci/admin/services/autoupdatehosts/save_hosts_etc" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{}" \
    > /dev/null 2>&1

# 记录日志
logger -t "autoupdatehosts" "定时任务执行完成" 