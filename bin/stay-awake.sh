#!/bin/bash
# stay-awake.sh — 保持 Mac 不睡眠/不锁屏
#
# 用法:
#   stay-awake.sh                 # 默认模式,12 小时,防熄屏+防锁屏
#   stay-awake.sh 6               # 默认模式,6 小时
#   stay-awake.sh forever         # 永不休眠模式,直到手动 stop
#   stay-awake.sh -alive          # 合盖不休眠模式,默认 2 小时(通勤场景)
#   stay-awake.sh -alive 1.5      # 合盖不休眠模式,1.5 小时
#   stay-awake.sh stop            # 停止所有模式 (含恢复合盖休眠设置)
#   stay-awake.sh status          # 查看当前状态

SCRIPT_NAME="stay-awake"
LOCK_FILE="/tmp/${SCRIPT_NAME}.pid"
ALIVE_PID_FILE="/tmp/${SCRIPT_NAME}-alive.pid"
ALIVE_END_FILE="/tmp/${SCRIPT_NAME}-alive.end"

# ============================================================
# 状态查询
# ============================================================
show_status() {
    local any=0
    if [ -f "$LOCK_FILE" ] && kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
        echo "[${SCRIPT_NAME}] 默认模式运行中 (PID $(cat "$LOCK_FILE"))"
        any=1
    fi
    if [ -f "$ALIVE_PID_FILE" ] && sudo -n kill -0 "$(cat "$ALIVE_PID_FILE")" 2>/dev/null; then
        local end_human="未知"
        [ -f "$ALIVE_END_FILE" ] && end_human=$(date -r "$(cat "$ALIVE_END_FILE")" '+%Y-%m-%d %H:%M:%S')
        echo "[${SCRIPT_NAME}] 合盖不休眠模式运行中 (守护 PID $(cat "$ALIVE_PID_FILE"))"
        echo "[${SCRIPT_NAME}] 计划恢复时间: ${end_human}"
        any=1
    fi
    local cur=$(pmset -g custom 2>/dev/null | awk '/disablesleep/ {print $2; exit}')
    [ -n "$cur" ] && echo "[${SCRIPT_NAME}] 当前 disablesleep 值: ${cur} (1=禁用休眠, 0=正常)"
    [ "$any" = "0" ] && echo "[${SCRIPT_NAME}] 没有运行中的实例"
}

# ============================================================
# 停止 + 恢复
# ============================================================
stop_default_mode() {
    if [ -f "$LOCK_FILE" ]; then
        OLD_PID=$(cat "$LOCK_FILE")
        if kill -0 "$OLD_PID" 2>/dev/null; then
            echo "[${SCRIPT_NAME}] 停止默认模式 (PID $OLD_PID)"
            kill "$OLD_PID" 2>/dev/null
            sleep 1
            kill -9 "$OLD_PID" 2>/dev/null
        fi
        rm -f "$LOCK_FILE"
    fi
    pkill -f "caffeinate -disu" 2>/dev/null
}

stop_alive_mode() {
    local need_restore=0
    if [ -f "$ALIVE_PID_FILE" ]; then
        local apid=$(cat "$ALIVE_PID_FILE")
        echo "[${SCRIPT_NAME}] 停止合盖守护进程 (PID $apid)"
        sudo kill "$apid" 2>/dev/null
        sleep 1
        sudo kill -9 "$apid" 2>/dev/null
        need_restore=1
    fi
    # 不管 pid 文件在不在,都强制把 disablesleep 恢复成 0,确保安全
    local cur=$(pmset -g custom 2>/dev/null | awk '/disablesleep/ {print $2; exit}')
    if [ "$cur" = "1" ] || [ "$need_restore" = "1" ]; then
        echo "[${SCRIPT_NAME}] 恢复 disablesleep=0 (允许合盖休眠)"
        sudo pmset -a disablesleep 0
    fi
    rm -f "$ALIVE_PID_FILE" "$ALIVE_END_FILE"
}

stop_all() {
    stop_default_mode
    stop_alive_mode
    echo "[${SCRIPT_NAME}] 已全部停止"
}

# ============================================================
# 命令分发
# ============================================================
case "$1" in
    stop)   stop_all; exit 0 ;;
    status) show_status; exit 0 ;;
esac

