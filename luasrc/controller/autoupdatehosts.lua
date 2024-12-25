module("luci.controller.autoupdatehosts", package.seeall)

local SETTINGS_FILE = "/etc/auto_update_host/settings.yaml"
local LOG_FILE = "/tmp/auto_update_host/log.txt"
local HOSTS_FILE = "/etc/hosts"

-- 写入日志
local function write_log(msg)
    local fs = require "nixio.fs"
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local log_msg = string.format("[%s] %s\n", timestamp, msg)
    
    -- 确保日志目录存在
    os.execute("mkdir -p /tmp/auto_update_host")
    
    -- 追加日志
    local file = io.open(LOG_FILE, "a")
    if file then
        file:write(log_msg)
        file:close()
    end
end

-- 加载YAML配置
local function load_settings()
    local fs = require "nixio.fs"
    local settings = {}
    
    -- 确保目录存在
    os.execute("mkdir -p /etc/auto_update_host")
    
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
    settings.bakPath = settings.bakPath or "/etc/auto_update_host/hosts.bak"
    
    return settings
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
    entry({"admin", "services", "autoupdatehosts", "preview"}, call("preview_hosts")).leaf = true
    entry({"admin", "services", "autoupdatehosts", "get_log"}, call("get_log"))
    entry({"admin", "services", "autoupdatehosts", "clear_log"}, call("clear_log"))
end

-- 其他现有函数保持不变...

-- 新增函数用于处理设置
function get_settings()
    local settings = load_settings()
    luci.http.prepare_content("application/json")
    luci.http.write_json(settings)
end

function save_settings()
    local fs = require "nixio.fs"
    local settings = luci.http.formvalue()
    local content = ""
    
    write_log("开始保存设置...")
    
    -- 确保目录存在
    os.execute("mkdir -p /etc/auto_update_host")
    
    -- 验证和处理设置值
    settings.enable = settings.enable or "false"
    settings.cron = (settings.cron and settings.cron ~= "") and settings.cron or ""
    settings.bakPath = (settings.bakPath and settings.bakPath ~= "") 
        and settings.bakPath 
        or "/etc/auto_update_host/hosts.bak"
    
    -- 处理 URLs
    local urls = {}
    if settings.urls then
        -- 如果 urls 是 JSON 字符串，解析它
        if settings.urls:sub(1,1) == "[" then
            urls = luci.jsonc.parse(settings.urls) or {}
        else
            -- 如果是单个 URL，直接添加
            urls = {settings.urls}
        end
    end
    
    write_log(string.format("处理设置数据: enable=%s, cron=%s, bakPath=%s, urls数量=%d", 
        settings.enable, settings.cron, settings.bakPath, #urls))
    
    -- 构建 YAML 内容
    content = string.format("enable: %s\n", settings.enable)
    content = content .. string.format("cron: %s\n", settings.cron)
    content = content .. string.format("bakPath: %s\n", settings.bakPath)
    
    -- 添加 URLs
    if #urls > 0 then
        content = content .. "urls:\n"
        for _, url in ipairs(urls) do
            content = content .. string.format("  - %s\n", url)
        end
    else
        content = content .. "urls: []\n"
    end
    
    write_log(string.format("准备写入配置文件: %s", SETTINGS_FILE))
    
    -- 保存设置
    if fs.writefile(SETTINGS_FILE, content) then
        write_log("配置文件保存成功")
        
        -- 处理定时任务
        if settings.enable == "true" and settings.cron and settings.cron ~= "" then
            write_log("��新定时任务...")
            -- 移除旧的定时任务
            os.execute("sed -i '/autoupdatehosts.sh/d' /etc/crontabs/root")
            -- 添加新的定时任务
            local cron_cmd = string.format("echo '%s /usr/bin/autoupdatehosts.sh' >> /etc/crontabs/root", settings.cron)
            if os.execute(cron_cmd) == 0 then
                os.execute("/etc/init.d/cron restart")
                write_log("定时任务更新成功")
            else
                write_log("定时任务更新失败")
            end
        else
            write_log("移除定时任务...")
            os.execute("sed -i '/autoupdatehosts.sh/d' /etc/crontabs/root")
            os.execute("/etc/init.d/cron restart")
        end
        
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 0, msg = "设置保存成功"})
    else
        write_log("配置文件保存失败")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "设置保存失败"})
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

