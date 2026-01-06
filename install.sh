#!/bin/bash

# 定义监控脚本的路径和文件名
MONITOR_SCRIPT="/usr/local/bin/speedtest_monitor.sh"
# 定时任务：每12小时运行一次
CRON_JOB="0 */12 * * * sudo $MONITOR_SCRIPT > /dev/null 2>&1"

# --- 检查是否以root用户运行 ---
if [[ "$EUID" -ne 0 ]]; then
  echo "此脚本必须以root用户身份运行。请使用 sudo。"
  exit 1
fi

echo "--- 正在创建轻量化监控脚本 ${MONITOR_SCRIPT} ---"

# 写入子脚本内容
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash

# 环境变量设置
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --- 参数配置 ---
threshold_mbps=100  # 判定阈值 (Mbps)
test_file_size=10   # 测试文件大小 (MB)
# 使用 Cloudflare 的测速节点，全球响应速度快且稳定
test_url="https://speed.cloudflare.com/__down?bytes=10485760" 

# --- 依赖检查 ---
for pkg in curl bc; do
    if ! command -v $pkg &> /dev/null; then
        apt-get update && apt-get install -y $pkg
    fi
done

# --- 核心测速逻辑 ---
# 获取开始时间（纳秒）
start_time=$(date +%s.%N)

# 执行下载测试
http_code=$(curl -s -o /dev/null -w "%{http_code}" "$test_url")

# 检查下载是否成功
if [ "$http_code" -ne 200 ]; then
    echo "测速文件下载失败，HTTP状态码: $http_code"
    exit 1
fi

# 获取结束时间并计算耗时
end_time=$(date +%s.%N)
duration=$(echo "$end_time - $start_time" | bc)

# 计算带宽 (Mbps)
# 公式: (文件大小 10MB * 8 bit) / 耗时
download_speed_mbps=$(echo "scale=2; ($test_file_size * 8) / $duration" | bc)

echo "当前实测速度: ${download_speed_mbps} Mbps"

# --- 服务控制逻辑 ---
# 检查服务状态（兼容原脚本逻辑）
xrayr_status=$(xrayr status 2>&1 | tail -n 1)
v2bx_status=$(v2bx status 2>&1 | tail -n 2 | head -n 1)

if (( $(echo "$download_speed_mbps < $threshold_mbps" | bc -l) )); then
    echo "警告：速度低于阈值，正在停止服务..."
    [[ ! "$xrayr_status" =~ "Stopped" ]] && xrayr stop
    [[ ! "$v2bx_status" =~ "Stopped" ]] && v2bx stop
else
    echo "状态：速度达标，正在确保服务运行..."
    [[ "$xrayr_status" =~ "Stopped" ]] && xrayr start
    [[ "$v2bx_status" =~ "Stopped" ]] && v2bx start
fi
EOF

# 赋予执行权限
chmod +x "$MONITOR_SCRIPT"

# --- 设置定时任务 ---
echo "--- 正在设置定时任务 ---"
(crontab -l 2>/dev/null | grep -F "${MONITOR_SCRIPT}" | grep -v "grep") || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo "安装完成！"
echo "监控脚本：$MONITOR_SCRIPT"
echo "测速方式：10MB 文件下载测试（极省流量）"
echo "定时任务：每12小时自动运行一次"
