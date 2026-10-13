# AppDrop

AppDrop 是一款原生 macOS App Store 价格追踪应用：追踪不同商店区域（US / HK / JP / CN）的应用价格，查看历史走势与历史新低，并在降价时通过系统本地通知提醒。

## 技术栈

| 组件 | 技术 |
| --- | --- |
| 语言 / UI | Swift 6（语言模式 6）+ SwiftUI（macOS 14.0+） |
| 图表 | Swift Charts（`.stepEnd` 阶梯折线） |
| 持久化 | SwiftData（App Group 共享库，主 App 与后台 Helper 共用一份数据库） |
| 后台调度 | ServiceManagement / `SMAppService.agent(plistName:)` + launchd（`StartInterval = 86400`，按需执行后退出） |
| 通知 | UserNotifications（主 App 与 Helper 各自授权） |
| 网络 | URLSession（iTunes Search/Lookup API，自动重试、分批与并发控制） |
| 工程 | XcodeGen（`project.yml` → `AppDrop.xcodeproj`）+ SwiftPM 本地包 `SharedKit` |
| 测试 | Swift Testing（`swift test`，66 项） |
| 图标 | 由 `Scripts/make-appicon.py` 从单张原图生成完整 AppIcon 资源集（自动去掉白边/投影并填满画布） |

## 目录结构

```
AppDrop.xcodeproj            # 由 xcodegen 生成（勿手改，改 project.yml 后重新生成）
project.yml                  # 工程定义（targets / 签名 / 复制阶段 / Info.plist）
AppDrop/                     # 主应用（App / Views / ViewModels / Resources / entitlements）
AppDropHelper/               # 后台助手（LSUIElement 小 App，main.swift + entitlements + launchd plist）
SharedKit/                   # 共享 SwiftPM 包（Models / Services / Data / Utilities + Tests + appdropctl）
Tests/integration/           # 集成验证脚本说明（见 Documentation/test-report.md）
Documentation/               # 构建、后台服务、Wishdrop 格式与测试报告
dist/                        # 构建产物（AppDrop-1.0.0-macOS-universal.zip + SHA-256）
```

## 构建与运行

```bash
# 1. 生成 Xcode 工程
xcodegen generate

# 2. 单元测试（Swift Testing，离线 mock，不依赖真实价格）
swift test --package-path SharedKit

# 3. Debug 构建
xcodebuild -project AppDrop.xcodeproj -scheme AppDrop -configuration Debug \
  -derivedDataPath /private/tmp/AppDrop-DD -allowProvisioningUpdates build

# 4. Release 构建（Universal：arm64 + x86_64）
xcodebuild -project AppDrop.xcodeproj -scheme AppDrop -configuration Release \
  -derivedDataPath /private/tmp/AppDrop-Release-DD -allowProvisioningUpdates build

# 5. 组装 zip（干净目录复制，避免旧文件残留破坏签名）
ditto -c -k --keepParent /private/tmp/AppDrop-Release-DD/Build/Products/Release/AppDrop.app \
  dist/AppDrop-1.0.0-macOS-universal.zip
```

详细说明（含签名、安装、排错）见 [Documentation/build-and-run.md](Documentation/build-and-run.md)。

## 应用图标

```bash
python3 Scripts/make-appicon.py <源图路径> AppDrop/Resources/Assets.xcassets/AppIcon.appiconset
```

脚本会：自动识别源图中的图标本体（忽略白色背景与投影）→ 用“背景色平面拟合 + 扩散”填充四角 → 生成 16…1024px 的完整 macOS AppIcon 资源集（App 与 Helper 共用）。

## 搜索与平台

“添加应用 → 搜索”提供 **Mac** 与 **iPhone·iPad** 两个目录选项，**默认 Mac**：

- Mac 目录使用 iTunes `entity=macSoftware`，并额外按响应的 `kind` 过滤（该目录会混入少量 iOS 条目）；iPhone/iPad 目录使用 `entity=software`。
- 结果行会显示 `Mac` / `iPhone·iPad` 徽章，便于区分。
- 已知限制：Apple 的搜索索引并不包含全部应用（例如部分新上架的 Mac 游戏：Palworld、Cyberpunk 2077: Ultimate 用 `lookup` 能查到、`search` 却查不到）。这类应用请用「App Store 链接」添加（实测有效）；搜索无匹配结果时界面会直接给出该提示与跳转按钮。

## 归档与导出

