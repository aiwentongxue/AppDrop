# 构建与运行

## 环境要求

- macOS 27（当前验证环境）/ Xcode 27.0（含命令行工具）；Swift 6.4。
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。
- 签名：本机已配置 Apple ID（个人团队）。主 App 与 Helper 使用 `Automatic` 签名 + Xcode 托管描述文件（见 `project.yml` 的 `CODE_SIGN_STYLE`/`DEVELOPMENT_TEAM`）。

## 常用命令

```bash
# 生成工程（修改 project.yml 或增删文件后都要执行）
xcodegen generate

# 单元测试（不需要网络；使用 mock URLProtocol）
swift test --package-path SharedKit

# Debug / Release 构建（-allowProvisioningUpdates 让 CLI 复用/刷新 Xcode 托管描述文件）
xcodebuild -project AppDrop.xcodeproj -scheme AppDrop -configuration Debug \
  -derivedDataPath /private/tmp/AppDrop-DD -allowProvisioningUpdates build
xcodebuild -project AppDrop.xcodeproj -scheme AppDrop -configuration Release \
  -derivedDataPath /private/tmp/AppDrop-Release-DD -allowProvisioningUpdates build

# 校验产物（结构 + 深层签名）
codesign --verify --deep --strict --verbose=2 /private/tmp/AppDrop-Release-DD/Build/Products/Release/AppDrop.app

# 安装：务必复制到"干净位置"，ditto 是合并复制，直接覆盖旧副本会残留旧文件并破坏签名
mv /Applications/AppDrop.app /private/tmp/AppDrop-旧副本.app   # 如已安装
ditto /private/tmp/AppDrop-Release-DD/Build/Products/Release/AppDrop.app /Applications/AppDrop.app

# 头less 诊断入口（脚本/排错用）
/Applications/AppDrop.app/Contents/MacOS/AppDrop --dump-store-info
/Applications/AppDrop.app/Contents/MacOS/AppDrop --backend-status
/Applications/AppDrop.app/Contents/MacOS/AppDrop --register-backend | --unregister-backend
/Applications/AppDrop.app/Contents/MacOS/AppDrop --store-diagnose   # 容器可写性探测
```

## 开发工具 `appdropctl`

位于 `SharedKit/Sources/AppDropCtl`，不随 App 分发：

```bash
swift build --package-path SharedKit --product appdropctl
CTL=.build/debug/appdropctl           # 或 --scratch-path 下的产物
$CTL store-path                       # 显示解析到的容器与数据库路径
$CTL info / list                      # 共享库内容与最近一次检查
$CTL add-test-entry --track-id 497799835 --country us --price 9.99 --currency USD --formatted '$9.99'
$CTL simulate-drop --track-id 497799835 --country us      # 抬高库内价格以在下次真实查价时制造“降价”
$CTL records --track-id 497799835 --country us            # 历史记录（含 notified 标记）
$CTL clear-runs                                           # 清空运行历史（用于强制触发后台补跑）
$CTL export-wishdrop --output /tmp/list.wishdrop
$CTL import-wishdrop --input /tmp/list.wishdrop
$CTL lookup --track-id 497799835 --country us             # 真实 API 冒烟
```

## 排错

- **打开即显示“无法打开共享数据库”**：说明当前进程未被允许访问 App Group 容器。执行 `AppDrop --store-diagnose` 查看两个候选容器的可写性；个人团队签名需在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中允许 AppDrop 与 AppDrop Helper。
- **`codesign --verify --deep --strict` 报 “sealed resource is missing or invalid”**：安装/复制时把新构建合并进了旧目录。请先把目标 App 移走再复制（见上）。
- **Xcode 里出现 3 个警告**：个人团队的描述文件不包含 App Groups 能力，Xcode 会提示；本机通过完全磁盘访问权限放行（见 README 已知限制）。
- **CLI 构建提示无法创建描述文件**：确认 Xcode 已登录 Apple ID，并带上 `-allowProvisioningUpdates` 重试。

## 应用图标

图标资源位于 `AppDrop/Resources/Assets.xcassets/AppIcon.appiconset`（App 与 Helper 共用）：

```bash
python3 Scripts/make-appicon.py /path/to/source.png AppDrop/Resources/Assets.xcassets/AppIcon.appiconset
```

脚本要求 Pillow / numpy / scipy。它会自动定位图标本体（排除白色底与投影）、把四角用背景色平滑填满（保证“填满、无白边”），并输出 16…1024 的全部尺寸与 `Contents.json`。换图后重新构建即可。

## 归档（Archive）与导出单个 .app

