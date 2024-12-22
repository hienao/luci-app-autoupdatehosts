module("luci.controller.autoupdatehosts", package.seeall)

-- 添加日志函数
local function write_log(level, msg)
    local fs = require "nixio.fs"
    local logfile = "/tmp/autoupdatehosts.log"
    local max_size = 1024 * 1024  -- 1MB
    
    -- 确保日志文件存在
    if not fs.access(logfile) then
        fs.writefile(logfile, "")
    end
    
    -- 检查日志文件大小
    local size = fs.stat(logfile, "size") or 0
    if size > max_size then
        -- 保留最后 100 行
        local sys = require "luci.sys"
        sys.exec(string.format("tail -n 100 %s > %s.tmp && mv %s.tmp %s", logfile, logfile, logfile, logfile))
        write_log("info", "日志文件已超过1MB，已自动清理")
    end
    
    -- 获取当前时间
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    -- 格式化日志消息
    local log_msg = string.format("[%s] [%s] %s\n", timestamp, level, msg)
    
    -- 读取现有日志
    local current_log = fs.readfile(logfile) or ""
    -- 追加新日志
    fs.writefile(logfile, current_log .. log_msg)
end

-- 添加 YAML 配置文件路径
local YAML_CONFIG = "/etc/AutoUpdateHosts.yaml"

-- 添加 YAML 处理函数
local function load_yaml()
    local fs = require "nixio.fs"
    local content = fs.readfile(YAML_CONFIG)
    if not content then
        return {}
    end
    
    -- 简单的 YAML 解析
    local config = {}
    for line in content:gmatch("[^\r\n]+") do
        local key, value = line:match("^%s*([^:]+):%s*(.+)%s*$")
        if key and value then
            -- 移除引号
            value = value:gsub("^['\"](.+)['\"]$", "%1")
            config[key] = value
        end
    end
    return config
end

local function save_yaml(config)
    local fs = require "nixio.fs"
    local content = ""
    for key, value in pairs(config) do
        -- 如果值包含特殊字符，添加引号
        if value:match("[%s:]") then
            value = string.format('"%s"', value)
        end
        content = content .. string.format("%s: %s\n", key, value)
    end
    return fs.writefile(YAML_CONFIG, content)
end

function index()
    if not nixio.fs.access("/etc/config/autoupdatehosts") then
        return
    end

    local e = entry({"admin", "services", "autoupdatehosts"}, 
        alias("admin", "services", "autoupdatehosts", "setting"),
        _("Auto Update Hosts"), 60)
    e.dependent = false
    e.acl_depends = { "luci-app-autoupdatehosts" }

    entry({"admin", "services", "autoupdatehosts", "setting"}, cbi("autoupdatehosts"), _("Base Setting"), 20).leaf = true
    entry({"admin", "services", "autoupdatehosts", "log"}, template("autoupdatehosts/log"), _("Log"), 30).leaf = true
    entry({"admin", "services", "autoupdatehosts", "get_current_hosts"}, call("get_current_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "preview"}, call("preview_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "get_config"}, call("get_config")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "save_config"}, call("save_config")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "get_log"}, call("get_log")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "fetch_hosts"}, call("fetch_hosts"), nil).leaf = true
    entry({"admin", "services", "autoupdatehosts", "save_hosts_etc"}, call("save_hosts_etc")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "backup_hosts"}, call("backup_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "fetch_backup_hosts"}, call("fetch_backup_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "clear_log"}, call("clear_log")).leaf = true
end

function get_current_hosts()
    local fs = require "nixio.fs"
    local hosts_file = "/etc/hosts"
    local hosts_content = fs.readfile(hosts_file) or "# No hosts content"
    
    -- 设置���应类型为纯文本
    luci.http.prepare_content("text/plain")
    luci.http.write(hosts_content)
end

function get_config()
    local uci = require "luci.model.uci".cursor()
    local yaml_config = load_yaml()
    
    -- 优先使用 YAML 配置，如果不存在则使用 UCI 配置
    local config = {
        enabled = yaml_config.enabled or uci:get_first("autoupdatehosts", "config", "enabled") or "0",
        urls = yaml_config.urls or uci:get_first("autoupdatehosts", "config", "urls") or "",
        schedule = yaml_config.schedule or uci:get_first("autoupdatehosts", "config", "schedule") or "",
        backup_path = yaml_config.backup_path or uci:get_first("autoupdatehosts", "config", "backup_path") or "/etc/hosts.bak"
    }
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(config)
end

