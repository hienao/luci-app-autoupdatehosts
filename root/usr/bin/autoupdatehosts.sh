#!/bin/sh

start_mark="##订阅hosts内容开始（程序自动更新请勿手动修改中间内容）##"
end_mark="##订阅hosts内容结束（程序自动更新请勿手动修改中间内容）##"

# 获取当前hosts内容
current_hosts=$(cat /etc/hosts)

# 提取标记之外的内容
before_mark=$(echo "$current_hosts" | sed -n "1,/$start_mark/p" | grep -v "$start_mark")
after_mark=$(echo "$current_hosts" | sed -n "/$end_mark/,\$p" | grep -v "$end_mark")

# 获取配置的URLs
urls=$(uci get autoupdatehosts.@config[0].urls)

# 获取新的hosts内容
new_content=""
for url in $urls; do
    content=$(wget -qO- "$url")
    new_content="$new_content\n$content"
done

# 组合新的hosts文件
final_content="${before_mark}\n${start_mark}\n${new_content}\n${end_mark}\n${after_mark}"

# 保存到hosts文件
echo -e "$final_content" > /etc/hosts

# 重启dnsmasq使更改生效
/etc/init.d/dnsmasq restart 