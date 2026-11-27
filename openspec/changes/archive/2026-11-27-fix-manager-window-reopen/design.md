# Design

## Context

详见 `proposal.md` 的背景说明。当前架构的核心约束决定了本设计的边界：

1. **同包多进程架构**：`Sources/Safarier/main.swift` 让同一个二进制 `Safarier.app/Contents/MacOS/Safarier` 根据命令行参数分别以图形管理器（无参数）、CLI（子命令）和浏览环境 Runner（`run ...`）身份运行；管理器与每个 Runner 均设 `NSApplication.ActivationPolicy.regular`，共用 `Safarier.app` 与 Bundle ID `sh.safarier.app`（见 `scripts/build-app.sh`）。
2. **数据存储强绑定 Bundle ID**：`Sources/SafarierWebKit/DataStoreManager.swift` 使用 `WKWebsiteDataStore(forIdentifier: profile.id)` 持久化各环境数据，管理器清理数据也直接调用 `WKWebsiteDataStore.remove(forIdentifier:)`。macOS 按当前进程 `CFBundleIdentifier` 划定 WebKit 持久化根目录，因此不能更改 Runner 的 Bundle ID。
3. **开发规范约束**（见 `CONTRIBUTING.zh-CN.md`）：
   - 仅使用公开 Foundation / AppKit / SwiftUI API，不新增私有 SPI、不发网络请求。
   - 新增中文界面文案必须在 `Resources/en.lproj/Localizable.strings` 补齐英文翻译并通过 `LocalizationCoverageTests`。
   - `ManagerModel` 是 `ManagerApp` 上的 `@StateObject`，且 `startMonitoring()` 已幂等（`guard monitor == nil else { return }`）。
   - `SafarierWorkspace.locksDirectory` 仅按具体 `<profileID>.lock` 访问与清理，不会盲扫误删其他锁文件。

## Goals / Non-Goals

**Goals:**
- 管理窗口关闭（点击红色关闭按钮或 `⌘W`）后管理器进程持续留驻，仅 `⌘Q` 退出，并可在点击管理器 Dock 图标、`⌘\`` 切回、浏览器菜单与任意 Dock 图标右键菜单时即时唤出主窗口。
- 即使管理器已被 `⌘Q` 退出或仅通过 CLI 启动了浏览器窗口，仍能从浏览器窗口的菜单或 Dock 右键菜单一键拉起新的管理器实例。
- 保证同工作目录下管理器单实例运行，同时消除语言切换与自动更新重启时的单实例锁竞态。
- 单实例锁与跨进程唤醒信号均按 `workspace.root` 隔离，保证 `SAFARIER_HOME` 单元测试零干扰、全量可测。

**Non-Goals:**
- 不将 Runner 拆分为独立 Bundle ID 的嵌套 Helper `.app`。
- 不在系统右上角菜单栏新增常驻状态栏图标（`NSStatusBar` / `MenuBarExtra`）。
- 不修改 Runner 收到 `applicationShouldHandleReopen(_, hasVisibleWindows: true)` 时的默认行为（避免用户点浏览器自己的 Dock 图标切窗口时被意外弹出的管理器打断）。
- 不调整浏览环境隐私模拟、WebKit 配置或代理出站链路。

## Decisions

### 决策 1：保持单 `.app` 与 `sh.safarier.app` Bundle ID，通过“留驻 + 单实例协调 + 显式拉起”闭环解决
- **选择**：保持现有 `.app` 打包结构与 `sh.safarier.app` 不变，在应用层补齐留驻、跨进程唤醒与新实例拉起。
- **备选方案与放弃原因**：将 Runner 拆为独立 Bundle ID（如 `sh.safarier.runner`）的嵌套 Helper `.app`。该方案会导致升级后所有老用户持久环境的 `WKWebsiteDataStore(forIdentifier:)` 数据路径漂移（Cookie 与登录态丢失）、管理器无法清理 Runner 的沙盒数据，并破坏现有 `BuildAppInfoPlistTests` 与自动更新打包契约。