-- 添加hosts文件内容验证函数
local function validate_hosts_content(content)
    if not content or #content == 0 then
        return false, "hosts内容不能为空"
    end
    
    -- 检查基本格式
    local valid_lines = 0
    local invalid_lines = {}
    local line_number = 0
    
    for line in content:gmatch("[^\r\n]+") do
        line_number = line_number + 1
        -- 忽略注释和空行
        if not line:match("^%s*#") and not line:match("^%s*$") then
            -- 检查是否符合hosts文件格式: IP地址(IPv4或IPv6) 域名
            local ip, domain = line:match("^%s*([%x%d:%.]+)%s+([%S]+)%s*$")
            if not ip or not domain then
                table.insert(invalid_lines, line_number)
            else
                local valid_ip = false
                -- 验证IPv4地址格式
                if ip:match("^%d+%.%d+%.%d+%.%d+$") then
                    local parts = {ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)")}
                    valid_ip = true
                    if #parts ~= 4 then
                        valid_ip = false
                    else
                        for _, part in ipairs(parts) do
                            local num = tonumber(part)
                            if not num or num < 0 or num > 255 then
                                valid_ip = false
                                break
                            end
                        end
                    end
                -- 验证IPv6地址格式
                elseif ip:match("^%x*:%x*") then
                    -- 简单验证IPv6格式，接受包含冒号的十六进制格式
                    valid_ip = true
                end
                
                if not valid_ip then
                    table.insert(invalid_lines, line_number)
                else
                    valid_lines = valid_lines + 1
                end
            end
        end
    end
    
    if #invalid_lines > 0 then
        return false, string.format("发现无效的hosts条目(行号: %s)", table.concat(invalid_lines, ", "))
    end
    
    if valid_lines == 0 then
        return false, "未找到有效的hosts条目"
    end
    
    return true, "hosts内容验证通过"
end

-- 修改保存hosts文件的函数
function save_hosts_etc()
    local fs = require "nixio.fs"
    local content = luci.http.formvalue("content")
    
    if content then
        write_log(string.format("准备保存hosts文件，内容大小：%d 字节", #content))
        
        -- 验证hosts内容
        local is_valid, msg = validate_hosts_content(content)
        if not is_valid then
            write_log("hosts文件验证失败: " .. msg)
            luci.http.prepare_content("application/json")
            luci.http.write_json({code = 1, msg = msg})
            return
        end
        
        -- 确保内容有正确的换行
        content = content:gsub("\r\n", "\n"):gsub("\n\n+", "\n\n")
        
        -- 保存新内容
        if fs.writefile(HOSTS_FILE, content) then
            -- 重启 dnsmasq
            os.execute("/etc/init.d/dnsmasq restart")
            write_log("hosts文件保存成功，已重启dnsmasq服务")
            luci.http.prepare_content("application/json")
            luci.http.write_json({code = 0, msg = "Hosts保存成功"})
        else
            write_log("hosts文件保存失败")
            luci.http.prepare_content("application/json")
            luci.http.write_json({code = 1, msg = "保存hosts文件失败"})
        end
    else
        write_log("保存hosts文件失败：未提供内容")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "未提供hosts内容"})
    end
end

