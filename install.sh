#!/bin/bash

# ================= 配置区 =================
# 1. 在这里填入你的 TG 机器人信息
TG_BOT_TOKEN="你的_BOT_TOKEN"
TG_CHAT_ID="你的_CHAT_ID"

# 2. 定义监控脚本的路径和文件名
MONITOR_SCRIPT="/usr/local/bin/speedtest_monitor.sh"
# 定时任务：每12小时运行一次
CRON_JOB="0 */12 * * * sudo $MONITOR_SCRIPT > /dev/null 2>&1"
# ==========================================

# --- 检查是否以root用户运行 ---
if [[ "$EUID" -ne 0 ]]; then
  echo "此脚本必须以root用户身份运行。请使用 sudo。"
  exit 1
fi

echo "--- 正在创建带通知功能的监控脚本 ${MONITOR_SCRIPT} ---"

# 写入子脚本内容
cat > "$MONITOR_SCRIPT" << EOF
#!/bin/bash

# 环境变量设置
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --- 参数配置 ---
threshold_mbps=100  # 判定阈值 (Mbps)
test_file_size=10   # 测试文件大小 (MB)
test_url="https://speed.cloudflare.com/__down?bytes=10485760" 

# --- TG 通知函数 ---
send_tg_msg() {
    local message=\$1
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \\
        -d "chat_id=${TG_CHAT_ID}" \\
        -d "text=\$message" \\
        -d "parse_mode=Markdown"
}

# --- 依赖检查 ---
for pkg in curl bc; do
    if ! command -v \$pkg &> /dev/null; then
        apt-get update && apt-get install -y \$pkg
    fi
done

# --- 核心测速逻辑 ---
start_time=\$(date +%s.%N)
http_code=\$(curl -s -o /dev/null -w "%{http_code}" "\$test_url")

if [ "\$http_code" -ne 200 ]; then
    msg="⚠️ *测速异常*\\n节点：\$(hostname)\\n状态：测速文件下载失败 (HTTP \$http_code)"
    send_tg_msg "\$msg"
    exit 1
fi

end_time=\$(date +%s.%N)
duration=\$(echo "\$end_time - \$start_time" | bc)
download_speed_mbps=\$(echo "scale=2; (\$test_file_size * 8) / \$duration" | bc)

# --- 服务控制逻辑 ---
xrayr_status=\$(xrayr status 2>&1 | tail -n 1)
v2bx_status=\$(v2bx status 2>&1 | tail -n 2 | head -n 1)

if (( \$(echo "\$download_speed_mbps < \$threshold_mbps" | bc -l) )); then
    action="🔴 *速度不达标，停止服务*"
    [[ ! "\$xrayr_status" =~ "Stopped" ]] && xrayr stop
    [[ ! "\$v2bx_status" =~ "Stopped" ]] && v2bx stop
else
    action="✅ *速度达标，服务运行中*"
    [[ "\$xrayr_status" =~ "Stopped" ]] && xrayr start
    [[ "\$v2bx_status" =~ "Stopped" ]] && v2bx start
fi

# 发送最终执行结果
final_msg="📊 *节点测速报告*\\n--------------------\\n节点名称：\$(hostname)\\n实测带宽：*\${download_speed_mbps} Mbps*\\n判定阈值：\${threshold_mbps} Mbps\\n当前动作：\${action}"
send_tg_msg "\$final_msg"

EOF

# 赋予执行权限
chmod +x "$MONITOR_SCRIPT"

# --- 设置定时任务 ---
echo "--- 正在设置定时任务 ---"
(crontab -l 2>/dev/null | grep -F "${MONITOR_SCRIPT}" | grep -v "grep") || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo "安装完成！"
echo "监控脚本：$MONITOR_SCRIPT"
echo "测速通知将发送至您的 Telegram。"
