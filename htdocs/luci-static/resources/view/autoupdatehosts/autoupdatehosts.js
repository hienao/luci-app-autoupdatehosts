'use strict';
'require view';
'require ui';

function viewCurrentHosts() {
    var preview = document.getElementById('preview');
    preview.style.display = 'block';
    preview.value = '正在获取...';
    
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/cgi-bin/luci/admin/services/autoupdatehosts/fetch_hosts', true);
    
    xhr.onload = function() {
        if (xhr.status >= 200 && xhr.status < 300) {
            preview.value = xhr.responseText;
        } else {
            preview.value = '获取 hosts 文件失败: ' + xhr.status;
        }
    };
    
    xhr.onerror = function() {
        preview.value = '获取 hosts 文件失败：网络错误';
    };
    
    xhr.send();
}

function viewBackupHosts() {
    var preview = document.getElementById('preview');
    preview.style.display = 'block';
    preview.value = '正在获取备份文件...';
    
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/cgi-bin/luci/admin/services/autoupdatehosts/fetch_backup_hosts', true);
    
    xhr.onload = function() {
        if (xhr.status >= 200 && xhr.status < 300) {
            preview.value = xhr.responseText;
        } else {
            preview.value = '获取备份文件失败: 网络错误';
        }
    };
    
    xhr.onerror = function() {
        preview.value = '获取备份文件失败：网络错误';
    };
    
    xhr.send();
}

function previewHosts() {
    var preview = document.getElementById('preview');
    preview.style.display = 'block';
    preview.value = '正在获取预览...';
    
    var urls = document.getElementsByName('cbid.autoupdatehosts.config.urls')[0].value;
    
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/cgi-bin/luci/admin/services/autoupdatehosts/preview', true);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    
    xhr.onload = function() {
        if (xhr.status >= 200 && xhr.status < 300) {
            preview.value = xhr.responseText;
        } else {
            preview.value = '预览失败: ' + xhr.status;
        }
    };
    
    xhr.onerror = function() {
        preview.value = '预览失败：网络错误';
    };
    
    xhr.send('urls=' + encodeURIComponent(urls));
}

function backupHosts() {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/cgi-bin/luci/admin/services/autoupdatehosts/backup_hosts', true);
    
    xhr.onload = function() {
        if (xhr.status >= 200 && xhr.status < 300) {
            var result = JSON.parse(xhr.responseText);
            if (result.code === 0) {
                alert('备份成功');
            } else {
                alert(result.msg);
            }
        } else {
            alert('备份失败: ' + xhr.status);
        }
    };
    
    xhr.onerror = function() {
        alert('备份失败：网络错误');
    };
    
    xhr.send();
} 