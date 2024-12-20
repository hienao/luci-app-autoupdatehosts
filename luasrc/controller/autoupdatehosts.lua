module("luci.controller.autoupdatehosts", package.seeall)

function index()
    local e = entry({"admin", "services", "autoupdatehosts"}, 
        template("autoupdatehosts/settings"), 
        _("Auto Update Hosts"), 60)
    e.dependent = false
    e.acl_depends = { "luci-app-autoupdatehosts" }
    
    entry({"admin", "services", "autoupdatehosts", "get_hosts"}, call("get_current_hosts"))
    entry({"admin", "services", "autoupdatehosts", "preview"}, call("preview_hosts"))
    entry({"admin", "services", "autoupdatehosts", "save"}, call("save_hosts"))
    entry({"admin", "services", "autoupdatehosts", "get_config"}, call("get_config"))
    entry({"admin", "services", "autoupdatehosts", "save_config"}, call("save_config"))
    entry({"admin", "services", "autoupdatehosts", "get_log"}, call("get_log"))
end

function get_current_hosts()
    local sys = require "luci.sys"
    local util = require "luci.util"
    local fs = require "nixio.fs"
    local uci = require "luci.model.uci".cursor()
    
    -- 定义日志文件路径
    local logfile = "/tmp/autoupdatehosts.log"
    
    -- 确保日志文件存在并有权限
    local function ensure_logfile()
        local file = io.open(logfile, "a")
        if not file then
            os.execute("touch " .. logfile)
            os.execute("chmod 666 " .. logfile)
        else
            file:close()
        end
    end
    
    -- 写入日志
    local function log(msg)
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        local log_msg = string.format("[%s] %s\n", timestamp, msg)
        local file = io.open(logfile, "a")
        if file then
            file:write(log_msg)
            file:close()
        end
    end
    
    -- 确保日志文件存在
    ensure_logfile()
    
    log("=== 开始新的日志记录 ===")
    log("开始读取 hosts 文件")
    
    -- 检查文件是否存在并输出文件信息
    log("检查 hosts 文件权限")
    local file_info = sys.exec("ls -l /etc/hosts")
    log("hosts 文件信息: " .. (file_info or "无法获取文件��息"))
    
    if not fs.access("/etc/hosts") then
        log("错误：hosts 文件不存在")
        luci.http.status(500, "Hosts file not found")
        luci.http.prepare_content("text/plain")
        luci.http.write("Error: Hosts file not found")
        return
    end
    
    -- 尝试直接读取文件内容
    local direct_content = fs.readfile("/etc/hosts")
    log(string.format("直接读取文件大小: %d 字节", #(direct_content or "")))
    
    -- 使用 cat 命令读取
    local content = sys.exec("cat /etc/hosts")
    log(string.format("通过 cat 命令读取文件大小: %d 字节", #(content or "")))
    
    -- 输出文件内容预览
    if content and #content > 0 then
        local preview = util.trim(util.split(content, "\n", 3)[1] or "")
        log(string.format("文件内容预览: %s", preview))
        
        log("成功读取 hosts 文件")
        luci.http.prepare_content("text/plain")
        luci.http.write(content)
    else
        log("错误：无法读取 hosts 文件内容")
        -- 尝试使用其他命令读取
        local alt_content = sys.exec("sudo cat /etc/hosts")
        log(string.format("尝试使用 sudo 读取大小: %d 字节", #(alt_content or "")))
        
        luci.http.status(500, "Failed to read hosts file")
        luci.http.prepare_content("text/plain")
        luci.http.write("Error: Unable to read hosts file")
    end
end

function get_config()
    local uci = require "luci.model.uci".cursor()
    local config = {
        enabled = uci:get_first("autoupdatehosts", "config", "enabled") or "0",
        urls = uci:get_first("autoupdatehosts", "config", "urls") or "",
        schedule = uci:get_first("autoupdatehosts", "config", "schedule") or ""
    }
    luci.http.prepare_content("application/json")
    luci.http.write_json(config)
end

function fetch_url_content(url)
    local http = require "luci.sys.http"
    local content = http.request_to_buffer(url)
    return content or ""
end

function preview_hosts()
    local fs = require "nixio.fs"
    local uci = require "luci.model.uci".cursor()
    
    local current_hosts = fs.readfile("/etc/hosts") or ""
    local urls = uci:get_first("autoupdatehosts", "config", "urls") or ""
    
    local start_mark = "##订阅hosts内容开始（程序自动更新请勿手动修改中间内容）##"
    local end_mark = "##订阅hosts内容结束（程序自动更新请勿手动修改中间内容）##"
    
    -- 移除旧的订阅内容
    local before_mark = current_hosts:match("(.-)%" .. start_mark)
    local after_mark = current_hosts:match(end_mark .. "(.*)")
    before_mark = before_mark or ""
    after_mark = after_mark or ""
    
    -- 获取新的订阅内容
    local new_content = "\n"
    for url in urls:gmatch("[^\r\n]+") do
        new_content = new_content .. fetch_url_content(url) .. "\n"
    end
    
    local result = before_mark .. start_mark .. new_content .. end_mark .. after_mark
    
    luci.http.prepare_content("text/plain")
    luci.http.write(result)
end

function save_config()
    local uci = require "luci.model.uci".cursor()
    local data = luci.http.formvalue()
    
    uci:foreach("autoupdatehosts", "config", function(s)
        uci:delete("autoupdatehosts", s[".name"])
    end)
    
    local config = uci:section("autoupdatehosts", "config", nil, {
        enabled = data.enabled,
        urls = data.urls,
        schedule = data.schedule
    })
    
    uci:commit("autoupdatehosts")
    
    -- 更新定时任务
    if data.enabled == "1" then
        local sys = require "luci.sys"
        sys.exec("sed -i '/luci-autoupdatehosts/d' /etc/crontabs/root")
        sys.exec(string.format("echo '%s /usr/bin/autoupdatehosts.sh' >> /etc/crontabs/root", data.schedule))
        sys.exec("/etc/init.d/cron restart")
    else
        local sys = require "luci.sys"
        sys.exec("sed -i '/luci-autoupdatehosts/d' /etc/crontabs/root")
        sys.exec("/etc/init.d/cron restart")
    end
    
    luci.http.prepare_content("application/json")
    luci.http.write_json({code = 0, msg = "保存成功"})
end

function save_hosts()
    local fs = require "nixio.fs"
    local content = luci.http.formvalue("content")
    
    if content then
        fs.writefile("/etc/hosts", content)
        luci.sys.exec("/etc/init.d/dnsmasq restart")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 0, msg = "保存成功"})
    else
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "内容不能为空"})
    end
end

function get_log()
    local fs = require "nixio.fs"
    local logfile = "/tmp/autoupdatehosts.log"
    
    -- 确保日志文件存在
    if not fs.access(logfile) then
        luci.http.prepare_content("application/json")
        luci.http.write_json({log = "暂无日志记录"})
        return
    end
    
    -- 读取日志文件
    local log_content = fs.readfile(logfile) or ""
    
    -- 如果日志内容太长，只返回最后100行
    local lines = {}
    for line in log_content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    -- 保留最后100行
    local start_index = #lines > 100 and #lines - 100 + 1 or 1
    local result = table.concat(lines, "\n", start_index)
    
    luci.http.prepare_content("application/json")
    luci.http.write_json({log = result})
end 