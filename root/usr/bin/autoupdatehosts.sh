#!/bin/sh

# 定义日志文件路径
LOG_FILE="/tmp/auto_update_host/log.txt"

# 写入日志函数
write_log() {
    local msg="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # 确保日志目录存在
    mkdir -p /tmp/auto_update_host
    
    # 写入日志
    echo "[$timestamp] $msg" >> "$LOG_FILE"
}

# 加载配置文件
SETTINGS_FILE="/etc/auto_update_host/settings.yaml"
HOSTS_FILE="/etc/hosts"

write_log "开始自动更新hosts..."

# 检查配置文件是否存在
if [ ! -f "$SETTINGS_FILE" ]; then
    write_log "配置文件不存在: $SETTINGS_FILE"
    exit 1
fi

# 读取配置文件中的URLs
urls=$(awk '/^[[:space:]]*-/ {print $2}' "$SETTINGS_FILE")
if [ -z "$urls" ]; then
    write_log "未找到有效的订阅URL"
    exit 1
fi

# 获取当前hosts文件的非订阅内容
if [ -f "$HOSTS_FILE" ]; then
    before_mark=$(sed -n '1,/##订阅hosts内容开始/p' "$HOSTS_FILE" | grep -v "##订阅hosts内容开始")
    after_mark=$(sed -n '/##订阅hosts内容结束/,$p' "$HOSTS_FILE" | grep -v "##订阅hosts内容结束")
else
    before_mark=""
    after_mark=""
fi

# 创建临时文件
temp_file="/tmp/hosts.temp"
echo "$before_mark" > "$temp_file"
echo -e "\n##订阅hosts内容开始（程序自动更新请勿手动修改中间内容）##" >> "$temp_file"
# 添加更新时间戳
echo -e "# 更新时间：$(date '+%Y-%m-%d %H:%M:%S')\n" >> "$temp_file"

# 下载并合并hosts内容
success=0
for url in $urls; do
    write_log "正在获取URL内容: $url"
    if wget -qO- "$url" >> "$temp_file" 2>/dev/null; then
        write_log "成功获取内容: $url"
        success=1
    else
        write_log "获取内容失败: $url"
    fi
done

if [ $success -eq 0 ]; then
    write_log "所有URL获取失败"
    rm -f "$temp_file"
    exit 1
fi

# 添加结束标记和剩余内容
echo -e "\n##订阅hosts内容结束（程序自动更新请勿手动修改中间内容）##" >> "$temp_file"
echo "$after_mark" >> "$temp_file"

# 移除多余的空行
sed -i '/^$/N;/^\n$/D' "$temp_file"

# 更新hosts文件
if mv "$temp_file" "$HOSTS_FILE"; then
    write_log "hosts文件更新成功"
    # 重启dnsmasq服务
    /etc/init.d/dnsmasq restart
    write_log "已重启dnsmasq服务"
else
    write_log "hosts文件更新失败"
    rm -f "$temp_file"
    exit 1
fi

write_log "自动更新hosts完成"
exit 0 