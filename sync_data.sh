#!/bin/bash
# 确保文件使用 LF 而非 CRLF 行尾
# 如果在 Windows 上编辑过此文件，请确保转换为 Unix 格式

# 添加调试信息
echo "Starting sync_data.sh script at $(date)"
echo "Current directory: $(pwd)"
echo "Script location: $0"
echo "Home directory: $HOME"

# 检查环境变量
if [[ -z "$WEBDAV_URL" ]] || [[ -z "$WEBDAV_USERNAME" ]] || [[ -z "$WEBDAV_PASSWORD" ]]; then
    echo "Starting without backup functionality - missing WEBDAV_URL, WEBDAV_USERNAME, or WEBDAV_PASSWORD"
    exit 0
fi

# 设置备份路径
WEBDAV_BACKUP_PATH=${WEBDAV_BACKUP_PATH:-""}
FULL_WEBDAV_URL="${WEBDAV_URL}"
if [ -n "$WEBDAV_BACKUP_PATH" ]; then
    FULL_WEBDAV_URL="${WEBDAV_URL}/${WEBDAV_BACKUP_PATH}"
fi

# 测试 WebDAV 连接
echo "Testing WebDAV connection to $FULL_WEBDAV_URL..."
curl -v -u "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" "$FULL_WEBDAV_URL" 2>&1 | grep "HTTP/"

# 激活虚拟环境
source $HOME/venv/bin/activate

# 下载最新备份并恢复
restore_backup() {
    echo "开始从 WebDAV 下载最新备份..."
    python3 -c "
import sys
import os
import tarfile
import requests
import shutil
from webdav3.client import Client
try:
    options = {
        'webdav_hostname': '$FULL_WEBDAV_URL',
        'webdav_login': '$WEBDAV_USERNAME',
        'webdav_password': '$WEBDAV_PASSWORD',
        'verbose': True
    }
    print('Connecting to WebDAV server: ' + '$FULL_WEBDAV_URL')
    client = Client(options)
    
    # 测试连接
    try:
        print('Testing connection...')
        client.check()
        print('Connection successful')
    except Exception as e:
        print('Connection test failed: ' + str(e))
        sys.exit(1)
    
    # 获取文件列表
    try:
        print('Listing files...')
        files = client.list()
        print('Files found: ' + str(files))
        backups = [file for file in files if file.endswith('.tar.gz') and file.startswith('alist_backup_')]
    except Exception as e:
        print('Failed to list files: ' + str(e))
        sys.exit(1)
        
    if not backups:
        print('没有找到备份文件')
        sys.exit(0)
    
    latest_backup = sorted(backups)[-1]
    print(f'最新备份文件：{latest_backup}')
    
    # 使用 requests 下载文件
    try:
        with requests.get(f'$FULL_WEBDAV_URL/{latest_backup}', auth=('$WEBDAV_USERNAME', '$WEBDAV_PASSWORD'), stream=True) as r:
            r.raise_for_status()
            with open(f'/tmp/{latest_backup}', 'wb') as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)
            print(f'成功下载备份文件到 /tmp/{latest_backup}')
    except Exception as e:
        print('下载备份失败: ' + str(e))
        sys.exit(1)
    
    # 解压文件
    if os.path.exists(f'/tmp/{latest_backup}'):
        try:
            # 如果目录已存在，先删除它
            if os.path.exists('$HOME/data'):
                shutil.rmtree('$HOME/data')
            os.makedirs('$HOME/data', exist_ok=True)
            
            # 解压备份文件
            with tarfile.open(f'/tmp/{latest_backup}', 'r:gz') as tar:
                tar.extractall('$HOME/data')
            
            print(f'成功从 {latest_backup} 恢复备份')
        except Exception as e:
            print('解压备份失败: ' + str(e))
            sys.exit(1)
    else:
        print('下载的备份文件不存在')
except Exception as e:
    print('发生错误: ' + str(e))
    sys.exit(1)
"
}

# 首次启动时下载最新备份
echo "Downloading latest backup from WebDAV..."
restore_backup

# 等待30秒后启动程序
sleep 30

# 启动程序
./apksapwk server &

# 同步函数
sync_data() {
    while true; do
        echo "Starting sync process at $(date)"

        if [ ! -d $HOME/data ]; then
            mkdir -p $HOME/data
            echo "Data directory created."
        fi

        timestamp=$(date +%Y%m%d_%H%M%S)
        backup_file="alist_backup_${timestamp}.tar.gz"

        # 压缩数据目录
        tar -czf "/tmp/${backup_file}" -C $HOME/data .

        # 上传新备份到WebDAV
        curl -u "$WEBDAV_USERNAME:$WEBDAV_PASSWORD" -T "/tmp/${backup_file}" "$FULL_WEBDAV_URL/${backup_file}"
        if [ $? -eq 0 ]; then
            echo "Successfully uploaded ${backup_file} to WebDAV"
        else
            echo "Failed to upload ${backup_file} to WebDAV"
        fi

        # 清理旧备份文件
        python3 -c "
import sys
from webdav3.client import Client
options = {
    'webdav_hostname': '$FULL_WEBDAV_URL',
    'webdav_login': '$WEBDAV_USERNAME',
    'webdav_password': '$WEBDAV_PASSWORD'
}
client = Client(options)
backups = [file for file in client.list() if file.endswith('.tar.gz') and file.startswith('alist_backup_')]
backups.sort()
if len(backups) > 5:
    to_delete = len(backups) - 5
    for file in backups[:to_delete]:
        client.clean(file)
        print(f'Successfully deleted {file}.')
else:
    print('Only {} backups found, no need to clean.'.format(len(backups)))
" 2>&1

        rm -f "/tmp/${backup_file}"
        
        SYNC_INTERVAL=${SYNC_INTERVAL:-600}
        echo "Next sync in ${SYNC_INTERVAL} seconds..."
        sleep $SYNC_INTERVAL
    done
}

# 启动同步进程
sync_data &
