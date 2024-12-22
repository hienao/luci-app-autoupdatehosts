-- 创建配置页面模型
-- m: Map对象，对应整个配置页面
-- s: Section对象，对应配置的分节
local m, s

-- 创建主配置页面
-- 参数1: 配置文件名
-- 参数2: 页面标题
-- 参数3: 页面描述
m = Map("autoupdatehosts", translate("Auto Update Hosts Settings"),
    translate("Configure automatic hosts file updates"))

-- 创建配置分节
-- anonymous: 匿名节，不显示节名
-- addremove: 禁止添加或删除配置节
s = m:section(TypedSection, "config", "")
s.anonymous = true
s.addremove = false

-- 启用开关选项
-- Flag类型，表示开关选项
-- rmempty: 不允许为空
local enable = s:option(Flag, "enabled", translate("Enable"))
enable.rmempty = false

-- 更新计划选项
-- Value类型，表示输入框
-- placeholder: 默认显示的提示文本
local schedule = s:option(Value, "schedule", translate("Update Schedule"))
schedule.placeholder = "0 2 * * *"
schedule.description = translate("Cron expression format (e.g., \"0 2 * * *\" for 2 AM daily)")

-- URLs输入区域
-- TextValue类型，表示多行文本输入框
local urls = s:option(TextValue, "urls", translate("Hosts URLs"))
urls.rows = 10
urls.wrap = "off"
urls.description = translate("Enter URLs (one per line) for hosts files")

-- 备份路径选项
-- Value类型，表示输入框
local backup_path = s:option(Value, "backup_path", translate("Backup Path"))
backup_path.placeholder = "/etc/AutoUpdateHosts/hosts.bak"
backup_path.description = translate("Path to save hosts backup file")

-- 操作按钮区域
-- DummyValue类型，使用自定义模板
local buttons = s:option(DummyValue, "_dummy1")
buttons.template = "autoupdatehosts/buttons"

-- 预览区域
-- TextValue类型，使用自定义模板
-- readonly: 设置为只读
local preview = s:option(TextValue, "_preview")
preview.template = "autoupdatehosts/preview"
preview.title = translate("Preview Content")
preview.rows = 20
preview.wrap = "off"
preview.readonly = true

return m 