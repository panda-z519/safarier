# Tasks

## 1. 核心仓储原子更新、网址整理与跨进程通知（SafarierCore）

- [x] 1.1 在 `Sources/SafarierCore/RecordRepository.swift` 新增 `mutate(id:_:)`，在既有 `NSLock` + `flock` 文件锁内完成重读、按 ID 修改、校验与原子保存，并在 `Tests/SafarierCoreTests/RecordRepositoryTests.swift` 补充单元测试验证：局部修改不覆盖外部新写入的其他字段、校验失败不写盘、目标 ID 不存在抛 `RepositoryError.notFound`（运行 `swift test --filter RecordRepositoryTests` 通过）
- [x] 1.2 在 `Sources/SafarierCore/AddressInput.swift` 新增纯函数 `removingQueryAndFragment(from:)`、`originOnly(from:)` 与 `isSameStartupURL(_:_:)`，并在 `Tests/SafarierCoreTests/AddressInputTests.swift` 覆盖带参数/锚点/端口/大小写域名/根路径斜杠等边界用例（运行 `swift test --filter AddressInputTests` 通过）
- [x] 1.3 在 `Sources/SafarierCore/ManagerLock.swift` 新增按工作目录隔离的跨进程配置变更通知定义 `ProfilesSyncNotification`（复用 `ManagerWakeup.workspaceScope(for:)`），并在 `Tests/SafarierCoreTests/ProfileLockTests.swift`（或相邻测试文件）验证通知名称与不同工作目录作用域互不冲突（运行 `swift test --filter ProfileLockTests` 通过）

## 2. 浏览器启动页签写入服务与原生 Safari 风格 Sheet（Safarier/Browser）

- [x] 2.1 在 `Sources/Safarier/Browser/BrowserSession.swift` 实现启动页签读写与撤销协调方法（读取当前环境最新 `startupTabs`、按末尾/首位插入或重新启用暂停项、锁内原子写入、按 `tabID` 精准撤销、同步会话 `⇧⌘H` 首页网址并广播 `ProfilesSyncNotification`），并编写单测验证末尾追加、设为首页、暂停项重新启用、撤销回滚、不覆盖管理器其他字段以及环境已删除时的报错处理（运行对应 `SafarierAppTests` 测试用例通过）
- [x] 2.2 新增原生 Safari 风格 Sheet 控制器（无标题栏紧凑 `NSPanel`，宽度约 `392pt`，采用 `window.beginSheet(_:)` 附着于工具栏正下方）：包含目标环境标题、原生「添加位置」`NSPopUpButton`（末尾 / 第 1 位设为首页）、自动全选的网址输入框、「去掉参数 / 仅保留域名 / 还原原网址」紧凑快捷按钮、实时校验与重复/暂停态单行提示、右下角「取消 (`Esc`) / 添加 (`↩`)」按钮，并编写单测验证输入校验、快捷裁剪状态切换、重复与暂停态文案/按钮变化及回车与 Esc 行为（运行对应 `SafarierAppTests` 测试用例通过）
- [x] 2.3 在 `Sources/Safarier/Browser/BrowserMenu.swift` 与 `Sources/Safarier/Browser/BrowserWindowController.swift` 挂载「文件 → 添加到启动页签… (`⌘D`)」菜单项、实现无窗口时禁用校验、防 Sheet 重复弹出保护、窗口底部自动淡出且带「撤销」按钮的轻提示条以及 `⇧⌘H` 实时读取同步后的首页网址，并补充菜单校验与窗口集成单测（运行对应 `SafarierAppTests` 测试用例通过）

## 3. 环境管理器实时刷新（Safarier/ManagerGUI）

- [x] 3.1 在 `Sources/Safarier/ManagerGUI/ManagerLauncher.swift`（或同步辅助入口）与 `Sources/Safarier/ManagerGUI/ManagerModel.swift` 接入 `ProfilesSyncNotification` 发送与订阅（按 `workspace.managerWakeupScope` 过滤，收到后在 `@MainActor` 调 `reload()` 并在释放时注销观察者），并补充单测验证：同工作目录收到通知自动刷新启动页签列表、不同工作目录通知被忽略、存在未保存草稿时 `ProfileEditorState` 仍保留草稿与外部变更冲突保护（运行对应 `SafarierAppTests` 测试用例通过）

## 4. 多语言本地化、文档更新与端到端验证

- [x] 4.1 补齐所有新增菜单项、Sheet 表单、快捷按钮、校验/重复提示、错误与撤销轻提示文案在 `Resources/en.lproj/Localizable.strings` 和 `Resources/ru.lproj/Localizable.strings` 的对应条目，并运行 `swift test --filter LocalizationCoverageTests` 确认中英表与占位符覆盖率 100% 通过
- [x] 4.2 更新 `docs/startup-tabs.md`、`README.zh-CN.md` 与 `README.md` 的快捷键速查表和启动页签操作说明，核对文档中快捷键与功能描述和实际实现一致
- [x] 4.3 运行全量测试 `swift test` 并在本地启动构建版本手工核验：浏览器按 `⌘D` 工具栏正下方居中弹出原生 Sheet → 编辑/去参数/选位置 → 确认后分屏中的环境管理器实时新增该启动页签 → 点击「撤销」实时回滚 → `⇧⌘H` 跳转符合预期
