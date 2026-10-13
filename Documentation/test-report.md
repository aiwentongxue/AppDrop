# AppDrop 测试报告

验证日期：2026-10-13（Asia/Shanghai）
环境：macOS 27.2（26B5101f）/ Xcode 27.0（27A266a）/ Swift 6.4 / Apple Silicon
签名：Apple Development（个人团队 HP5WBFL9G3）+ Xcode 托管描述文件（未公证）

本报告只记录**实际执行过**的验证及其证据；未执行项列在末尾。

---

## 1. 自动化单元测试（全部通过）

```bash
swift test --package-path SharedKit
```

结果：`Test run with 66 tests in 9 suites passed`。覆盖范围：

| 套件 | 覆盖点 |
| --- | --- |
| `AppStoreURLParserTests` | 四个区域合法链接、查询参数/尾斜杠/大小写、无 slug、itunes 域名、缺 ID、非法 ID、不支持域名、非法/缺失区域、垃圾输入 |
| `AppStoreServiceTests` | 字段与 Decimal 精确解析、免费应用与缺价格字段、缺失 ID、>50 分批（3 请求）、HTTP 5xx 重试后失败（3 次尝试）、404 不重试、超时重试、解码失败、部分成功保留、搜索/空关键词、HTTP 错误上抛、取消、URL 形状（`/lookup?id=…&country=…`） |
| `PriceEngineTests` | 首建基准、无价格条目、缺失价格→unavailable（绝不转 0）、持平不记录、降价百分比/新低、高于历史低点、持平于低点、上涨清折扣、币种变化重建、0 价除零安全、区域隔离 |
| `StoreTests` | 基准建档、无价导入、重复键拒绝、多区域独立、级联删除、降价落库与 notifiedAt、持平不追加、notFound/失败不覆盖价格、运行日志裁剪（200）、受限容器错误可见、Wishdrop 导入去重、测试工具接口 |
| `RefreshEngineTests` | 首次成功不通知、降价通知一次且重跑幂等、notFound 保留价格、失败批量标记错误、flock 互斥跳过、20h 逾期判断与补跑、更换区域（成功/失败不动数据） |
| `WishdropTests` | 编解码往返、非法 JSON、错误格式标识、未来版本拒绝、逐条校验问题码、导出规范化 URL |
| `FileLockTests` | 快速失败、等待超时、跨实例竞争 |
| `LocalizationTests` | en / zh-Hans 通知文案可解析 |
| `BackendStateTests` | `SMAppService.Status` 四态映射 |
| `PlaceholderTests(常量)` | App Group ID 与候选列表一致性 |

## 2. 构建与产物

| 项 | 结果 |
| --- | --- |
| Debug 构建（xcodebuild + `-allowProvisioningUpdates`） | ✅ BUILD SUCCEEDED |
| Release 构建 | ✅ BUILD SUCCEEDED |
| 结构 | ✅ `Contents/Library/LoginItems/AppDropHelper.app`、`Contents/Library/LaunchAgents/com.appdrop.helper.plist`、双份 `embedded.provisionprofile` |
| 签名 | ✅ `codesign --verify --deep --strict` 通过（App 与 Helper） |
| 架构 | ✅ Universal：`arm64 + x86_64` |
| 打包 | ✅ `dist/AppDrop-1.0.0-macOS-universal.zip`（2.1 MB），解压后复检签名通过、可运行 |
| 压缩包 SHA-256 | `ab004255f1397314d568275028f1523a4b73c16d37b5423b6237fbe3d85df406` |

## 3. 系统集成验证（真实运行）

以下均在**正常启动**（LaunchServices / launchd）下验证，而非只在终端上下文：