function fetch_url_content(url)
    local sys = require "luci.sys"
    local max_retries = 3
    local retry_delay = 3  -- seconds
    
    for i = 1, max_retries do
        -- 使用 wget 命令获取内容
        local content = sys.exec(string.format("wget -qO- '%s'", url:gsub("'", "'\\''")))
        
        if content and #content > 0 then
            write_log("info", string.format("成功获取URL内容: %s (大小: %d字节)", url, #content))
            return content
        end
        
        -- 如果 wget 失败，尝试使用 curl
        content = sys.exec(string.format("curl -sfL '%s'", url:gsub("'", "'\\''")))
        
        if content and #content > 0 then
            write_log("info", string.format("使用curl成功获取URL内容: %s (大小: %d字节)", url, #content))
            return content
        end
        
        if i < max_retries then
            write_log("warning", string.format("第%d次获取失败，%d秒后重试: %s", i, retry_delay, url))
            sys.exec(string.format("sleep %d", retry_delay))
        end
    end
    
    write_log("error", string.format("在%d次尝试后获取URL内容失败: %s", max_retries, url))
    return ""
end

function preview_hosts()
    local fs = require "nixio.fs"
    
    -- 从请求中获取 URLs
    local urls = luci.http.formvalue("urls")
    if not urls or urls == "" then
        luci.http.prepare_content("text/plain")
        luci.http.write("# No URLs provided")
        return
    end
    
    -- 读取当前 hosts 文件
    local current_hosts = fs.readfile("/etc/hosts") or ""
    
    -- 定义标确保每个标记都有正确的换行
    local start_mark = "\n##订阅hosts内容开始（程序自动更新请勿手动修改中间内容）##\n"
    local end_mark = "\n##订阅hosts内容结束（程序自动更新请勿手动修改中间内容）##\n"
    
    -- 检查是否存在标记
    local has_marks = current_hosts:find("##订阅hosts内容开始") and current_hosts:find("##订阅hosts内容结束")
    
    local before_mark, after_mark
    
    if has_marks then
        -- 如果存在标记，移除旧的订阅内容
        before_mark = current_hosts:match("(.-)%s*##订阅hosts内容开始")
        after_mark = current_hosts:match("##订阅hosts内容结束.-##%s*(.*)")
    else
        -- 如果不存在标记，将整个当前内容作为 before_mark
        before_mark = current_hosts
        after_mark = ""
    end
    
    -- 确保 before_mark 和 after_mark 有正确的结尾和开头
    before_mark = (before_mark or ""):gsub("%s*$", "\n")
    after_mark = (after_mark or ""):gsub("^%s*", "\n")
    
    -- 获取新的订阅内容
    local new_content = ""
    for url in urls:gmatch("[^\r\n]+") do
        local content = fetch_url_content(url)
        if content and #content > 0 then
            -- 确保每个URL的内容前后都有换行
            new_content = new_content .. content:gsub("^%s*(.-)%s*$", "%1") .. "\n"
        end
    end
    
    -- 组合最终内容，确保各部分之间有正确的换行
    local result = before_mark .. start_mark .. new_content .. end_mark .. after_mark
    
    -- 移除多余的空行
    result = result:gsub("\n\n+", "\n\n")
    
    luci.http.prepare_content("text/plain")
    luci.http.write(result)
end

function save_config()
    local uci = require "luci.model.uci".cursor()
    local sys = require "luci.sys"
    local data = luci.http.formvalue()
    
    -- 验证备份路径
    if not data.backup_path or data.backup_path == "" then
        data.backup_path = "/etc/hosts.bak"
    end
    
    -- 验证 URLs 格式
    if data.urls and data.urls ~= "" then
        local valid_urls = {}
        for url in data.urls:gmatch("[^\r\n]+") do
            if url:match("^https?://") then
                table.insert(valid_urls, url)
            else
                write_log("warning", string.format("忽略无效URL: %s", url))
            end
        end
        data.urls = table.concat(valid_urls, "\n")
    end
    
    -- 验证 Cron 表达式
    if data.schedule and data.schedule ~= "" then
        if not data.schedule:match("^%s*[%d*]+ [%d*]+ [%d*]+ [%d*]+ [%d*]+%s*$") then
            write_log("error", "无效的 Cron 表达式")
            luci.http.prepare_content("application/json")
            luci.http.write_json({code = 1, msg = "无效的 Cron 表达式"})
            return
        end
    end
    
    -- 保存到 UCI
    uci:foreach("autoupdatehosts", "config", function(s)
        uci:delete("autoupdatehosts", s[".name"])
    end)
    
    local config = uci:section("autoupdatehosts", "config", nil, {
        enabled = data.enabled,
        urls = data.urls,
        schedule = data.schedule,
        backup_path = data.backup_path or "/etc/hosts.bak"
    })
    
    uci:commit("autoupdatehosts")
    
    -- 同时保存到 YAML
    local yaml_config = {
        enabled = data.enabled,
        urls = data.urls,
        schedule = data.schedule,
        backup_path = data.backup_path or "/etc/hosts.bak"
    }
    
    if save_yaml(yaml_config) then
        write_log("info", "配置已保存到 YAML 文件")
    else
        write_log("error", "保存 YAML 配置失败")
    end
    
    -- 确保脚本有执行权限
    sys.exec("chmod +x /usr/bin/autoupdatehosts.sh")
    
    -- 先移除旧的定时任务
    sys.exec("sed -i '/luci-autoupdatehosts/d' /etc/crontabs/root")
    
    -- 只有在启用状态且设置了更新计划才添加定时任务
    if data.enabled == "1" and data.schedule and data.schedule ~= "" then
        sys.exec(string.format("echo '%s /usr/bin/autoupdatehosts.sh' >> /etc/crontabs/root", data.schedule))
        write_log("info", string.format("添加定时任务: %s", data.schedule))
    else
        write_log("info", "未设置定时任务")
    end
    
    -- 重启 cron 服务
    sys.exec("/etc/init.d/cron restart")
    
    luci.http.prepare_content("application/json")
    luci.http.write_json({code = 0, msg = "保存成功"})
end

function get_log()
    local sys = require "luci.sys"
    local logfile = "/tmp/autoupdatehosts.log"
    
    -- 确保日志文件存在
    if not sys.exec("test -f " .. logfile .. " && echo 'exists'") then
        luci.http.prepare_content("application/json")
        luci.http.write_json({log = "暂无日志记录"})
        return
    end
    
    -- 使用 root 权限读取日志
    local log_content = sys.exec("cat " .. logfile) or ""
    
    -- 如果日志内容太长，只返回最后100行
    local result = sys.exec("tail -n 100 " .. logfile) or ""
    
    luci.http.prepare_content("application/json")
    luci.http.write_json({log = result})
end

function fetch_hosts()
    local fs = require "nixio.fs"
    local hosts_file = "/etc/hosts"
    local hosts_content = fs.readfile(hosts_file) or "# No hosts content"
    
    -- ���置响应类型为纯文本
    luci.http.prepare_content("text/plain")
    luci.http.write(hosts_content)
end

function save_hosts_etc()
    local fs = require "nixio.fs"
    local sys = require "luci.sys"
    local uci = require "luci.model.uci".cursor()
    
    write_log("info", "开始执行 save_hosts_etc")
    
    -- 读取当前 hosts 文件
    local current_hosts = fs.readfile("/etc/hosts")
    if not current_hosts then
        write_log("error", "读取 hosts 文件失败")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "读取 hosts 文件失败"})
        return
    end
    write_log("info", string.format("当前 hosts 文件大小: %d 字节", #current_hosts))
    
    -- 定义标
    local start_mark = "\n##订阅hosts内容开始（程序自动更新请勿手动修改中间内容）##\n"
    local end_mark = "\n##订阅hosts内容结束（程序自动更新请勿手动修改中间内容）##\n"
    
    -- 提取原始内容（不包含标记之间的内容）
    local before_mark, after_mark
    if current_hosts:find("##订阅hosts内容开始") and current_hosts:find("##订阅hosts内容结束") then
        before_mark = current_hosts:match("(.-)%s*##订阅hosts内容开始")
        after_mark = current_hosts:match("##订阅hosts内容结束.-##%s*(.*)")
    else
        before_mark = current_hosts
        after_mark = ""
    end
    
    -- 确保 before_mark 和 after_mark 有正确的结尾和开头
    before_mark = (before_mark or ""):gsub("%s*$", "\n")
    after_mark = (after_mark or ""):gsub("^%s*", "\n")
    
    -- 从 YAML 配置获取 URLs
    local yaml_config = load_yaml()
    local urls = yaml_config.urls
    
    -- 如果 YAML 中没有，则从 UCI 获取
    if not urls or urls == "" then
        urls = uci:get_first("autoupdatehosts", "config", "urls") or ""
    end
    
    if urls == "" then
        write_log("error", "未配置 URLs")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "未配置 URLs"})
        return
    end
    
    write_log("info", string.format("获取到 URLs 配置: %s", urls))
    
    -- 获取新的订阅内容
    local new_content = ""
    local valid_entries = 0
    local invalid_entries = 0
    for url in urls:gmatch("[^\r\n]+") do
        local content = fetch_url_content(url)
        if content and #content > 0 then
            -- 验证每一行的格式
            for line in content:gmatch("[^\r\n]+") do
                -- 跳过注释和空行
                if not line:match("^%s*#") and not line:match("^%s*$") then
                    -- 检查是否符合 hosts 文件格式
                    local ip, domain = line:match("^%s*([%d%.]+)%s+([%S]+)%s*$")
                    if ip and domain then
                        new_content = new_content .. string.format("%s %s\n", ip, domain)
                        valid_entries = valid_entries + 1
                    else
                        invalid_entries = invalid_entries + 1
                        write_log("warning", string.format("忽略无效的hosts条目: %s", line))
                    end
                else
                    new_content = new_content .. line .. "\n"
                end
            end
        end
    end
    
    write_log("info", string.format("处理完成: %d 个有效条目, %d 个无效条目", valid_entries, invalid_entries))
    
    -- 组合最终内容
    local result = before_mark .. start_mark .. new_content .. end_mark .. after_mark
    
    -- 移除多余的空行
    result = result:gsub("\n\n+", "\n\n")
    
    -- 保存到 hosts 文件
    if fs.writefile("/etc/hosts", result) then
        -- 自动创建备份
        local backup_path = yaml_config.backup_path or "/etc/hosts.bak"
        local timestamp = os.date("%Y%m%d_%H%M%S")
        local auto_backup = backup_path:gsub("%.bak$", "_auto_" .. timestamp .. ".bak")
        if fs.writefile(auto_backup, current_hosts) then
            write_log("info", string.format("自动创建备份文件: %s", auto_backup))
        else
            write_log("warning", "自动备份失败")
        end
        
        -- 检查文件大小
        local size = fs.stat("/etc/hosts", "size") or 0
        local size_mb = size / 1024 / 1024
        if size_mb > 1 then  -- 如果大于1MB
            write_log("warning", string.format("hosts文件较大 (%.2fMB)，可能影响系统性能", size_mb))
        end
        
        write_log("info", string.format("成功更新 hosts 文件，大小: %d 字节", #result))
        -- 重启 dnsmasq
        sys.exec("/etc/init.d/dnsmasq restart")
        write_log("info", "重启 dnsmasq 服务完成")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 0, msg = "更新成功"})
    else
        write_log("error", "写入 hosts 文件失败")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "写入文件失败"})
    end
