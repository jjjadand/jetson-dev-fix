#!/bin/bash
# bt-auto-maintain.sh - 自动发现设备并维持连接
PID_FILE="/tmp/bt-auto-maintain.pid"
LAST_MAC_FILE="/tmp/bt-last-mac"

if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
    echo "已在运行 (PID: $(cat $PID_FILE))"
    exit 1
fi
echo $$ > "$PID_FILE"

cleanup() {
    rm -f "$PID_FILE"
    exit 0
}
trap cleanup SIGINT SIGTERM

# 获取当前连接的 MAC（如果有多个，取第一个）
get_connected_mac() {
    hcitool con 2>/dev/null | grep -oE '([0-9A-F]{2}:){5}[0-9A-F]{2}' | head -1 | tr '[:lower:]' '[:upper:]'
}

TARGET_MAC=""

echo "[$(date '+%H:%M:%S')] 启动自动维持脚本..."
echo "首次需要手动连接，或脚本会自动尝试连接上次设备"

while true; do
    CURRENT_MAC=$(get_connected_mac)
    
    if [ -n "$CURRENT_MAC" ]; then
        # 有连接
        if [ "$CURRENT_MAC" != "$TARGET_MAC" ]; then
            TARGET_MAC="$CURRENT_MAC"
            echo "$TARGET_MAC" > "$LAST_MAC_FILE"
            echo "[$(date '+%H:%M:%S')] 新设备: $TARGET_MAC，开始维持"
        fi
        
        # 关键：周期性 trust（维持权限，防止因 profile 问题断开）
        bluetoothctl trust "$TARGET_MAC" >/dev/null 2>&1
        
    else
        # 无连接，尝试恢复
        if [ -z "$TARGET_MAC" ] && [ -f "$LAST_MAC_FILE" ]; then
            TARGET_MAC=$(cat "$LAST_MAC_FILE")
        fi
        
        if [ -n "$TARGET_MAC" ]; then
            echo "[$(date '+%H:%M:%S')] 断开 detected，恢复 $TARGET_MAC..."
            bluetoothctl trust "$TARGET_MAC" >/dev/null 2>&1
            #sleep 1
            bluetoothctl connect "$TARGET_MAC" >/dev/null 2>&1
            #sleep 1  # 等待连接建立
        else
            echo "[$(date '+%H:%M:%S')] 等待首次连接..."
            sleep 2
        fi
    fi
    
    sleep 5
done

cleanup