# ============================================================
# 合盖不休眠模式 (-alive)
# ============================================================
if [ "$1" = "-alive" ]; then
    HOURS="${2:-2}"
    if ! [[ "$HOURS" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "用法: $0 -alive [小时数, 默认 2]"
        exit 1
    fi

    SECONDS_TOTAL=$(awk "BEGIN {printf \"%d\", $HOURS * 3600}")
    END_EPOCH=$(( $(date +%s) + SECONDS_TOTAL ))
    END_HUMAN=$(date -r "$END_EPOCH" '+%Y-%m-%d %H:%M:%S')

    # 清理已有的同模式实例
    stop_alive_mode >/dev/null 2>&1

    echo "[${SCRIPT_NAME}] 合盖不休眠模式启动"
    echo "[${SCRIPT_NAME}] 持续 ${HOURS} 小时, 计划恢复: ${END_HUMAN}"
    echo "[${SCRIPT_NAME}] 需要 sudo 权限 (pmset 修改电源设置)..."

    # 提前缓存 sudo 凭证 (一次性,合盖后不会再问)
    sudo -v || { echo "[${SCRIPT_NAME}] sudo 验证失败,中止"; exit 1; }

    # 关键设计:启动一个完全脱离终端的 root 守护进程
    # 它用 setsid + nohup 双重保护,不会被任何信号杀掉(除了 kill -9)
    # 即使主脚本退出/终端关闭/电脑重启过 sudo 缓存,它都会按时恢复
    sudo bash -c "
        # 启用合盖不休眠
        pmset -a disablesleep 1

        # 写入恢复时间戳
        echo '$END_EPOCH' > '$ALIVE_END_FILE'

        # 后台守护:睡眠到点 -> 恢复 -> 自清理
        nohup setsid bash -c '
            sleep $SECONDS_TOTAL
            pmset -a disablesleep 0
            rm -f \"$ALIVE_PID_FILE\" \"$ALIVE_END_FILE\"
            logger -t stay-awake \"alive 模式到期,disablesleep 已恢复为 0\"
        ' >/dev/null 2>&1 < /dev/null &

        # 保存守护进程 PID
        echo \$! > '$ALIVE_PID_FILE'
        chmod 644 '$ALIVE_PID_FILE' '$ALIVE_END_FILE'
    "

    if [ -f "$ALIVE_PID_FILE" ]; then
        echo "[${SCRIPT_NAME}] 守护进程已启动 (PID $(cat "$ALIVE_PID_FILE"))"
        echo "[${SCRIPT_NAME}] 现在可以放心合盖了。${HOURS} 小时后自动恢复"
        echo "[${SCRIPT_NAME}] 提前停止: $0 stop"
        echo ""
        echo "⚠️  安全提示:"
        echo "   - 别把 Mac 塞进密闭包里,留点散热空间"
        echo "   - 确认电量充足或接电源"
        echo "   - 如果中途重启了电脑,记得运行 '$0 stop' 手动恢复"
    else
        echo "[${SCRIPT_NAME}] 启动失败"
        exit 1
    fi
    exit 0
fi

# ============================================================
# 默认模式 (防熄屏 + 防锁屏)
# ============================================================
stop_default_mode >/dev/null 2>&1

HOURS="${1:-12}"
FOREVER=0
case "$HOURS" in
    forever|always|on)
        FOREVER=1
        ;;
esac

if [ "$FOREVER" = "0" ] && ! [[ "$HOURS" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "用法: $0 [小时数|forever|-alive [小时数]|stop|status]"
    exit 1
fi

if [ "$FOREVER" = "1" ]; then
    END_EPOCH=0
    echo "[${SCRIPT_NAME}] 启动,持续到手动停止"
else
    SECONDS_TOTAL=$(awk "BEGIN {printf \"%d\", $HOURS * 3600}")
    END_EPOCH=$(( $(date +%s) + SECONDS_TOTAL ))
    END_HUMAN=$(date -r "$END_EPOCH" '+%Y-%m-%d %H:%M:%S')
    echo "[${SCRIPT_NAME}] 启动,持续 ${HOURS} 小时"
    echo "[${SCRIPT_NAME}] 结束时间: ${END_HUMAN}"
fi
echo "[${SCRIPT_NAME}] 手动停止: $0 stop"
echo "[${SCRIPT_NAME}] PID: $$"
echo "$$" > "$LOCK_FILE"

cleanup() {
    echo ""
    echo "[${SCRIPT_NAME}] 清理中..."
    pkill -P $$ 2>/dev/null
    pkill -f "caffeinate -disu" 2>/dev/null
    rm -f "$LOCK_FILE"
    exit 0
}
trap cleanup INT TERM EXIT

if [ "$FOREVER" = "1" ]; then
    caffeinate -disu &
else
    caffeinate -disu -t "$SECONDS_TOTAL" &
fi

while [ "$FOREVER" = "1" ] || [ "$(date +%s)" -lt "$END_EPOCH" ]; do
    osascript -e 'tell application "System Events" to key code 63' >/dev/null 2>&1
    sleep 50
done

cleanup
