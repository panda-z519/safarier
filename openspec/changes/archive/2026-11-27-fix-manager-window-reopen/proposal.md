# Proposal

## Why

当前 Safarier 管理器进程与各浏览器环境（Runner）进程共用同一个 `.app` 包与 Bundle ID（`sh.safarier.app`），且管理器在最后一个窗口关闭后会直接退出（`applicationShouldTerminateAfterLastWindowClosed` 返回 `true`）。当用户点击管理窗口左上角红色关闭按钮后，只要桌面上仍有浏览器窗口在运行，macOS LaunchServices 会将程序坞（Dock）、聚焦搜索（Spotlight）和访达（Finder）的重新打开事件路由到仍在运行的浏览器进程，且浏览器内也没有打开管理器的入口，导致管理窗口在有浏览窗口运行时彻底无法再次唤醒。

## What Changes

- **管理器窗口采用原生 macOS 留驻惯例**：关闭管理窗口（点击关闭按钮或 `⌘W`）仅关闭/隐藏窗口而不退出管理器进程，仅在用户显式退出（`⌘Q` 或菜单「退出 Safarier」）时终止进程。
- **管理器单实例锁与跨进程唤醒**：在 `SafarierCore` 中基于现有 `flock` + PID 文件机制新增管理器单实例锁（`locks/manager.lock`），防止重复打开多个管理器实例，并支持按 `workspace.root.path` 隔离的本机跨进程唤醒信号；在语言切换和自动更新重启拉起新实例前主动释放锁，避免重启竞态。
- **多路径唤醒管理窗口**：
  - 点击管理器程序坞图标（`applicationShouldHandleReopen`）自动重新显示主窗口。
  - 从浏览器窗口通过 `⌘\`` 切回管理器（`applicationDidBecomeActive` 且当前无可见窗口）自动重新显示主窗口。
  - 在浏览器顶部「窗口」菜单（附快捷键 `⌥⌘0`）及每个浏览器进程程序坞右键菜单（`applicationDockMenu`）中新增「打开环境管理器」入口：管理器存活时激活并唤醒主窗口，管理器已退出时以多实例模式拉起新管理器进程（裸二进制开发模式回落为直接拉起可执行文件）。
  - 管理器自身菜单与程序坞右键菜单提供一致的显示主窗口入口。
- **保持界面克制与兼容性**：不新增系统右上角状态栏图标；保持单 `.app` 与 `sh.safarier.app` Bundle ID 不变，确保既有持久化环境的 `WKWebsiteDataStore(forIdentifier:)` 数据、本地化打包配置与隐私隔离原则不受影响。
- **补齐中英文文案与自动化测试**：在 `Resources/en.lproj/Localizable.strings` 中补充新增文案的英文条目，并为锁机制、唤醒路由、菜单绑定与管理器生命周期策略补充单元测试。

## Capabilities

### New Capabilities
- `manager-window-lifecycle`: 图形管理器窗口关闭留驻、单实例协调，以及在浏览器进程运行期间从程序坞、快捷键、浏览器菜单和右键程序坞菜单唤醒或拉起管理器的完整生命周期行为。

### Modified Capabilities

## Impact

- **`SafarierCore`**：新增 `ManagerLock`（或扩展锁工具）与 `SafarierWorkspace` 的管理器状态查询方法（`managerPID()`、`isManagerRunning()`）。
- **`Safarier` / `ManagerGUI`**：调整 `ManagerApp.swift`、`SafarierAppView.swift`、`UILanguage.swift`、`AboutAndUpdateController.swift`，新增跨进程唤醒协调器。
- **`Safarier` / `Browser`**：调整 `BrowserMenu.swift` 与 `BrowserSession.swift`，增加「打开环境管理器」菜单项、快捷键与 `applicationDockMenu` 实现。
- **本地化与测试**：更新 `Resources/en.lproj/Localizable.strings`，在 `Tests/SafarierCoreTests` 和 `Tests/SafarierAppTests` 中补充单元测试；不修改 `WKWebsiteDataStore`、WebKit 原生桥接层、网络代理或 `.app` Bundle 结构。