end

function backup_hosts()
    local fs = require "nixio.fs"
    local sys = require "luci.sys"
    local yaml_config = load_yaml()
    
    -- 获取备份路径
    local backup_path = yaml_config.backup_path or "/etc/hosts.bak"
    -- 自动添加时间戳到备份文件名
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local backup_file = backup_path:gsub("%.bak$", "_" .. timestamp .. ".bak")
    
    -- 清理旧的备份文件，只保留最近5个
    local backup_dir = backup_file:match("(.+)/[^/]+$") or "."
    local old_backups = sys.exec("ls -t " .. backup_dir .. "/*hosts*.bak 2>/dev/null")
    local count = 0
    for file in old_backups:gmatch("[^\n]+") do
        count = count + 1
        if count > 5 then
            fs.remove(file)
            write_log("info", string.format("清理旧的备份文件: %s", file))
        end
    end
    
    write_log("info", string.format("开始备份 hosts 文件到 %s", backup_file))
    
    -- 读取当前 hosts 文件
    local current_hosts = fs.readfile("/etc/hosts")
    if not current_hosts then
        write_log("error", "读取 hosts 文件失败")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "读取 hosts 文件失败"})
        return
    end
    
    -- 如果备份文件存在，先删除
    if fs.access(backup_file) then
        fs.remove(backup_file)
        write_log("info", "删除已存在的备份文件")
    end
    
    -- 创建新的备份文件
    if fs.writefile(backup_file, current_hosts) then
        write_log("info", "hosts 文件备份成功")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 0, msg = "备份成功"})
    else
        write_log("error", "hosts 文件备份失败")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "备份失败"})
    end
end

function fetch_backup_hosts()
    local fs = require "nixio.fs"
    local yaml_config = load_yaml()
    
    -- 获取备份路径
    local backup_path = yaml_config.backup_path or "/etc/hosts.bak"
    
    if not fs.access(backup_path) then
        write_log("error", string.format("备份文件不存在: %s", backup_path))
        luci.http.prepare_content("text/plain")
        luci.http.write("# 备份文件不存在")
        return
    end
    
    local hosts_content = fs.readfile(backup_path) or "# 备份文件为空"
    write_log("info", string.format("读取备份文件，大小: %d 字节", #hosts_content))
    
    luci.http.prepare_content("text/plain")
    luci.http.write(hosts_content)
end

function clear_log()
    local fs = require "nixio.fs"
    local logfile = "/tmp/autoupdatehosts.log"
    
    -- 清空日志文件
    if fs.writefile(logfile, "") then
        write_log("info", "日志已清空")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 0, msg = "日志已清空"})
    else
        write_log("error", "清空日志失败")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "清空日志失败"})
    end
end 