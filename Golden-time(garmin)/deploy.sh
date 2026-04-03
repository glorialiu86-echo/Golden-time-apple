#!/bin/bash
# 构建 + 部署 + 自动截图脚本

set -e  # 遇到错误立即退出

PROJECT_DIR="/Users/gloria/Documents/garmin-watch/Golden-time"
SDK_BIN="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-8.4.1-2026-02-03-e9f77eeaa/bin"

cd "$PROJECT_DIR"

echo "🔨 开始构建..."
"$SDK_BIN/monkeyc" \
    --jungles monkey.jungle \
    --device fenix7s \
    --output bin/Golden-time.prg \
    --private-key developer_key \
    --warn

echo ""
echo "📱 部署到模拟器..."
"$SDK_BIN/monkeydo" bin/Golden-time.prg fenix7s &

# 等待模拟器启动和渲染
echo "⏳ 等待模拟器渲染（5秒）..."
sleep 5

echo ""
echo "📸 自动截图..."
./screenshot.sh

echo ""
echo "✅ 完成！截图已保存到 screenshots/ 目录"