### 决策 2：管理器采用 `applicationShouldTerminateAfterLastWindowClosed = false` + SwiftUI `openWindow` 唤醒，不覆盖 SwiftUI 内部 `NSWindow.delegate`
- **选择**：
  - `ManagerAppDelegate.applicationShouldTerminateAfterLastWindowClosed(_:)` 改为返回 `false`。
  - 在 `ManagerApp` / `SafarierAppView` 中将 SwiftUI `@Environment(\.openWindow)` 桥接注册给管理器窗口协调器（同时保留对当前可见/隐藏主窗口的查找与 `makeKeyAndOrderFront` 能力）。
  - 统一通过 `showMainWindow()` 处理唤出：若已有管理窗口实例则取消最小化并置前；若窗口已被 SwiftUI 关闭则调用 `openWindow(id: "manager")` 重新打开并 `NSApp.activate(ignoringOtherApps: true)`。
  - 在以下 3 个时机触发 `showMainWindow()`：
    1. `applicationShouldHandleReopen(_:hasVisibleWindows:)`（`!flag` 时）；
    2. `applicationDidBecomeActive(_:)`（当主窗口均不可见时，覆盖从浏览器按 `⌘\`` 经 `WindowCycler` 切回隐藏管理器的路径）；
    3. 收到跨进程唤醒通知时。
- **备选方案与放弃原因**：
  - 覆盖 SwiftUI `Window` 的 `nsWindow.delegate` 在 `windowShouldClose` 中拦截并 `orderOut(nil)`。由于 SwiftUI `Window` 内部依赖自身 `AppKitWindowDelegate` 维护工具栏、场景状态与尺寸恢复，直接替换 delegate 存在兼容性隐患。且 `ManagerModel` 已在 `App` 层由 `@StateObject` 持有，关闭再通过 `openWindow(id: "manager")` 重开已能保留所有编辑草稿（`profileEditors`）、选中项与监控定时器。
  - 智能策略（无 Runner 时关窗退出、有 Runner 时隐藏）：用户已明确选择纯 macOS 惯例（一律留驻，仅 `⌘Q` 退出），行为更一致、无状态分支困惑。

### 决策 3：在 `SafarierCore` 复用 `flock` + PID 机制实现 `ManagerLock`，以 `DistributedNotificationCenter` 发送本机唤醒信号
- **选择**：
  - 在 `SafarierCore` 抽离或扩展 `ProfileLock` 底层文件锁逻辑，新增 `ManagerLock`（锁文件路径为 `<workspace.locksDirectory>/manager.lock`，权限 `0600`，写入当前进程 PID；进程退出或崩溃由内核自动释放）。
  - 在 `SafarierWorkspace` 新增 `managerPID() -> Int32?` 与 `isManagerRunning() -> Bool`。
  - 跨进程唤醒使用 `DistributedNotificationCenter.default()`：
    - 通知名固定为 `sh.safarier.manager.reopen`；
    - 通知 `object` 为规范化后的 `workspace.root.standardizedFileURL.path`（与 `SAFARIER_HOME` 绑定）；
    - 发送时带 `deliverImmediately: true`。
  - 管理器进程启动早期（在 `UILanguage.applyAtLaunch()` 之后、进入 `ManagerApp.main()` 之前）尝试获取 `ManagerLock`：
    - 获取成功：持有锁直至进程退出（或重启前主动释放）；
    - 获取失败（`.alreadyRunning`）：向同工作目录发送唤醒通知并尝试 `NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])`，随后自身以退出码 `0` 退出。
- **备选方案与放弃原因**：
  - 仅靠 `NSWorkspace.shared.runningApplications` 判断管理器是否存活：由于管理器与 Runner 具有完全相同的 `bundleIdentifier` 和 `executableURL`，`NSRunningApplication` 无法区分某个进程是管理器还是浏览器 Runner；必须靠 `manager.lock` 精确识别管理器 PID。
  - 为管理器新建 Unix Domain Socket 监听服务：相比 `flock` + `DistributedNotificationCenter` 过于重型，且需要额外管理 socket 文件权限、清理与异步读写线程；本项目唤醒动作无需双向数据载荷，单向通知 + PID 激活已足够简单可靠。

