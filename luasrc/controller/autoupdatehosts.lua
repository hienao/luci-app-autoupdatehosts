module("luci.controller.autoupdatehosts", package.seeall)

-- 添加日志函数
local function write_log(level, msg)
    local fs = require "nixio.fs"
    local logfile = "/tmp/autoupdatehosts.log"
    
    -- 确保日志文件存在
    if not fs.access(logfile) then
        fs.writefile(logfile, "")
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

function index()
    if not nixio.fs.access("/etc/config/autoupdatehosts") then
        return
    end

    local e = entry({"admin", "services", "autoupdatehosts"}, 
        alias("admin", "services", "autoupdatehosts", "settings"),
        _("Auto Update Hosts"), 60)
    e.dependent = false
    e.acl_depends = { "luci-app-autoupdatehosts" }

    entry({"admin", "services", "autoupdatehosts", "settings"}, template("autoupdatehosts/settings")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "get_current_hosts"}, call("get_current_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "preview"}, call("preview_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "get_config"}, call("get_config")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "save_config"}, call("save_config")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "get_log"}, call("get_log")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "fetch_hosts"}, call("fetch_hosts"), nil).leaf = true
    entry({"admin", "services", "autoupdatehosts", "save_hosts_etc"}, call("save_hosts_etc")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "backup_hosts"}, call("backup_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "fetch_backup_hosts"}, call("fetch_backup_hosts")).leaf = true
end

function get_current_hosts()
    local fs = require "nixio.fs"
    local hosts_file = "/etc/hosts"
    local hosts_content = fs.readfile(hosts_file) or "# No hosts content"
    
    -- 设置响应类型为纯文本
    luci.http.prepare_content("text/plain")
    luci.http.write(hosts_content)
end

function get_config()
    local uci = require "luci.model.uci".cursor()
    local config = {
        enabled = uci:get_first("autoupdatehosts", "config", "enabled") or "0",
        urls = uci:get_first("autoupdatehosts", "config", "urls") or "",
        schedule = uci:get_first("autoupdatehosts", "config", "schedule") or "",
        backup_path = uci:get_first("autoupdatehosts", "config", "backup_path") or "/etc/hosts.bak"
    }
    luci.http.prepare_content("application/json")
    luci.http.write_json(config)
end

function fetch_url_content(url)
    local sys = require "luci.sys"
    -- 使用 wget 命令获取内容
    local content = sys.exec(string.format("wget -qO- '%s'", url:gsub("'", "'\\''")))
    
    -- 如果 wget 失败，尝试使用 curl
    if not content or #content == 0 then
        write_log("error", string.format("wget 获取失败，尝试使用 curl: %s", url))
        content = sys.exec(string.format("curl -sfL '%s'", url:gsub("'", "'\\''")))
    end
    
    if content and #content > 0 then
        write_log("info", string.format("成功获取URL内容: %s (大小: %d字节)", url, #content))
    else
        write_log("error", string.format("获取URL内容失败: %s", url))
    end
    
    return content or ""
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
    
    -- 定义标记，确保每个标记都有正确的换行
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
            -- 确保每个URL的内容前后���有换行
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
    
    -- 确保脚本有执行权限
    sys.exec("chmod +x /usr/bin/autoupdatehosts.sh")
    
    -- 更新定时任务
    if data.enabled == "1" then
        sys.exec("sed -i '/luci-autoupdatehosts/d' /etc/crontabs/root")
        sys.exec(string.format("echo '%s /usr/bin/autoupdatehosts.sh' >> /etc/crontabs/root", data.schedule))
        sys.exec("/etc/init.d/cron restart")
    else
        sys.exec("sed -i '/luci-autoupdatehosts/d' /etc/crontabs/root")
        sys.exec("/etc/init.d/cron restart")
    end
    
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
    
    -- 设置响应类型为纯文本
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
    
    -- 定义标记
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
    
    -- 从配置获取 URLs
    local urls = uci:get_first("autoupdatehosts", "config", "urls") or ""
    if urls == "" then
        write_log("error", "未配置 URLs")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "未配置 URLs"})
        return
    end
    write_log("info", string.format("获取到 URLs 配置: %s", urls))
    
    -- 获取新的订阅内容
    local new_content = ""
    for url in urls:gmatch("[^\r\n]+") do
        local content = fetch_url_content(url)
        if content and #content > 0 then
            -- 确保每个URL的内容前后都有换行
            new_content = new_content .. content:gsub("^%s*(.-)%s*$", "%1") .. "\n"
        end
    end
    
    -- 组合最终内容
    local result = before_mark .. start_mark .. new_content .. end_mark .. after_mark
    
    -- 移除多余的空行
    result = result:gsub("\n\n+", "\n\n")
    
    -- 保存到 hosts 文件
    if fs.writefile("/etc/hosts", result) then
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
    local uci = require "luci.model.uci".cursor()
    
    -- 获取备份路径
    local backup_path = uci:get_first("autoupdatehosts", "config", "backup_path") or "/etc/hosts.bak"
    write_log("info", string.format("开始备份 hosts 文件到 %s", backup_path))
    
    -- 读取当前 hosts 文件
    local current_hosts = fs.readfile("/etc/hosts")
    if not current_hosts then
        write_log("error", "读取 hosts 文件失败")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "读取 hosts 文件失败"})
        return
    end
    
    -- 如果备份文件存在，先删除
    if fs.access(backup_path) then
        fs.remove(backup_path)
        write_log("info", "删除已存在的备份文件")
    end
    
    -- 创建新的备份文件
    if fs.writefile(backup_path, current_hosts) then
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
    local uci = require "luci.model.uci".cursor()
    
    -- 获取备份路径
    local backup_path = uci:get_first("autoupdatehosts", "config", "backup_path") or "/etc/hosts.bak"
    
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