function fetch_backup_hosts()
    local fs = require "nixio.fs"
    local settings = load_settings()
    
    -- 获取备份路径
    local backup_path = settings.bakPath or "/etc/auto_update_host/hosts.bak"
    write_log(string.format("获取备份文件内容，路径：%s", backup_path))
    
    if not fs.access(backup_path) then
        write_log("备份文件不存在，返回空内容")
        luci.http.header('Content-Type', 'text/plain; charset=utf-8')
        luci.http.prepare_content("text/plain")
        luci.http.write("")
        return
    end
    
    local hosts_content = fs.readfile(backup_path) or ""
    write_log(string.format("读取备份文件成功，大小：%d 字节", #hosts_content))
    luci.http.header('Content-Type', 'text/plain; charset=utf-8')
    luci.http.prepare_content("text/plain")
    luci.http.write(hosts_content)
end

-- 修改备份hosts文件的函数
function backup_hosts()
    local fs = require "nixio.fs"
    local settings = load_settings()
    
    -- 获取备份路径
    local backup_path = settings.bakPath or "/etc/auto_update_host/hosts.bak"
    write_log(string.format("开始备份hosts文件到：%s", backup_path))
    
    -- 读取当前 hosts 文件
    local current_hosts = fs.readfile(HOSTS_FILE)
    if not current_hosts then
        write_log("备份失败：无法读取当前hosts文件")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "无法读取hosts文件"})
        return
    end
    
    -- 验证hosts内容
    local is_valid, msg = validate_hosts_content(current_hosts)
    if not is_valid then
        write_log("hosts文件验证失败: " .. msg)
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = msg})
        return
    end
    
    -- 确保备份��录存在
    local backup_dir = backup_path:match("(.+)/[^/]+$")
    if backup_dir and not fs.access(backup_dir) then
        os.execute("mkdir -p " .. backup_dir)
        write_log(string.format("创建备份目录：%s", backup_dir))
    end
    
    -- 创建备份
    if fs.writefile(backup_path, current_hosts) then
        write_log(string.format("备份成功，大小：%d 字节", #current_hosts))
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 0, msg = "备份创建成功"})
    else
        write_log("备份失败：无法写入备份文件")
        luci.http.prepare_content("application/json")
        luci.http.write_json({code = 1, msg = "创建备份失败"})
    end
end 

-- 获取日志内容
function get_log()
    local fs = require "nixio.fs"
    
    -- 确保日志目录和文件存在
    os.execute("mkdir -p /tmp/auto_update_host")
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
    os.execute("mkdir -p /tmp/auto_update_host")
    
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

-- hosts预览功能
-- 功能：根据提供的URLs预览合并后的hosts内容
function preview_hosts()
    local fs = require "nixio.fs"
    local urls_json = luci.http.formvalue("urls")
    local urls = {}
    
    write_log("开始预览hosts内容")
    
    if urls_json then
        urls = luci.jsonc.parse(urls_json)
    end
    
    if not urls or #urls == 0 then
        write_log("未提供URLs，返回当前hosts文件内容")
        get_current_hosts()
        return
    end
    
    -- 读取当前 hosts 文件
    local current_hosts = fs.readfile(HOSTS_FILE) or ""
    
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
        write_log("检测到现有标记，将更新订阅内容")
    else
        -- 如果不存在标记，将整个当前内容作为 before_mark
        before_mark = current_hosts
        after_mark = ""
        write_log("未检测到标记，将添加新的订阅内容")
    end
    
    -- 确保 before_mark 和 after_mark 有正确的结尾和开头
    before_mark = (before_mark or ""):gsub("%s*$", "\n")
    after_mark = (after_mark or ""):gsub("^%s*", "\n")
    
    -- 获取新的订阅内容
    local new_content = ""
    local wget = "wget -qO- "
    
    for _, url in ipairs(urls) do
        write_log(string.format("正在获取URL内容：%s", url))
        -- 使用wget获取内容
        local cmd = string.format("%s %s", wget, url)
        local content = io.popen(cmd):read("*a")
        
        if content and #content > 0 then
            -- 确保每个URL的内容前后都有换行
            content = content:gsub("^%s*(.-)%s*$", "%1")
            new_content = new_content .. content .. "\n"
            write_log(string.format("成功获取内容，大小：%d 字节", #content))
        else
            write_log(string.format("获取内容失败：%s", url))
        end
    end
    
    if #new_content > 0 then
        -- 组合最终内容，确保各部分之间有正确的换行
        local result = before_mark .. start_mark .. new_content .. end_mark .. after_mark
        
        -- 移除多余的空行
        result = result:gsub("\n\n+", "\n\n")
        
        write_log(string.format("合并后的hosts内容大小：%d 字节", #result))
        luci.http.prepare_content("text/plain")
        luci.http.write(result)
    else
        write_log("所有URL获取失败，返回当前hosts内容")
        get_current_hosts()
    end
end 