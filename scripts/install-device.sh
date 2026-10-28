#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--help" ]]; then
  echo "用法：DEVELOPMENT_TEAM=你的个人团队ID ./scripts/install-device.sh [--check]"
  echo "连接多台设备时，再设置 DEVICE_ID=目标设备的 CoreDevice 标识或 UDID。"
  exit 0
fi
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--check" ) ]]; then
  echo "未知参数。运行 ./scripts/install-device.sh --help 查看用法。" >&2
  exit 2
fi

if [[ ! "${DEVELOPMENT_TEAM:-}" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "请先设置 DEVELOPMENT_TEAM 为你自己的 Personal Team ID，不要使用组织团队。" >&2
  exit 2
fi
if ! command -v jq >/dev/null; then
  echo "缺少 jq，无法安全读取已连接设备信息。" >&2
  exit 2
fi

devices_json=$(mktemp)
details_json=$(mktemp)
profile_plist=$(mktemp)
trap 'rm -f "$devices_json" "$details_json" "$profile_plist"' EXIT

xcrun devicectl list devices --json-output "$devices_json" >/dev/null
if [[ -n "${DEVICE_ID:-}" ]]; then
  device_id=$DEVICE_ID
else
  device_count=$(jq '[.result.devices[] | select(.hardwareProperties.platform == "iOS" and .connectionProperties.tunnelState == "connected")] | length' "$devices_json")
  if [[ "$device_count" -ne 1 ]]; then
    echo "需要恰好连接一台 iPhone；当前找到 $device_count 台。多台设备请设置 DEVICE_ID。" >&2
    xcrun devicectl list devices >&2
    exit 2
  fi
  device_id=$(jq -r '.result.devices[] | select(.hardwareProperties.platform == "iOS" and .connectionProperties.tunnelState == "connected") | .identifier' "$devices_json")
fi

xcrun devicectl device info details --device "$device_id" --json-output "$details_json" >/dev/null
device_id=$(jq -r '.result.identifier' "$details_json")
device_udid=$(jq -r '.result.hardwareProperties.udid // empty' "$details_json")
device_name=$(jq -r '.result.deviceProperties.name' "$details_json")
developer_mode=$(jq -r '.result.deviceProperties.developerModeStatus' "$details_json")
if [[ -z "$device_udid" || "$developer_mode" != "enabled" ]]; then
  echo "未取得设备 UDID，或 iPhone 尚未开启开发者模式。请先在手机设置中开启。" >&2
  exit 2
fi

echo "手机：$device_name ($device_udid)"
echo "签名团队：${DEVELOPMENT_TEAM}（请确认是你自己的 Personal Team）"
if [[ "${1:-}" == "--check" ]]; then
  echo "设备与参数检查通过；未构建或安装。"
  exit 0
fi

xcodebuild -project Prompter.xcodeproj -scheme Prompter -configuration Debug \
  -destination "platform=iOS,id=$device_udid" -derivedDataPath build/device \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates build

app="build/device/Build/Products/Debug-iphoneos/Prompter.app"
if [[ ! -d "$app" ]]; then
  echo "构建成功但找不到安装包：$app" >&2
  exit 1
fi

codesign --verify --deep --strict "$app"
signed_team=$(codesign -dv --verbose=4 "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)
security cms -D -i "$app/embedded.mobileprovision" > "$profile_plist"
profile_team=$(plutil -extract TeamIdentifier.0 raw -o - "$profile_plist")
if [[ "$signed_team" != "$DEVELOPMENT_TEAM" || "$profile_team" != "$DEVELOPMENT_TEAM" ]]; then
  echo "签名团队与指定的个人团队不一致，已停止安装。" >&2
  exit 1
fi
if ! plutil -extract ProvisionedDevices json -o - "$profile_plist" | jq -e --arg udid "$device_udid" 'index($udid) != null' >/dev/null; then
  echo "描述文件不包含这台 iPhone，已停止安装。" >&2
  exit 1
fi

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
echo "安装 $bundle_id；不会先卸载手机上的 App。"
xcrun devicectl device install app --device "$device_id" "$app"

if ! xcrun devicectl device process launch --device "$device_id" "$bundle_id"; then
  echo "已安装但未能启动。请在 iPhone 的 设置 → 通用 → VPN与设备管理 中信任开发者，然后手动打开 App。" >&2
  exit 1
fi
echo "安装并启动成功。"
