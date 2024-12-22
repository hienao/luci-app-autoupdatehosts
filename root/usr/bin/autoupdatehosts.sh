#!/bin/sh

# 记录开始时间
start_time=$(date +%s)

# 检查是否启用
enabled=$(grep "^enabled:" /etc/AutoUpdateHosts.yaml | cut -d' ' -f2- | tr -d '"')
if [ "$enabled" != "1" ]; then
    logger -t "autoupdatehosts" "服务未启用，跳过更新"
    exit 0
fi

# 检查网络连接
for i in 1 2 3; do
    if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        break
    fi
    if [ $i -eq 3 ]; then
        logger -t "autoupdatehosts" "网络连接失败，跳过更新"
        exit 1
    fi
    sleep 10
done

# 调用 LuCI 的 save_hosts_etc 接口
curl -s "http://localhost/cgi-bin/luci/admin/services/autoupdatehosts/save_hosts_etc" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{}" \
    > /dev/null 2>&1

# 检查执行结果
if [ $? -eq 0 ]; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    logger -t "autoupdatehosts" "定时任务执行成功，耗时 ${duration} 秒"
else
    logger -t "autoupdatehosts" "定时任务执行失败"
    exit 1
fi 