1. **同一份数据库**：主 App 与 Helper 各自 `--dump-store-info` 输出相同的 `storePath`（`~/Library/Group Containers/group.com.appdrop.shared/AppDrop/AppDrop.store`）；外部工具 `appdropctl` 写入的条目在主 App 界面立即可见（截图为证）。
2. **真实 API**：`appdropctl lookup` 与界面搜索均返回真实 iTunes 数据（Xcode / Things 3 / TestFlight 等）；价格字段与格式化文本正确。
3. **后台服务注册**：`AppDrop --backend-status` → `enabled`；`launchctl print gui/<uid>/com.appdrop.helper` 显示已提交服务（含 BundleProgram 与父 bundle）。
4. **launchd 真实后台运行**：`launchctl kickstart -k` 触发后，Helper 于 launchd 上下文完成真实查价：`helper.log` 记录 `outcome=success checked=3 changed=0 failed=0`，共享库 `checkRuns` 增加、`lastRun: background success checked=3`；主 App 设置页“最近尝试/最近成功/统计”同步显示。
5. **逾期跳过**：注册后首次自动运行时因距上次尝试 <20h 正确跳过（`run skipped because of the minimum interval`）。
6. **UI 流程（Computer Use 实测点击）**：
   - 主窗口：网格/列表切换、排序、区域筛选、搜索框、工具栏（添加/导入/导出/刷新）均存在且可交互（截图 `Documentation/screenshots/`）。
   - 详情页：当前价格/历史最低/最近变化/最近成功检查、`.stepEnd` 图表与“仅一条记录”兜底、App Store 链接。
   - 新增（搜索）：搜索 “Xcode” 返回真实结果（名称/开发者/价格/区域/图标），点击“添加”后列表出现新卡片（已随后清理）。
   - 更换区域弹窗：标题/说明/区域按钮/取消 正确（验证后取消，未改动数据）。
   - 删除弹窗：“停止追踪此应用？该应用在此区域的价格历史将被删除。”正确弹出（为遵守“GUI 删除需用户在场确认”的原则，验证后取消，实际清理用 CLI 完成）。
   - 设置页：默认区域（仅影响新加）、通知权限（主应用 已授权）、后台状态（已启用/最近尝试/最近成功/统计）、launchd 时间说明。
   - 导出：系统保存面板 → 实际写出 `AppDrop-Wishlist.wishdrop`，JSON 校验通过（测试文件随后移至 /tmp）。
   - 导入（Finder 打开）：自制样例（1 新增 + 1 已存在 + 2 无效）双击打开后弹出摘要：`新增 1 · 已存在 1 · 无效 2`，并逐条列出 `Invalid app id "12".`、`Unsupported storefront "de".`；导入条目显示“价格待获取/尚未检查”，随后清理。
   - 关窗退出：关闭最后一个窗口后进程退出，生命周期日志完整记录 `window willClose → applicationShouldTerminateAfterLastWindowClosed → applicationShouldTerminate`。
7. **通知链路**：
   - 主应用身份：模拟降价（库内价格 9.99 → 真实价格 Free）后手动刷新 → 记录 `decrease` 且 `notifiedAt` 已写入；系统日志 `[com.appdrop.app] Adding/Added notification request … hasError: 0`。
   - Helper 身份：当前权限为 `denied`（本轮测试中未在弹窗选择允许），因此后台运行触发的通知会被跳过并记录日志；开启路径见后台文档。

## 4. 未验证 / 局限

- **公证与分发签名**：未做 Developer ID 签名与 Apple 公证（无对应证书），`dist/` 产物仅适用于本机/开发场景。
- **Helper 通知的横幅可视确认**：已验证调度成功（API 返回无错误 + 记录标记），未截图留存横幅本身。
- **休眠/关机期间的行为**：launchd 语义上不会执行，本项目只保证“恢复后补跑”，未做真实休眠实验。
- **第二台机器**：个人团队 + 未公证签名在其他机器的表现未验证；本机所需的“完全磁盘访问权限”授权属于个人团队签名在 macOS 27 上的平台限制（详见 README/后台文档）。

## 5. 遗留物与清理说明

- `/Applications/AppDrop.app`：当前为 Release 版（干净安装，deep-strict 通过）；测试期间产生的临时追踪条目均已清理，用户在用的 3 个应用未改动。
- `~/Library/Group Containers/group.com.appdrop.shared/`：包含正式共享库（`AppDrop/AppDrop.store`）、`helper.log` 与 `refresh.lock`；根目录另有本次开发前遗留的 `AppDrop.sqlite`（未删除）。
- `/private/tmp/AppDrop-*`、`/tmp/group.HP5WBFL9G3.backup-*`、`/private/tmp/AppDrop-previous-install.app`：测试过程中的临时副本（可随时清理）。