在 Xcode 中 `Product → Archive` 后，Organizer 会显示 `Version 1.0.0`；`Distribute App → Copy App（或 Debugging）` 可导出单个 `.app`。命令行等价流程：

```bash
xcodebuild -project AppDrop.xcodeproj -scheme AppDrop -configuration Release \
  -archivePath /private/tmp/AppDrop.xcarchive -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath /private/tmp/AppDrop.xcarchive \
  -exportPath /private/tmp/AppDrop-export -exportOptionsPlist ExportOptions.plist
```

注意：Helper 目标必须保持 `SKIP_INSTALL = YES`（见 `project.yml`），否则归档里会出现两个可安装产物、Xcode 不写入 `ApplicationProperties`，Organizer 便会显示“版本 —”且无法分发。

## 支持的 macOS 版本

- 最低部署目标：macOS 14.0（当前构建使用 Xcode 27 / macOS SDK 27）。

## App Group 与共享数据库

- App Group：`group.com.appdrop.shared`（主 App 与 Helper 的 entitlements 均声明；两端数据库路径完全一致：`~/Library/Group Containers/group.com.appdrop.shared/AppDrop/AppDrop.store`）。
- 共享库采用显式 URL 的 `ModelConfiguration`；容器解析使用“真实写入探测”，解析失败会明确报错，**绝不静默回退到私有数据库**。设置页的“共享存储”会显示当前实际解析到的容器。
- 跨进程写入由 App Group 容器内 `flock` 咨询锁串行化，并由“价格记录 + notifiedAt”幂等标记保证不会重复通知。

## 后台任务工作方式

- 主 App 通过 `SMAppService.agent(plistName: "com.appdrop.helper.plist")` 注册内嵌的 `AppDropHelper.app`（位于 `Contents/Library/LoginItems/`）；launchd plist 位于 `Contents/Library/LaunchAgents/`。
- Helper 默认带 `--scheduled` 参数运行：距上次尝试不足 20 小时则跳过；`--run-now` 强制执行；完成写库与通知后退出，不常驻、不轮询。
- `StartInterval = 86400` 只是“尽力调度”：Mac 休眠/关机期间不会执行，醒来后由“逾期判断”补跑。界面会如实显示注册状态（`未注册 / 已启用 / 等待系统批准 / 未找到`）与最近尝试/成功/失败信息。

## 通知权限

macOS 的通知权限按进程身份独立：

1. **AppDrop（主应用）**：首次启动引导中申请；手动刷新触发的降价通知使用该权限。
2. **AppDrop Helper（后台助手)**：首次运行后台检查前独立申请一次（“AppDrop Helper”）；launchd 后台运行触发的降价通知使用该权限。若被拒绝，可在「系统设置 → 通知 → AppDrop Helper」中开启。

通知权限被拒绝不影响价格历史记录；通知失败不会被当作价格查询失败。

## 已知限制（诚实清单）

- **签名与公证**：当前为个人团队（Personal Team）Apple Development 签名 + Xcode 托管描述文件，**未做 Developer ID 签名与公证**，仅适合本机/开发使用；对外分发需付费开发者账号。
- **换到另一台 Mac 运行**：需要（1）放行 Gatekeeper（未公证）；（2）在“系统设置 → 隐私与安全性 → 完全磁盘访问权限”中允许 AppDrop 与 AppDrop Helper（个人团队签名下 App Group 容器受 TCC 保护）；（3）注意内嵌描述文件仅 7 天有效期，过期需重新构建。详见 [Documentation/build-and-run.md](Documentation/build-and-run.md) 的“分发到另一台 Mac”一节。
- **本机额外授权**：个人团队签名下，macOS 27 的 Group Containers 受 TCC 保护，需在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中允许 AppDrop（与 AppDrop Helper）。若使用付费账号并启用 App Groups 能力，则无需该授权。
- `StartInterval` 不保证准时；休眠/关机可能错过或延迟检查。
- 不做汇率换算，不合并不同区域的“最低价”；同一应用不同区域为独立追踪项。
- “较上次降价”基于两次有效价格之差，**不是**商店官方促销折扣；界面不会显示虚构的划线原价。
- 免费应用（价格 0）不参与降幅计算（无除零风险）；导入的心愿单条目在首次成功查价前显示“价格待获取”，不会用 0 元占位。

## 相关文档

- [构建与运行](Documentation/build-and-run.md)
- [后台服务启用与排错](Documentation/background-helper.md)
- [Wishdrop 文件格式](Documentation/wishdrop-format.md)
- [测试报告（含证据）](Documentation/test-report.md)

