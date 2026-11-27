# Proposal

## Why

目前用户若想把正在浏览的网页加入当前环境的「启动页签」，必须手动复制网址、切回环境管理器、找到对应环境、点击添加启动页签、粘贴修改并保存，跨窗口来回切换不仅打断浏览节奏，在多开环境时还容易误改到其他环境。与此同时，浏览器窗口里的 `⌘D` 快捷键目前处于闲置状态，提供一个与原生 macOS Safari 按 `⌘D` 高度一致的窗口顶部下拉确认表单，即可原地完成网址确认、微调并安全同步到环境管理器。

## What Changes

- **浏览器菜单与 `⌘D` 快捷键入口**：在浏览器顶部「文件」菜单中新增「添加到启动页签…」（快捷键 `⌘D`），绑定当前环境；菜单项仅在有效浏览窗口处于焦点时可用。
- **原生 Safari 风格下拉确认表单（Sheet）**：按下 `⌘D` 后从浏览器工具栏正下方居中滑出紧凑模态 Sheet（`window.beginSheet(_:)`），包含：
  - 明确标注目标环境名称；
  - 「添加位置」下拉选择器（`NSPopUpButton`）：默认「启动页签末尾（作为第 N 项）」，可选「第 1 位 · 设为首页（同步作为 `⇧⌘H`）」；
  - 自动预填当前页有效 `http`/`https` 网址并自动全选的输入框（空白起始页或历史记录页默认留空并允许手动输入），复用 `AddressInput.webURL(for:)` 校验与自动协议补全；
  - 紧凑快捷整理按钮：「去掉参数」（清除 query/fragment）与「仅保留域名」（只留 scheme + host + 端口），修改后可一键「还原原网址」；
  - 重复与暂停态智能识别：实时比对当前环境最新启动页签，已在启用列表时提示并允许「仍要添加」，已存在但处于暂停状态时提示并将主按钮切换为「重新启用」；
  - 标准 macOS 按钮与键盘操作：右下角「取消」（`Esc`）与默认主按钮「添加」（`↩`），输入无效或为空时禁用主按钮。
- **跨进程锁内原子写入与管理器实时刷新**：
  - 在 `RecordRepository` 既有 `flock` 文件锁内新增按 ID 原子更新方法，读取最新 `profiles.json` 后仅修改目标环境的 `startupTabs` 字段并校验落盘，避免覆盖用户在管理器中修改的其他配置项；
  - 写入成功后通过 `DistributedNotificationCenter` 发送按工作目录隔离的变更通知，运行中的环境管理器收到后立即调用 `reload()` 刷新启动页签列表（若用户正在编辑该环境且有未保存草稿，维持既有 `ProfileEditorState` 冲突保护不覆写草稿）；
  - 添加成功后在浏览器底部展示自动消失的轻提示（含「撤销」快捷操作，可原子回滚本次添加/重新启用）；若本次写入改变了当前环境的首页（首位启用项），顺带同步当前浏览器会话的 `⇧⌘H` 起始网址，不改动当前已打开的标签页。
- **多语言本地化与文档同步**：补齐新增菜单、弹窗、提示与错误文案的简体中文 / 英文（`en.lproj`）/ 俄文（`ru.lproj`）本地化条目，并更新 `README.zh-CN.md` / `README.md` 快捷键速查与 `docs/startup-tabs.md` 说明。

## Capabilities

### New Capabilities
- `browser-startup-tab-shortcut`: 浏览器窗口内通过 `⌘D` 唤出原生 Safari 风格 Sheet 确认弹窗，编辑/整理网址并选择位置，原子写入当前环境的启动页签配置且实时同步至环境管理器。

### Modified Capabilities
<!-- 本次变更不修改已有 `manager-window-lifecycle` 规范中的需求契约。 -->

## Impact

- **核心层（`SafarierCore`）**：`RecordRepository` 新增锁内按 ID 原子更新接口；`ManagerLock.swift`（或同目录）新增跨进程配置变更通知定义（复用 `ManagerWakeup.workspaceScope` 隔离规则）；`AddressInput` 可补充纯函数式的 URL 裁剪辅助方法（去参数、仅保留域名）供 UI 与单测共用。
- **浏览器层（`Safarier/Browser`）**：`BrowserMenu.swift`、`BrowserWindowController.swift`、`BrowserSession.swift`，以及新增/扩展原生 Sheet 控制器与底部撤销轻提示视图。
- **管理器层（`Safarier/ManagerGUI`）**：`ManagerLauncher.swift`（或跨进程通知发送端）与 `ManagerModel.swift` / `ManagerApp.swift` 监听同工作目录配置变更通知并触发 `reload()`。
- **资源、测试与文档**：`Resources/en.lproj/Localizable.strings`、`Resources/ru.lproj/Localizable.strings`、`Tests/SafarierCoreTests/`、`Tests/SafarierAppTests/`、`docs/startup-tabs.md`、`README.zh-CN.md`、`README.md`。
