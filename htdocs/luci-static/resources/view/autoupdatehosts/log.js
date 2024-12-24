'use strict';
'require view';
'require ui';

var refreshTimer = null;
var isRefreshing = false;

function toggleRefresh() {
    isRefreshing = !isRefreshing;
    var btn = document.getElementById('btn_refresh');
    
    if (isRefreshing) {
        btn.value = _('Stop Refresh');
        refreshTimer = setInterval(fetchLog, 1000);
    } else {
        btn.value = _('Start Refresh');
        if (refreshTimer) {
            clearInterval(refreshTimer);
            refreshTimer = null;
        }
    }
}

function fetchLog() {
    var xhr = new XHR();
    xhr.get('<%=luci.dispatcher.build_url("admin", "services", "autoupdatehosts", "get_log")%>', null,
        function(x, data) {
            if (data && data.log) {
                var textarea = document.getElementById('log_content');
                textarea.value = data.log;
                textarea.scrollTop = textarea.scrollHeight;
            }
        }
    );
}

function clearLog() {
    var xhr = new XHR();
    xhr.post('<%=luci.dispatcher.build_url("admin", "services", "autoupdatehosts", "clear_log")%>', null,
        function(x, data) {
            if (data && data.code === 0) {
                document.getElementById('log_content').value = '';
                ui.addNotification(null, E('p', _('Log cleared successfully')));
            } else {
                ui.addNotification(null, E('p', _('Failed to clear log')));
            }
        }
    );
}

window.addEventListener('load', function() {
    fetchLog();
}); 