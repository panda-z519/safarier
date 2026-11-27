# Tasks

## 1. 管理器单实例锁与工作目录状态查询（SafarierCore）

- [x] 1.1 在 `Sources/SafarierCore` 中复用 `ProfileLock` 的 `flock` + PID 文件机制实现 `ManagerLock`（锁路径为 `<locksDirectory>/manager.lock`，权限 `0600`），并在 `SafarierWorkspace` 中新增 `managerPID()` 与 `isManagerRunning()`，编写单元测试覆盖抢锁、互斥拒绝、PID 读写、释放后重抢及与 `ProfileLock` 互不干扰，运行 `swift test --filter ProfileLockTests`（及新增锁测试）验证通过
- [x] 1.2 定义按 `workspace.root.standardizedFileURL.path` 隔离的管理器唤醒通知标识工具（如 `ManagerIPC` / 通知常量），并验证不同工作目录生成的隔离键互不相等

## 2. 跨进程管理器唤醒与拉起协调器（ManagerGUI & Browser 共用）

- [x] 2.1 新增 `ManagerLauncher`（或窗口唤醒协调器），实现“查 `managerPID()` → 进程存活时发送本机 `DistributedNotification` 并激活进程；进程不存在时在 `.app` 下以 `NSWorkspace.OpenConfiguration.createsNewApplicationInstance = true` 拉起新实例（透传 `SAFARIER_HOME`），裸二进制模式下回落为 `Process` 启动无参数可执行文件”，通过依赖注入编写单元测试覆盖存活唤醒、`.app` 新实例拉起与裸二进制回落三条路径，运行对应单测验证通过

## 3. 图形管理器窗口留驻、单实例启动与重启防竞态（ManagerGUI）

- [x] 3.1 修改 `Sources/Safarier/ManagerGUI/ManagerApp.swift` 与 `SafarierAppView.swift`：`applicationShouldTerminateAfterLastWindowClosed` 返回 `false`；将 SwiftUI `openWindow(id: "manager")` 与既有主窗口置前逻辑统一收口到 `showMainWindow()`；在 `applicationShouldHandleReopen`、`applicationDidBecomeActive`（无可见窗口时）及本机唤醒通知回调中调用 `showMainWindow()`；同时在管理器「窗口」菜单与 `applicationDockMenu` 提供「打开环境管理器」入口，并补充单元测试验证关闭留驻策略与窗口菜单/Dock 菜单绑定
- [x] 3.2 在 `ManagerGUI.start()` 中接入 `ManagerLock` 单实例保护（抢锁失败时唤醒已有管理器并静默退出），并修改 `UILanguage.relaunch()` 与 `AboutAndUpdateController.installUpdateAndRelaunch()` 在拉起新实例前主动释放 `ManagerLock`（`UILanguage` 拉起失败时重新获取锁），补充单测验证重启释放/回滚逻辑并确认编译零警告

## 4. 浏览器入口与中英文本地化（Browser & Resources）

- [x] 4.1 修改 `Sources/Safarier/Browser/BrowserMenu.swift` 与 `BrowserSession.swift`：在浏览器「窗口」菜单顶部新增「打开环境管理器」（快捷键 `⌥⌘0`，`BrowserActions.openManager(_:)`）并在 `validateMenuItem(_:)` 中始终返回 `true`；实现 `BrowserSession.applicationDockMenu(_:)` 返回含「打开环境管理器」的菜单；新增单元测试验证菜单项存在、快捷键正确、无窗口时仍可用及 Dock 菜单项动作正确
- [x] 4.2 在 `Resources/en.lproj/Localizable.strings` 中补齐「打开环境管理器」等全部新增中文界面文案的英文翻译（不修改或提交 `Resources/zh-Hans.lproj`），运行 `swift test --filter LocalizationCoverageTests` 验证零缺键、零占位符漂移

## 5. 全量集成验证与实机验收

- [x] 5.1 运行 `swift test` 确认全量单元测试通过且编译零警告，核对 `BuildAppInfoPlistTests` 与 `LocalizationCoverageTests` 全部通过
- [x] 5.2 通过 `scripts/dev.sh` 或打包后的 `Safarier.app` 执行实机端到端验收：有/无运行环境时点击主窗红叉 `X` 均隐藏不退出；分别通过点击管理器 Dock 图标、`⌘\`` 切回、浏览器菜单「窗口 → 打开环境管理器」（`⌥⌘0`）及右键浏览器 Dock 图标均能唤回主窗且保留编辑状态；`⌘Q` 退出管理器后从浏览器菜单或右键 Dock 图标可成功重新拉起管理器；切换界面语言后重启正常且不触发双开误退