### 决策 4：语言切换与自动更新重启前主动释放 `ManagerLock`
- **选择**：
  - 在 `ManagerGUI` 暴露统一的锁持有与释放方法（例如 `releaseManagerLockForRelaunch()` 与失败回滚重新拿锁）。
  - `UILanguage.relaunch()` 在调用 `NSWorkspace.shared.openApplication` 之前先释放 `ManagerLock`；若 `openApplication` 回调报错（新进程未拉起），再尝试重新获取锁。
  - `AboutAndUpdateController.installUpdateAndRelaunch()` 在拉起重启子进程前同样先释放 `ManagerLock`。
- **原因**：这两个重启路径均为“旧进程先启动新实例，旧进程再调用 `NSApp.terminate(nil)`”，若不提前释放锁，新实例会在启动阶段检测到锁被旧进程占用而误判双开并主动退出，导致新旧两个管理器同时消失。

### 决策 5：浏览器端提供「打开环境管理器」顶部菜单项与程序坞右键菜单，经 `ManagerLauncher` 统一路由
- **选择**：
  - 封装可测试的 `ManagerLauncher`（依赖注入 `managerPID` 查询、唤醒通知发送、进程激活、`.app` 多实例启动与裸二进制回落启动）：
    1. 若 `managerPID()` 存在且对应 `NSRunningApplication` 未终止：发送本机唤醒通知并调用 `activate(options: [.activateAllWindows])`。
    2. 否则（管理器未运行或已退出）：
       - 当运行在 `.app` 包内（`Bundle.main.bundleURL.pathExtension == "app"`）：使用 `NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)`，其中 `config.createsNewApplicationInstance = true`、`config.activates = true`（若存在 `SAFARIER_HOME` 环境变量则透传）。
       - 当运行在开发模式裸二进制（如 `scripts/dev.sh`）：回落为 `Process` 直接拉起无参数的 `RunnerLauncher.currentExecutableURL()`（沿用当前环境变量）。
  - 入口位置：
    - `BrowserMenu.swift`：「窗口」菜单顶部新增「打开环境管理器」（快捷键 `⌥⌘0`，`BrowserActions.openManager(_:)`）；在 `BrowserSession.validateMenuItem(_:)` 中始终返回 `true`（即使当前无浏览窗口也可用）。
    - `BrowserSession.swift`：实现 `applicationDockMenu(_:)`，返回包含「打开环境管理器」的 `NSMenu`。
    - `ManagerApp.swift`：管理器自身「窗口」菜单（`CommandGroup`）和 `ManagerAppDelegate.applicationDockMenu(_:)` 同样提供「打开环境管理器」，统一调用 `showMainWindow()`。

## Risks / Trade-offs

- **[Risk] SwiftUI `@Environment(\.openWindow)` 在最后一个 `Window` 场景关闭后的可用性依赖 macOS 版本行为** → **Mitigation**：在 `ManagerApp` 的 `commands` 或 `App` 级捕获并测试 `openWindow(id: "manager")`；同时在 `showMainWindow()` 中优先复用已存在的管理器 `NSWindow`（调用 `deminiaturize` + `makeKeyAndOrderFront`），仅在无窗口时调 `openWindow(id: "manager")`，并在实现完成后进行本机实测验证关窗后再重开。
- **[Risk] 用户点击了属于浏览器的 Dock 图标（而非管理器的 Dock 图标）或从 Spotlight 打开 `Safarier.app` 时，macOS LaunchServices 仍可能优先激活浏览器进程** → **Mitigation**：保留了管理器常驻 Dock 图标供直接左键唤醒；同时在浏览器顶部「窗口」菜单（含快捷键 `⌥⌘0`）与**所有** Safarier Dock 图标的右键菜单里都提供「打开环境管理器」，确保任意场景下 1 步可达，且绝不干扰正常点击浏览器 Dock 图标切换浏览窗口的手感。
- **[Risk] `openApplication` 在管理器退出后极短时间内重复点击触发并发双开** → **Mitigation**：由 `ManagerLock` 兜底互斥，后抢锁的实例自动唤醒先抢锁的实例并静默退出。
- **[Risk] 新增中文菜单文案遗漏英文翻译导致 `LocalizationCoverageTests` 失败** → **Mitigation**：同步更新 `Resources/en.lproj/Localizable.strings` 并在任务收尾跑全量 `swift test` 验证。
