module("luci.controller.autoupdatehosts", package.seeall)

local SETTINGS_FILE = "/etc/auto_undate_host/settings.yaml"
local LOG_FILE = "/tmp/auto_undate_host/log.txt"
local HOSTS_FILE = "/etc/hosts"

function index()
    if not nixio.fs.access("/etc/config/autoupdatehosts") then
        return
    end

    -- 创建主菜单项
    entry({"admin", "services", "autoupdatehosts"}, firstchild(), _("Auto Update Hosts"), 60)
    
    -- 创建子菜单项
    entry({"admin", "services", "autoupdatehosts", "settings"}, template("autoupdatehosts/settings"), _("Settings"), 10)
    entry({"admin", "services", "autoupdatehosts", "log"}, template("autoupdatehosts/log"), _("Log"), 20)
    
    -- API 接口
    entry({"admin", "services", "autoupdatehosts", "get_settings"}, call("get_settings"))
    entry({"admin", "services", "autoupdatehosts", "save_settings"}, call("save_settings"))
    entry({"admin", "services", "autoupdatehosts", "get_hosts"}, call("get_current_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "save_hosts"}, call("save_hosts_etc")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "get_backup"}, call("fetch_backup_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "create_backup"}, call("backup_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "get_log"}, call("get_log"))
    entry({"admin", "services", "autoupdatehosts", "clear_log"}, call("clear_log"))
end

-- 其他现有函数保持不变...

-- 新增函数用于处理设置
function get_settings()
    local fs = require "nixio.fs"
    local settings = {}
    
    -- 确保目录存在
    os.execute("mkdir -p /etc/auto_undate_host")
    
    if fs.access(SETTINGS_FILE) then
        local content = fs.readfile(SETTINGS_FILE)
        if content then
            -- 简单的 YAML 解析
            for line in content:gmatch("[^\r\n]+") do
                local key, value = line:match("^([^:]+):%s*(.+)$")
                if key and value then
                    settings[key] = value
                end
            end
        end
    end
    
    -- 设置默认值
    settings.enable = settings.enable or "false"
    settings.cron = settings.cron or ""
    settings.bakPath = settings.bakPath or "/etc/auto_undate_host/hosts.bak"
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(settings)
end

function save_settings()
    local fs = require "nixio.fs"
    local settings = luci.http.formvalue()
    local content = ""
    
    -- 确保目录存在
    os.execute("mkdir -p /etc/auto_undate_host")
    
    -- 构建 YAML 内容
    content = string.format("enable: %s\n", settings.enable or "false")
    content = content .. string.format("cron: %s\n", settings.cron or "")
    content = content .. string.format("bakPath: %s\n", settings.bakPath or "/etc/auto_undate_host/hosts.bak")
    
    -- 保存设置
    if fs.writefile(SETTINGS_FILE, content) then
        -- 如果启用了定时任务，更新 crontab
        if settings.enable == "true" and settings.cron and settings.cron ~= "" then
            -- 移除旧的定时任务
            os.execute("sed -i '/auto_undate_host/d' /etc/crontabs/root")
            -- 添加新的定时任务
            os.execute(string.format("echo '%s /usr/bin/autoupdatehosts.sh' >> /etc/crontabs/root", settings.cron))
            -- 重启 cron 服务
            os.execute("/etc/init.d/cron restart")
        else
            -- 如果禁用了定时任务，移除相关任务
            os.execute("sed -i '/auto_undate_host/d' /etc/crontabs/root")
            os.execute("/etc/init.d/cron restart")
        end
        
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 0, msg = "Settings saved"})
    else
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "Failed to save settings"})
    end
end 

-- 获取当前hosts文件内容
function get_current_hosts()
    local fs = require "nixio.fs"
    local hosts_content = fs.readfile(HOSTS_FILE) or ""
    
    luci.http.prepare_content("text/plain")
    luci.http.write(hosts_content)
end

-- 保存hosts文件内容
function save_hosts_etc()
    local fs = require "nixio.fs"
    local content = luci.http.formvalue("content")
    
    if content then
        -- 先备份当前文件
        backup_hosts()
        
        -- 保存新内容
        if fs.writefile(HOSTS_FILE, content) then
            -- 重启 dnsmasq
            os.execute("/etc/init.d/dnsmasq restart")
            
            luci.http.prepare_content("application/json")
            luci.http.write_json({code = 0, msg = "Hosts saved"})
        else
            luci.http.prepare_content("application/json")
            luci.http.write_json({code = 1, msg = "Failed to save hosts"})
        end
    else
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "No content provided"})
    end
end 