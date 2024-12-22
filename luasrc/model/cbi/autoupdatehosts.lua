local m, s

m = Map("autoupdatehosts", translate("Auto Update Hosts Settings"),
    translate("Configure automatic hosts file updates"))

s = m:section(TypedSection, "config", "")
s.anonymous = true
s.addremove = false

local description = s:option(DummyValue, "_dummy1")
description.rawhtml = true
description.default = [[
    <div style="padding: 10px; background-color: #f0f0f0; margin-bottom: 20px;">
        <%:Configure automatic hosts file updates%>
    </div>
]]

local enable = s:option(Flag, "enabled", translate("Enable"))
enable.rmempty = false

local schedule = s:option(Value, "schedule", translate("Update Schedule"))
schedule.placeholder = "0 2 * * *"
schedule.description = translate("Cron expression format (e.g., \"0 2 * * *\" for 2 AM daily)")

local urls = s:option(TextValue, "urls", translate("Hosts URLs"))
urls.rows = 10
urls.wrap = "off"
urls.description = translate("Enter URLs (one per line) for hosts files")

local backup_path = s:option(Value, "backup_path", translate("Backup Path"))
backup_path.placeholder = "/etc/AutoUpdateHosts/hosts.bak"
backup_path.description = translate("Path to save hosts backup file")

local preview_area = s:option(DummyValue, "_dummy2")
preview_area.template = "autoupdatehosts/preview"

local buttons = s:option(DummyValue, "_dummy3")
buttons.template = "autoupdatehosts/buttons"

return m 