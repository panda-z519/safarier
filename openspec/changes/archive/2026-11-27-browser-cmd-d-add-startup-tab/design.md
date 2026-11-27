# Design

## Context

参见 `proposal.md` 中的问题背景与目标范围。在当前代码库中：
- 浏览器窗口运行在独立的 Runner 进程中，通过 `BrowserMenu`（AppKit）组装菜单，`BrowserSession` 持有启动时的 `Profile` 快照与 `SafarierWorkspace`。
- 环境配置统一存储在 `workspace.profiles`（`RecordRepository<Profile>`，对应 `profiles.json`），该仓储已具备 `NSLock` + 独立 `.lock` 文件的 `flock` 跨进程排他锁，但现有 `update(_:)` 接口接收完整 `Profile`，若直接由浏览器用启动快照调用会覆盖管理器新修改的字段。
- 环境管理器目前仅在启动、手动 `⌘R` 或窗口重新激活（`NSApplication.didBecomeActiveNotification`）时调用 `ManagerModel.reload()`；跨进程唤醒已有成熟的 `ManagerWakeup` + `DistributedNotificationCenter`（按 `workspace.managerWakeupScope` 隔离）模式。
- 启动页签校验统一使用 `AddressInput.webURL(for:)`，且 `LocalizationCoverageTests` 强制校验源码中所有 `L10n.text(...)` 中文字面量均已在英文表注册且格式占位符一致。

## Goals / Non-Goals

**Goals:**
- 在浏览器端提供与原生 macOS Safari 按 `⌘D` 视觉位置、紧凑排版、键盘体验一致的模态下拉 Sheet。
- 实现跨进程并发安全的 `profiles.json` 局部原子更新，绝对不覆盖管理器已保存的其他环境属性。
- 实现浏览器写盘后对同工作目录环境管理器的即时刷新，同时完全兼容 `ProfileEditorState` 既有的未保存草稿冲突保护。
- 为本次新增提供可回滚的原子「撤销」能力，并在首位启用项变化时顺滑更新当前浏览器会话的 `⇧⌘H` 首页目标。
- 保持核心逻辑纯函数化与可测性，沿用项目现有的 `XCTest` 风格覆盖核心仓储、URL 裁剪、表单状态机、Sheet 交互及本地化覆盖率。

**Non-Goals:**
- 不引入浏览器书签系统或文件夹层级（只服务于当前环境的 `startupTabs`）。
- 不在浏览器窗口中直接编辑/删除其他历史启动页签（批量排序与管理仍留在环境管理器中）。
- 不改变已有启动页签的持久化 JSON Schema（沿用 `Profile.startupTabs` 与 `startURL` 兼容投影逻辑）。
- 不改变「修改启动页签不影响当前已打开标签页」的既有约定。

## Decisions

### 1. 弹窗形态：无标题栏 `NSPanel` + `window.beginSheet(_:)`（而非 `NSAlert` 或 `NSPopover`）
- **决策**：使用紧凑无标题栏 `NSPanel`（宽约 `392pt`）搭配 `NSVisualEffectView`（或标准窗口内容视图）并通过 `window.beginSheet(_:)` 附着在浏览器窗口工具栏正下方。
- **理由**：
  - `NSAlert` 左侧固定带有应用大图标，语义偏向“告警/二次确认”，与原生 Safari `⌘D` 的清爽表单感不符；
  - `NSPopover` 带指向尖角且点击窗外易误关，偏离用户明确要求的“原生 Safari 快捷键弹窗位置及风格”；
  - `window.beginSheet(_:)` 正是原生 macOS Safari 按 `⌘D` 的底层呈现机制，自带工具栏下沿正中滑出动效、圆角阴影与窗口级模态聚焦，且天然支持 `↩` 默认按钮和 `Esc` 取消按钮。
- **替代方案**：SwiftUI `NSHostingView` 嵌入 Sheet 虽可行，但浏览器端现有 UI（`BrowserViews.swift`、`AddressBar.swift`、`BrowserWindowController.swift`）全为纯 AppKit 实现，直接用轻量 AppKit 控制器可避免混栈焦点与第一响应者（自动全选文本）坑点，也更方便像 `CloseConfirmationTests` 一样做零 UI 阻塞的同步单测。

### 2. 网址裁剪与等价比较逻辑下沉至 `SafarierCore`
- **决策**：在 `AddressInput`（或同模块小型辅助枚举）提供纯函数：
  - `removingQueryAndFragment(from url: URL) -> URL?`：清除 `query` 与 `fragment`（`URLComponents` 置空 `query`/`fragment`）；
  - `originOnly(from url: URL) -> URL?`：仅保留 `scheme`、`host` 与非默认 `port`；
  - `isSameStartupURL(_ lhs: URL, _ rhs: URL) -> Bool`：按规范化后的 scheme/host（忽略大小写）与 path/query/fragment 比对，同时兼容根路径 `/` 与空路径的常见等价（如 `https://example.com` 与 `https://example.com/`）。
- **理由**：UI 按钮启用态判定、裁剪转换、重复检测均可复用到独立单测中，避免把字符串解析逻辑散落在 AppKit 视图层。

### 3. 跨进程安全写入：`RecordRepository.mutate(id:_:)`
- **决策**：在 `RecordRepository<Record>` 新增公开方法：
  ```swift
  @discardableResult
  public func mutate<T>(id: UUID, _ body: (inout Record) throws -> T) throws -> T
  ```
  该方法复用内部已有的 `mutate(_:)`（在 `NSLock` + `flock(LOCK_EX)` 文件锁内完成 `load → 按 id 查找 → 执行闭包修改 → record.validate() → save`），找不到记录时抛 `RepositoryError.notFound(id)`。
