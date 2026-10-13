# 后台服务（Helper）启用与排错

## 组件与位置

```
AppDrop.app/Contents/Library/LoginItems/AppDropHelper.app      # 后台助手（LSUIElement，无 Dock 图标）
AppDrop.app/Contents/Library/LaunchAgents/com.appdrop.helper.plist
```

plist 关键字段：

| 字段 | 值 | 说明 |
| --- | --- | --- |
| `Label` | `com.appdrop.helper` | launchd 服务名 |
| `BundleProgram` | `Contents/Library/LoginItems/AppDropHelper.app/Contents/MacOS/AppDropHelper` | 相对 App 包根路径 |
| `ProgramArguments` | `--scheduled` | 默认按需模式 |
| `RunAtLoad` | `true` | 注册成功先跑一次（逾期判断会挡住过频执行） |
| `StartInterval` | `86400` | 目标间隔 24h（不保证准时） |
| `ProcessType` | `Background` | 低优先级 |
| `AssociatedBundleIdentifiers` | `com.appdrop.app` | 系统设置中的归属显示 |

## 启用/停用

- App 内：首次启动引导 → “启用后台检查”；或「设置 → 后台检查」开关（无授权时开关保持开启并显示“等待系统设置批准”）。
- 命令行：`AppDrop --register-backend` / `--unregister-backend` / `--backend-status`。
- 重新注册（更新 Helper 或 plist 后需要）：设置页「重新注册后台服务」，或先 `--unregister-backend` 再 `--register-backend`。

## 运行语义

- Helper 在被 launchd 唤起或手动执行时加载共享库、按国家分批查询、应用价格规则、写历史与通知，然后退出；**不常驻、不轮询**。
- 距上次尝试不足 20 小时则跳过（`--run-now` 可强制）；因此“每天一次”是上限而不是严格周期。
- 网络失败只记录状态与错误，不会覆盖价格；同一价格变化只会通知一次（记录级 `notifiedAt` 幂等标记 + 跨进程 flock）。

## 状态含义（设置页 / `--backend-status`）

| 状态 | 含义 |
| --- | --- |
| `notRegistered` | 未注册 |
| `enabled` | 已注册且获准运行 |
| `requiresApproval` | 已注册，等待「系统设置 → 通用 → 登录项与扩展」批准 |
| `notFound` | 已注册但服务丢失（重新注册可修复） |

## Helper 的独立通知权限

后台降价通知由 Helper 身份发送，首次运行前需要单独授权一次（弹窗名称为“AppDrop Helper”）。若未授权：价格与历史照常记录，仅跳过通知（helper.log 中可见 `notification skipped: permission is ...`）。开启路径：「系统设置 → 通知 → AppDrop Helper → 允许通知」。

## 排错

```bash
# 查看服务是否注册/运行中
launchctl print gui/$(id -u)/com.appdrop.helper

# 立刻强制跑一次（会尊重 20h 间隔；如需强制，先 appdropctl clear-runs）
launchctl kickstart -k gui/$(id -u)/com.appdrop.helper

# Helper 诊断（容器可写性、共享库可读性、通知权限）
/Applications/AppDrop.app/Contents/Library/LoginItems/AppDropHelper.app/Contents/MacOS/AppDropHelper --store-diagnose

# 运行日志（共享容器内，含跳过原因/结果统计）
tail -20 ~/Library/Group\ Containers/group.com.appdrop.shared/AppDrop/helper.log
```

## 本机权限说明（重要）

macOS 27 将 `~/Library/Group Containers` 列为 TCC 保护目录；containermanagerd 会拒绝未获授权的进程（日志：*“Requestor's signature does not allow it to access a TCC-protected group container”*）。在**个人团队签名**下需要在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中允许：

1. `/Applications/AppDrop.app`
2. `/Applications/AppDrop.app/Contents/Library/LoginItems/AppDropHelper.app`

主 App 与 Helper 均在正常启动（LaunchServices/launchd）下验证过可读写共享库。使用**付费开发者账号**并把 App Groups 能力写入描述文件后，该额外授权不再需要。

