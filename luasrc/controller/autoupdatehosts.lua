module("luci.controller.autoupdatehosts", package.seeall)

local SETTINGS_FILE = "/etc/auto_undate_host/settings.yaml"
local LOG_FILE = "/tmp/auto_undate_host/log.txt"
local HOSTS_FILE = "/etc/hosts"

-- 写入日志
local function write_log(msg)
    local fs = require "nixio.fs"
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local log_msg = string.format("[%s] %s\n", timestamp, msg)
    
    -- 确保日志目录存在
    os.execute("mkdir -p /tmp/auto_undate_host")
    
    -- 追加日志
    local file = io.open(LOG_FILE, "a")
    if file then
        file:write(log_msg)
        file:close()
    end
end

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
    write_log(string.format("获取当前hosts文件内容，大小：%d 字节", #hosts_content))
    
    luci.http.prepare_content("text/plain")
    luci.http.write(hosts_content)
end

-- 保存hosts文件内容
function save_hosts_etc()
    local fs = require "nixio.fs"
    local content = luci.http.formvalue("content")
    
    if content then
        write_log(string.format("准备保存hosts文件，内容大小：%d 字节", #content))
        -- 先备份当前文件
        backup_hosts()
        
        -- 保存新内容
        if fs.writefile(HOSTS_FILE, content) then
            -- 重启 dnsmasq
            os.execute("/etc/init.d/dnsmasq restart")
            write_log("hosts文件保存成功，已重启dnsmasq服务")
            
            luci.http.prepare_content("application/json")
            luci.http.write_json({code = 0, msg = "Hosts saved"})
        else
            write_log("hosts文件保存失败")
            luci.http.prepare_content("application/json")
            luci.http.write_json({code = 1, msg = "Failed to save hosts"})
        end
    else
        write_log("保存hosts文件失败：未提供内容")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "No content provided"})
    end
end 

function fetch_backup_hosts()
    local fs = require "nixio.fs"
    local yaml_config = load_yaml()
    
    -- 获取备份路径
    local backup_path = yaml_config.bakPath or "/etc/auto_undate_host/hosts.bak"
    write_log(string.format("获取备份文件内容，路径：%s", backup_path))
    
    if not fs.access(backup_path) then
        write_log("备份文件不存在，返回空内容")
        luci.http.prepare_content("text/plain")
        luci.http.write("")
        return
    end
    
    local hosts_content = fs.readfile(backup_path) or ""
    write_log(string.format("读取备份文件成功，大小：%d 字节", #hosts_content))
    
    luci.http.prepare_content("text/plain")
    luci.http.write(hosts_content)
end

function backup_hosts()
    local fs = require "nixio.fs"
    local yaml_config = load_yaml()
    
    -- 获取备份路径
    local backup_path = yaml_config.bakPath or "/etc/auto_undate_host/hosts.bak"
    write_log(string.format("开始备份hosts文件到：%s", backup_path))
    
    -- 读取当前 hosts 文件
    local current_hosts = fs.readfile(HOSTS_FILE)
    if not current_hosts then
        write_log("备份失败：无法读取当前hosts文件")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "Failed to read hosts file"})
        return
    end
    
    -- 确保备份目录存在
    local backup_dir = backup_path:match("(.+)/[^/]+$")
    if backup_dir and not fs.access(backup_dir) then
        os.execute("mkdir -p " .. backup_dir)
        write_log(string.format("创建备份目录：%s", backup_dir))
    end
    
    -- 创建备份
    if fs.writefile(backup_path, current_hosts) then
        write_log(string.format("备份成��，大小：%d 字节", #current_hosts))
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 0, msg = "Backup created"})
    else
        write_log("备份失败：无法写入备份文件")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "Failed to create backup"})
    end
end 

-- 获取日志内容
function get_log()
    local fs = require "nixio.fs"
    
    -- 确保日志目录和文件存在
    os.execute("mkdir -p /tmp/auto_undate_host")
    if not fs.access(LOG_FILE) then
        fs.writefile(LOG_FILE, "")
    end
    
    -- 读取日志内容
    local log_content = fs.readfile(LOG_FILE) or ""
    
    -- 返回日志内容
    luci.http.prepare_content("application/json")
    luci.http.write_json({
        code = 0,
        log = log_content
    })
end

-- 清空日志
function clear_log()
    local fs = require "nixio.fs"
    
    -- 确保日志目录存在
    os.execute("mkdir -p /tmp/auto_undate_host")
    
    -- 清空日志文件
    if fs.writefile(LOG_FILE, "") then
        write_log("日志已清空")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 0, msg = "Log cleared"})
    else
        write_log("清空日志失败")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "Failed to clear log"})
    end
end 