- **理由**：
  - 与浏览器进程直接用旧 `session.profile` 调 `update(_:)` 相比，锁内重读保证了管理器刚保存的代理/节点/备注/其他启动页签绝不会被回退；
  - 新增与撤销（按插入的 `StartupTab.id` 移除，或恢复被重新启用项的原 `isEnabled` 与原索引）都走同一原子路径，并发安全。
- **替代方案**：由浏览器通过 IPC 请求管理器代写。该方案在管理器已退出（`⌘Q`）时会失效，而 Safarier 允许浏览器脱离管理器独立运行，因此直接通过带 `flock` 的 `RecordRepository` 落盘是唯一在管理器关闭时依然可用的方案。

### 4. 跨进程实时刷新管理器：复用 `DistributedNotificationCenter`
- **决策**：在 `SafarierCore/ManagerLock.swift`（靠近 `ManagerWakeup`）新增 `ProfilesSyncNotification`（例如 `Notification.Name("sh.safarier.profiles.changed")`），沿用 `ManagerWakeup.workspaceScope(for: root)` 作为 `object` 隔离标识。
  - 浏览器写入或撤销成功后，通过 `DistributedNotificationCenter.default().postNotificationName(..., object: workspace.managerWakeupScope, userInfo: nil, deliverImmediately: true)` 广播；
  - 管理器 `ManagerModel` 在 `startMonitoring()` 注册对应观察者并在 `deinit` / 停止监控时移除，收到通知后在 `@MainActor` 上调用既有的 `reload()`。
- **理由**：零新增依赖、完全本机离线、与既有 `ManagerWakeup` 隔离策略一致；且 `reload()` 内部已调用 `editor.receive(profile)`，天然尊重 `ProfileEditorState.hasChanges`，不会覆写用户正在编辑的草稿。
- **替代方案**：使用 `DispatchSource` 监控 `profiles.json` 文件节点。由于 `JSONDocumentStore` 采用原子替换写入会改变 inode，vnode 监控容易漏事件或需要监控目录并做防抖过滤；分布式通知更直接且与项目已有架构一致。

### 5. 浏览器会话内 `⇧⌘H` 首页同步与底部撤销轻提示
- **决策**：
  - 将 `BrowserSession.profile` 调整为 `private(set) var profile: Profile`（或维护单独的 `private(set) var currentStartupTabs: [StartupTab]`，并在 `goHome(_:)` 读取 `effectiveStartURL`），当 `⌘D` 成功写入或撤销后，将本次落盘后的最新 `startupTabs` 同步回 `session` 内存状态。这样：
    - 用户选择「设为首页」或为原本空列表添加首个启动页签后，当前窗口按 `⇧⌘H` 立即生效；
    - 撤销后 `⇧⌘H` 也会立即回到撤销前的目标；
    - `profile` 其他运行时不可变属性（代理、机型、存储模式）保持不变。
  - 浏览器窗口底部叠加轻量悬浮 Toast 视图（位于 `webView` 容器底部居中，不抢键盘焦点，3.5 秒自动淡出，包含「撤销」按钮；若再次打开 `⌘D` 或窗口关闭则自动清理计时器）。
  - 撤销快照仅保留本次操作的最小语义（`added(tabID: UUID)` 或 `reenabled(tabID: UUID, previousIndex: Int)`），撤销时也在 `flock` 锁内按 `tabID` 精准回滚，即使期间用户在管理器又改了其他项也不会错删。

### 6. 本地化与菜单位置
- **决策**：
  - 菜单挂载在 `BrowserMenu`「文件」菜单中「打开位置… (`⌘L`)」正下方，名称「添加到启动页签…」，快捷键 `⌘D`；
  - 新增所有 `L10n.text(...)` 文案同步补充至 `Resources/en.lproj/Localizable.strings` 与 `Resources/ru.lproj/Localizable.strings`（保持现有按模块分组风格和准确格式占位符），并运行 `LocalizationCoverageTests` 验收。

## Risks / Trade-offs

- **[风险] 重复添加与暂停态判重遇到 URL 细微差异（如尾部斜杠、大小写域名）** → **缓解**：使用 `AddressInput.isSameStartupURL` 统一规范化 scheme/host 大小写和根路径尾部斜杠；带不同 path 或 query 的网址视为不同页面，符合用户预期。
- **[风险] 管理器正处于未保存编辑状态时，用户切去浏览器按 `⌘D` 写入导致管理器列表看似未立即更新** → **缓解**：这是 `ProfileEditorState.receive(_:)` 的刻意安全设计（避免丢失用户正在输入的表单草稿）；管理器在用户保存时会明确提示「环境已在其他位置修改，请先还原为最新设置」，确保数据一致性。
- **[风险] 用户在浏览器按 `⌘D` 时快速连按多次，或正在展示其他 Sheet（如关闭确认框）** → **缓解**：`BrowserWindowController` 在弹出前检查 `window.attachedSheet == nil`，若当前窗口已有 Sheet 在展示则直接忽略或聚焦现有 Sheet，防止重复叠加。
- **[风险] 浏览器窗口内撤销后又触发重新启用，原位置索引越界** → **缓解**：撤销回滚时使用 `min(previousIndex, profile.startupTabs.count)` 钳制目标下标，且若该 `tabID` 已被用户在管理器删除则安全忽略不报错。
