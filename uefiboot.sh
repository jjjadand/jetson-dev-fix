#!/bin/bash

# 配置：匹配 Fanxiang 或 256GB（不区分大小写）
TARGET_KEYWORDS="Fanxiang|256GB"
LOG_FILE="/var/log/set-boot-order.log"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    log "错误：请使用 sudo 运行此脚本"
    exit 1
fi

# 检查 efibootmgr 是否安装
if ! command -v efibootmgr &> /dev/null; then
    log "错误：未找到 efibootmgr，请先安装：sudo apt install efibootmgr"
    exit 1
fi

log "开始查找启动项，匹配关键字：Fanxiang 或 256GB"

# 获取 efibootmgr 输出
EFI_OUTPUT=$(efibootmgr 2>&1)
if [ $? -ne 0 ]; then
    log "错误：无法执行 efibootmgr"
    log "$EFI_OUTPUT"
    exit 1
fi

# 查找目标启动项编号（匹配 Fanxiang 或 256GB，不区分大小写）
# 使用 -E 支持正则，-i 忽略大小写
TARGET_ENTRY=$(echo "$EFI_OUTPUT" | grep -iE "$TARGET_KEYWORDS" | head -1 | grep -oE 'Boot[0-9A-Fa-f]{4}' | head -1 | sed 's/Boot//')

if [ -z "$TARGET_ENTRY" ]; then
    log "错误：未找到包含 'Fanxiang' 或 '256GB' 的启动项"
    log "当前可用启动项："
    echo "$EFI_OUTPUT" | grep -E "^Boot[0-9A-Fa-f]{4}" | tee -a "$LOG_FILE"
    exit 1
fi

# 显示匹配到的具体是哪一项（用于确认）
MATCHED_LINE=$(echo "$EFI_OUTPUT" | grep -iE "$TARGET_KEYWORDS" | head -1)
log "找到匹配项：$MATCHED_LINE"
log "提取启动项编号：Boot$TARGET_ENTRY"

# 获取当前启动顺序
CURRENT_ORDER=$(echo "$EFI_OUTPUT" | grep "^BootOrder:" | awk '{print $2}')

if [ -z "$CURRENT_ORDER" ]; then
    log "错误：无法获取当前启动顺序"
    exit 1
fi

log "当前启动顺序：$CURRENT_ORDER"

# 检查是否已经在第一位
FIRST_ENTRY=$(echo "$CURRENT_ORDER" | cut -d',' -f1)
if [ "$FIRST_ENTRY" = "$TARGET_ENTRY" ]; then
    log "目标启动项已经在第一位，无需修改"
    exit 0
fi

# 构建新的启动顺序：目标项放第一，其余保持原顺序
NEW_ORDER="$TARGET_ENTRY"
IFS=',' read -ra ENTRIES <<< "$CURRENT_ORDER"
for entry in "${ENTRIES[@]}"; do
    if [ "$entry" != "$TARGET_ENTRY" ]; then
        NEW_ORDER="$NEW_ORDER,$entry"
    fi
done

log "准备设置新启动顺序：$NEW_ORDER"

# 执行修改
if ! efibootmgr -o "$NEW_ORDER" > /dev/null 2>&1; then
    log "错误：efibootmgr -o 命令执行失败"
    exit 1
fi

# 验证修改
sleep 1
VERIFY_OUTPUT=$(efibootmgr)
VERIFY_ORDER=$(echo "$VERIFY_OUTPUT" | grep "^BootOrder:" | awk '{print $2}')

if [ "$VERIFY_ORDER" = "$NEW_ORDER" ]; then
    log "成功：启动顺序已修改为：$VERIFY_ORDER"
    log "当前第一启动项：$(echo "$VERIFY_OUTPUT" | grep "Boot$TARGET_ENTRY" | sed 's/^\*/ /')"
    exit 0
else
    log "错误：修改未生效，当前顺序：$VERIFY_ORDER"
    exit 1
fi
