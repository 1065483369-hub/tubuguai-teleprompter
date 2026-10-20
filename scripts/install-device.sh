#!/bin/bash
# 一条命令：编译 → 签名 → 装到手机 → 启动。
#
# 前提（只需做一次）：
#   1. Xcode → Settings → Accounts 重新登录 Apple ID
#   2. 手机插数据线，在手机上点「信任此电脑」
#
# 之后每次改代码只跑这个脚本就行。
set -e
cd "$(dirname "$0")/.."

# 自动找已连接的设备
# 按 UUID 形状抓，不按列号 —— 设备名含空格/中文时列会错位
DEV=$(xcrun devicectl list devices 2>/dev/null \
  | grep -iE 'available|connected' \
  | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' \
  | head -1)
if [ -z "$DEV" ]; then
  echo "找不到已连接的设备。检查数据线，或 xcrun devicectl list devices"
  exit 1
fi

# 从证书里取真正的 team ID（OU 字段，不是 CN 括号里的成员 ID —— 那个是错的）
TEAM="${DEVELOPMENT_TEAM:-$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null \
  | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p' | head -1)}"
if [ -z "$TEAM" ]; then
  echo "找不到签名证书。在 Xcode 里登录 Apple ID 后重试。"
  exit 1
fi

echo "设备 $DEV"
echo "team $TEAM"
echo ""

xcodebuild -project Prompter.xcodeproj -scheme Prompter -sdk iphoneos \
  -destination "id=$DEV" -derivedDataPath build/device \
  DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates \
  build | grep -E "error:|warning:|BUILD" || true

APP=$(find build/device/Build/Products -name "Prompter.app" -maxdepth 3 | head -1)
[ -n "$APP" ] || { echo "构建产物没找到"; exit 1; }

echo ""
echo "安装 $APP"
xcrun devicectl device install app --device "$DEV" "$APP"

echo ""
echo "启动"
xcrun devicectl device process launch --device "$DEV" local.prompter.app

cat <<'TIP'

首次运行手机上会提示"不受信任的开发者"：
  设置 → 通用 → VPN与设备管理 → 开发者App → 信任

验证 PiP 请按这个顺序：
  1. 粘稿子 → 开始 → 念稿，文字是否跟着走
  2. 点「浮窗」→ 是否出现画中画窗口
  3. 切到系统相机 → 浮窗是否还在、文字是否还在滚   ← 关键
  4. 系统相机开始录制 → 浮窗是否还在（会闪一下"音频被占用·恢复中"）
  5. 把浮窗拖到镜头正下方
TIP
