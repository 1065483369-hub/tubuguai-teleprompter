# 把兔不乖的提词器装到 iPhone

这是一个 iOS 源码项目，**不能只在 iPhone 上点“下载 ZIP”就直接安装**。第一次安装需要 Mac 和 Xcode。App 本身免费；以下步骤使用你自己的 Apple 账号，不需要加入任何组织开发团队。

## 准备好这些

- 一台 Mac，以及从 App Store 安装的 Xcode。工程是 Xcode 16 格式；如果你的 iPhone 已升级到 iOS 26，使用支持该系统的 Xcode 26。
- 一台 iOS 16 或更新版本的 iPhone、一根可传数据的线、一个自己的 Apple 账号。免费的 Apple 账号就可以做个人真机测试。
- 从 [GitHub 仓库](https://github.com/1065483369-hub/tubuguai-teleprompter) 下载源码 ZIP 并解压，或在 Mac 终端运行：

```bash
git clone https://github.com/1065483369-hub/tubuguai-teleprompter.git
cd tubuguai-teleprompter
```

## 第一次安装

1. 在 Mac 上双击 `Prompter.xcodeproj`。打开 Xcode → Settings → Apple Accounts，登录你自己的 Apple 账号。
2. 用数据线连接 iPhone。手机弹出“信任此电脑”时点“信任”。若 Xcode 提示开启开发者模式，在 iPhone 的“设置 → 隐私与安全性 → 开发者模式”开启，按提示重启手机。
3. 在 Xcode 左侧点蓝色 `Prompter` 项目图标，选 `Prompter` **应用 Target**，打开 `Signing & Capabilities`。勾选 `Automatically manage signing`，在 `Team` 里选你的 **Personal Team**，不要选公司或其他组织团队。
4. 如果出现“Bundle Identifier 已被使用”，把应用 Target 里的 `Bundle Identifier` 改成你自己的唯一名称，例如 `com.yourname.tubuguai`。不要改成别人的团队 ID。
5. 在 Xcode 顶部运行目标里选你的 iPhone，按 `⌘R`。等 Xcode 构建、签名并安装；第一次可能要稍等。
6. 如果手机提示“不受信任的开发者”，打开“设置 → 通用 → VPN 与设备管理”，找到刚才用于签名的个人开发者并点“信任”，然后重新打开 App。首次使用相机、麦克风、语音识别和相册时，再按需要允许权限。

装好后，先用示例稿试读一小段，再测试录制和浮窗。切换到系统相机前，要先在 App 内开启浮窗。

## 下次更新

保留源码项目，在 Xcode 中重新选中自己的 iPhone，按 `⌘R` 即可更新。**不要先删除旧 App**；使用相同的 Bundle ID 和个人团队覆盖安装，才能尽量保留设备上的本地稿件与设置。

也可以用可选脚本。先在 Xcode 完成上面的个人团队选择，再在项目目录的终端运行：

```bash
DEVELOPMENT_TEAM=你的个人团队ID ./scripts/install-device.sh --check
DEVELOPMENT_TEAM=你的个人团队ID ./scripts/install-device.sh
```

这里的 Team ID 是 10 位字母数字，不是 Apple 账号邮箱，也不是证书名称。可在 Xcode 选好 Personal Team 后运行 `xcodebuild -project Prompter.xcodeproj -target Prompter -showBuildSettings | grep 'DEVELOPMENT_TEAM ='` 查看。连接多台设备时，再设置 `DEVICE_ID`；脚本不会替你猜测要用哪一台手机或哪一个团队。脚本需要 Mac 上有 `jq`；缺少时请用 Xcode 的 `⌘R` 路径。

## 免费账号的限制

Apple 的免费 Personal Team 描述文件约 **7 天到期**。到期后 App 可能无法再打开，需要回到 Xcode 重新构建、安装；这不是本项目收费。安装到朋友的 iPhone 时，朋友也应在自己的 Mac 上用自己的 Personal Team 签名。要让普通用户免用 Xcode 一键安装，则需要另行通过 TestFlight 或 App Store 分发。

如果你让桌面 AI 助手帮忙，可以把这句话发给它：

> 请在我的 Mac 上从 GitHub 下载这个 iOS 项目，先检查源码和安装教程。只用我自己的 Apple Personal Team 签名；不要自动选第一张证书，也不要卸载手机上已有的 App。需要登录 Apple 账号、在手机上信任或开启开发者模式时，停下来让我自己操作。安装后请验证 App 能启动，并告诉我免费签名的到期时间。

Apple 的免费账号规则见[开发者账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account/)；开发者模式步骤见 [Apple 文档](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。
