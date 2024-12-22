local m, s

m = Map("autoupdatehosts", translate("Auto Update Hosts Settings"),
    translate("Configure automatic hosts file updates"))

s = m:section(TypedSection, "config", "")
s.anonymous = true
s.addremove = false

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
backup_path.placeholder = "/etc/hosts.bak"
backup_path.description = translate("Path to save hosts backup file")

return m 