## 6. 复现命令（节选）

```bash
swift test --package-path SharedKit
xcodebuild -project AppDrop.xcodeproj -scheme AppDrop -configuration Release \
  -derivedDataPath /private/tmp/AppDrop-Release-DD -allowProvisioningUpdates build
/Applications/AppDrop.app/Contents/MacOS/AppDrop --backend-status
launchctl kickstart -k gui/$(id -u)/com.appdrop.helper
tail -20 ~/Library/Group\ Containers/group.com.appdrop.shared/AppDrop/helper.log
```

## 7. 追加验证（2026-10-13 下午）

1. **应用图标**：`Scripts/make-appicon.py` 从用户提供原图生成 10 个尺寸；`AppDrop.app/Contents/Resources/AppIcon.icns` 与 `Assets.car` 生成成功，Info.plist 含 `CFBundleIconFile/CFBundleIconName = AppIcon`，Helper 同样带图标；用 `NSWorkspace.icon(forFile:)` 复现 Finder/Dock 渲染，确认图标填满整块、四周无白边。
2. **归档元数据修复**：为 Helper 设置 `SKIP_INSTALL = YES` 后，`xcodebuild archive` 产物只含 `AppDrop.app`，归档 `Info.plist` 出现 `ApplicationProperties`（Version 1.0.0 / SigningIdentity / Architectures arm64+x86_64）。
3. **导出单个 .app**：`xcodebuild -exportArchive`（method=debugging）成功导出 `/tmp/AppDrop-export/AppDrop.app`，`codesign --verify --deep --strict` 通过，`--dump-store-info` 正常读取共享库。
4. **重新打包**：`dist/AppDrop-1.0.0-macOS-universal.zip` 重新生成（含图标资源，解压后签名校验通过、可读取共享库）；最新 SHA-256 见下节。

## 8. 追加验证（搜索目录修复）

用户反馈“搜索只能搜到 iOS/iPadOS 应用”。定位结论与修复：

1. **根因**：iTunes Search API 中 `entity=software` 只覆盖 iPhone/iPad 目录，Mac 目录需要 `entity=macSoftware`（原实现固定用 `software`）。
2. **实测（真实 API）**：`entity=macSoftware` 能返回 Mac 应用（iStat Menus 7、Transporter、DevCleaner、Tomb Raider、Borderlands 2…），但该目录的响应会混入少量 iOS 条目，因此实现中按响应 `kind` 过滤。
3. **产品决策（按用户要求）**：搜索只提供 **Mac** 与 **iPhone·iPad** 两个选项，**默认 Mac**，不做排序或合并。
4. **索引缺口（Apple 侧限制）**：`lookup` 可查到 Palworld（6503918400）、Cyberpunk 2077: Ultimate（6633429424）等 Mac 应用，但 `search`（各种 `entity`/`media`/`attribute`/`limit` 组合与多个区域）均无法命中——属 Apple 搜索索引缺口。界面在“无结果或结果中没有任何名称与关键词匹配”时给出提示与「改用链接添加」按钮。
5. **实测证据**：
   - 命令行（真实 API）：`platform=mac` 搜索 “iStat Menus”/“DevCleaner” 只返回 macOS 条目；`platform=ios` 返回 iOS 条目。
   - 界面（Computer Use 实际点击）：默认 `平台 = Mac`；用户搜索 “cyberpunk 2077” 得到的全是 Mac 应用（Disco Elysium、Borderlands 2、Tomb Raider…）；搜索 “Palworld” 时出现索引缺口提示（“结果中没有与“Palworld”匹配的应用。”+ 改用链接添加）；点击后正确切换到「App Store 链接」页；用 Palworld 链接解析并加入时正确提示“已在追踪列表中（同一区域）”。
   - 单元测试：`swift test` 70 项通过（含 Mac 目录 entity、`kind` 过滤、默认平台、价格缺失时用 lookup 补全）。
6. **最新产物**：`dist/AppDrop-1.0.0-macOS-universal.zip`，SHA-256 `f8b48b36a9e80b8b290fdb299bce5c71d51d742e5c5baf4dfccfb9f15ffe6630`；`/Applications/AppDrop.app` 为同一 Release 构建（deep-strict 通过）。