```bash
# 归档（等价于 Xcode 的 Product → Archive）
xcodebuild -project AppDrop.xcodeproj -scheme AppDrop -configuration Release \
  -archivePath /private/tmp/AppDrop.xcarchive -allowProvisioningUpdates archive

# 导出单个 .app（等价于 Organizer 的 Distribute App → Debugging / Copy App）
xcodebuild -exportArchive -archivePath /private/tmp/AppDrop.xcarchive \
  -exportPath /private/tmp/AppDrop-export \
  -exportOptionsPlist /private/tmp/AppDrop-ExportOptions.plist
```

`ExportOptions.plist` 示例（开发签名，个人团队可用）：

```xml
<dict>
  <key>method</key><string>debugging</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>HP5WBFL9G3</string>
</dict>
```

### “Organizer 里看不到版本 / 无法分发”的成因与修复

如果归档里同时存在多个可安装产物（例如把内嵌的 `AppDropHelper.app` 也当成独立 App 归档），Xcode 不会写入归档的 `ApplicationProperties`，于是 Organizer 的 Version 列显示“—”，也无法分发/导出。修复方式：为 Helper 目标设置 `SKIP_INSTALL = YES`（已写入 `project.yml`）。修复后归档只包含 `AppDrop.app`，`Info.plist` 中会出现：

```
"ApplicationProperties" => { CFBundleShortVersionString = 1.0.0; CFBundleIdentifier = com.appdrop.app; SigningIdentity = …; Team = HP5WBFL9G3; … }
```

另外，早期工程曾关闭 Xcode 签名（改用手动 codesign）时生成的归档也缺少这些元数据；请用当前工程重新 `Product → Archive`。

## 分发到另一台 Mac（重要）

### 先做“可分享构建”（`Scripts/make-shareable-build.sh`）

正常 Archive 出来的 `.app` 里嵌着 Xcode 托管的**开发**描述文件，它的 `ProvisionedDevices` 只登记了打包这台 Mac，并且 7 天过期。这类构建在**别的 Mac 上会在启动前被系统拦下**（现象正是“应用程序“AppDrop”无法打开。”，进程根本没启动，因此按进程名过滤日志为空），Gatekeeper 放行与 `xattr -cr` 都不会改变结果。

```bash
Scripts/make-shareable-build.sh \
  /private/tmp/AppDrop-Release-DD/Build/Products/Release/AppDrop.app \
  /private/tmp/AppDrop-shareable/AppDrop.app
```

脚本会：复制一份产物 → 删除两份 `embedded.provisionprofile`（主 App 与 Helper）→ 用 Apple Development 证书 + entitlements 重新签名（保留沙盒与 App Group 权限）→ `codesign --verify --deep --strict` 自检。产物不再有设备限制与 7 天有效期问题。

当前产物是**开发签名（个人团队）+ 未公证**，因此换一台 Mac 运行时有三道独立的关口，缺一不可：

1. **Gatekeeper**：未公证的 App 会被拦截（提示“无法验证开发者/已损坏”）。`xattr -cr` 只清除隔离标记，不等于放行；需要在目标机器右键“打开”，或用 `sudo spctl --global-disable` 关闭 Gatekeeper。本机之所以一直能直接打开，是因为本机 Gatekeeper 已全局关闭（`spctl --status` → `assessments disabled`）。
2. **完全磁盘访问权限（本方案必需）**：数据库位于 App Group 容器 `~/Library/Group Containers/group.com.appdrop.shared`，macOS 26+ 对该目录做 TCC 保护；而个人团队描述文件**不包含 App Groups 能力**（实测描述文件里只有 `application-identifier`/`team-identifier`/`keychain-access-groups`）。因此必须在那台机器上到「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中允许 **AppDrop** 与 **AppDrop Helper**，否则 App 能启动但会停在“无法打开共享数据库”页面。
3. **描述文件有效期**：内嵌的 “Mac Team Provisioning Profile” 有效期为 **7 天**（当前这份到 2026-10-20 过期），且 `ProvisionedDevices` 只登记了打包这台 Mac 的硬件 UUID。过期后请重新 Archive/导出再分发；长期分发应改用付费账号。

其他注意事项：

- **数据不会随 App 走**：追踪列表存在每台机器各自的 App Group 容器里。迁移用 App 内的「导出心愿单 / 导入心愿单」（`.wishdrop`）。
- **后台检查需在目标机器重新启用**：SMAppService 注册是按用户/按机器生效的。
- **正式分发方案**：付费 Apple Developer 账号 → Developer ID 签名 + 公证（Gatekeeper 无需放行、无需完全磁盘访问、证书 1 年有效）。

