'use strict';
'require view';
'require ui';
'require form';
'require xhr';

var refreshTimer = null;

function loadSettings() {
    return new Promise((resolve, reject) => {
        xhr.get('<%=luci.dispatcher.build_url("admin", "services", "autoupdatehosts", "get_hosts")%>', null)
            .then(function(res) {
                var data = res.json();
                if (data) {
                    resolve(data);
                } else {
                    reject('Failed to load settings');
                }
            });
    });
}

function saveSettings() {
    var settings = {
        enable: document.getElementById('enable').checked,
        cron: getCronExpression(),
        bakPath: document.getElementById('bakPath').value || '/etc/auto_undate_host/hosts.bak'
    };

    var xhr = new XHR();
    xhr.post('<%=luci.dispatcher.build_url("admin", "services", "autoupdatehosts", "save_settings")%>', 
        { settings: JSON.stringify(settings) },
        function(x, data) {
            if (data && data.code === 0) {
                ui.addNotification(null, E('p', _('Settings saved successfully')));
            } else {
                ui.addNotification(null, E('p', _('Failed to save settings')));
            }
        }
    );
}

function getCronExpression() {
    var type = document.getElementById('schedule_type').value;
    if (type === 'none') return '';

    var minute = document.getElementById('schedule_minute').value || '0';
    var hour = document.getElementById('schedule_hour').value || '0';

    switch(type) {
        case 'daily':
            return `${minute} ${hour} * * *`;
        case 'weekly':
            var week = document.getElementById('schedule_week').value;
            return `${minute} ${hour} * * ${week}`;
        case 'monthly':
            var day = document.getElementById('schedule_day').value;
            return `${minute} ${hour} ${day} * *`;
        default:
            return '';
    }
}

function updateScheduleInputs() {
    var type = document.getElementById('schedule_type').value;
    document.getElementById('day_container').style.display = type === 'monthly' ? '' : 'none';
    document.getElementById('week_container').style.display = type === 'weekly' ? '' : 'none';
}

function viewCurrentHosts() {
    xhr.get('<%=luci.dispatcher.build_url("admin", "services", "autoupdatehosts", "get_hosts")%>', null)
        .then(function(res) {
            var data = res.responseText;
            if (data) {
                document.getElementById('hosts_content').value = data;
            }
        });
}

function viewBackupHosts() {
    var xhr = new XHR();
    xhr.get('<%=luci.dispatcher.build_url("admin", "services", "autoupdatehosts", "get_backup")%>', null,
        function(x, data) {
            if (data) {
                document.getElementById('hosts_content').value = data;
            }
        }
    );
}

function previewHosts() {
    var xhr = new XHR();
    xhr.post('<%=luci.dispatcher.build_url("admin", "services", "autoupdatehosts", "preview")%>', null,
        function(x, data) {
            if (data) {
                document.getElementById('hosts_content').value = data;
            }
        }
    );
}

function backupHosts() {
    var xhr = new XHR();
    xhr.post('<%=luci.dispatcher.build_url("admin", "services", "autoupdatehosts", "create_backup")%>', null,
        function(x, data) {
            if (data && data.code === 0) {
                ui.addNotification(null, E('p', _('Backup created successfully')));
            } else {
                ui.addNotification(null, E('p', _('Failed to create backup')));
            }
        }
    );
}

function saveHosts() {
    var content = document.getElementById('hosts_content').value;
    var xhr = new XHR();
    xhr.post('<%=luci.dispatcher.build_url("admin", "services", "autoupdatehosts", "save_hosts")%>', 
        { content: content },
        function(x, data) {
            if (data && data.code === 0) {
                ui.addNotification(null, E('p', _('Hosts saved successfully')));
            } else {
                ui.addNotification(null, E('p', _('Failed to save hosts')));
            }
        }
    );
}

window.addEventListener('load', function() {
    loadSettings().then(settings => {
        document.getElementById('enable').checked = settings.enable === 'true';
        document.getElementById('bakPath').value = settings.bakPath;
        if (settings.cron) {
            setCronUI(settings.cron);
        }
        viewCurrentHosts();
    });
}); 