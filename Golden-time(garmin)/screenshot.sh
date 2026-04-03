#!/bin/bash
# 简化版截图脚本 - 手动选择窗口

SCREENSHOT_DIR="/Users/gloria/Documents/garmin-watch/Golden-time/screenshots"
mkdir -p "$SCREENSHOT_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
FILENAME="$SCREENSHOT_DIR/sim_$TIMESTAMP.png"

echo "📸 准备截图..."
echo "请用鼠标点击模拟器窗口（或按空格后点击窗口）"

# 交互式截图
screencapture -i -o "$FILENAME"

if [ -f "$FILENAME" ]; then
    echo "✅ 截图已保存: $FILENAME"
else
    echo "❌ 截图取消或失败"
    exit 1
fi
