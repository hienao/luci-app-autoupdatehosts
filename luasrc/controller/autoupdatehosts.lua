module("luci.controller.autoupdatehosts", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/autoupdatehosts") then
        return
    end

    local e = entry({"admin", "services", "autoupdatehosts"}, 
        alias("admin", "services", "autoupdatehosts", "settings"),
        _("Auto Update Hosts"), 60)
    e.dependent = false
    e.acl_depends = { "luci-app-autoupdatehosts" }

    entry({"admin", "services", "autoupdatehosts", "settings"}, template("autoupdatehosts/settings"), _("Settings"), 10).leaf = true
    entry({"admin", "services", "autoupdatehosts", "get_current_hosts"}, call("get_current_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "preview"}, call("preview_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "save"}, call("save_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "get_config"}, call("get_config")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "save_config"}, call("save_config")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "get_log"}, call("get_log")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "fetch_hosts"}, call("fetch_hosts"), nil).leaf = true
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