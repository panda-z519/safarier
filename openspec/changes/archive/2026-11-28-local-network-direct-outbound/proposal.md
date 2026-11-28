# Proposal

## Why

用户本机开启 Clash 等代理软件的虚拟网卡（TUN）或系统代理时，Safarier 现有的「直连」模式仅清空 WebKit `proxyConfigurations`，网页连接与 DNS 查询仍会进入系统代理或 `utun` 虚拟网卡。为了让单个 Safarier 环境在无需管理员权限、且完全不修改宿主机系统代理、路由表、DNS 或 Clash 配置的前提下只走本机物理网络（Wi-Fi / 有线网）出网，需要为环境直连模式增加按环境隔离的「强制使用本机网络」能力。

## What Changes

- **环境配置模型与向后兼容（`SafarierCore`）**：在 `Profile` 中新增 `bypassSystemProxy: Bool`（默认 `false`），旧版 `profiles.json` 缺少该字段时按 `false` 解码，复制环境保留该配置；校验时该字段与独立代理（`proxyID`）、订阅节点（`subscriptionID`/`nodeName`）及自定义出站（`customOutboundJSON`）互斥，不改变 `hasOutboundProxy` 与直连模式默认的 WebRTC 行为。
- **物理网卡与本地直连 DNS 自动探测（`SafarierNetwork`）**：新增 `LocalNetworkInterfaceResolver`，基于 macOS `SystemConfiguration` 自动过滤虚拟/隧道接口（`utun*`、`tun*`、`tap*`、`ppp*`、`ipsec*`、`lo*`、`bridge*`、`awdl*`、`llw*` 等），识别当前主物理网卡（如 `en0`）以及该网卡可用的本地非假 IP（过滤 `127.0.0.0/8`、`::1`、`198.18.0.0/15`）DHCP DNS 或路由器网关 DNS，均不可用时回退至绑定同一物理网卡的直连公共 DNS；界面不暴露手动网卡或 DNS 输入框。
- **环境专属 `sing-box` 本机直连通道（`SafarierNetwork` 与 `RunnerMain`）**：复用内置未修改的 `sing-box 1.14.4`，新增本机直连配置构造与启动方法（本地 `127.0.0.1` SOCKS5 入站 + 绑定物理网卡的 `direct` 出站 + 绑定同一物理网卡的 `udp` DNS）；Runner 通过 `WKWebsiteDataStore.proxyConfigurations`（`allowFailover = false`）强制当前环境走该本地入站，跳过系统代理并以套接字级网卡绑定（`IP_BOUND_IF` / `IPV6_BOUND_IF`）绕过 Clash TUN；配置文件权限为 `0600`，进程退出、收到信号或孤儿回收时自动清理。探测不到可用物理网卡或 `sing-box` 异常时严格 Fail-Closed 中止启动，绝不静默退回系统代理或 TUN。
- **管理器详情页内联编辑与界面展示（`ManagerGUI`）**：采用详情页内联编辑体验（与新建环境弹窗共用 `ProfileEditorView`）及方案一通俗文案——出站选「直连」时显示「强制使用本机网络」开关及大白话说明，切往其他出站时自动隐藏并关闭；详情页内联开启该开关时，底部显示断连不回退代理软件及切换网络需重启的提示；侧边栏环境行显示「本机网络」标签与专属图标；浏览器「隐私报告」弹窗显示 `本机网络（<网卡名>）`；管理器启动前预先校验 `sing-box` 可执行文件。
- **命令行与探针（`ManagerCLI` 与 `ProbeController`）**：为 `profile create` / `profile update` 增加 `--bypass-system-proxy` 与 `--no-bypass-system-proxy`，与 `--proxy` / `--sub` / `--node` 互斥校验；`profile list` 对开启本机网络的直连环境输出 `direct(local)`；`safarier probe` 的 `outbound` 字段输出 `kind: "localDirect"`、`interface`、`dns`、`singboxPID` 与 `localProxy`。
- **多语言本地化、测试与文档**：补齐 `Resources/en.lproj/Localizable.strings` 与 `Resources/ru.lproj/Localizable.strings` 新增文案并通过 `LocalizationCoverageTests`，补充核心模型、网卡与 DNS 探测、`sing-box check`、Runner 启动与 GUI/CLI 测试，并更新 `README.zh-CN.md` 与 `README.md`。

## Capabilities

### New Capabilities
- `local-network-direct-outbound`: 单个 Safarier 环境在直连模式下强制使用本机物理网卡与本地直连 DNS 出网，跳过 macOS 系统代理与 Clash / VPN 虚拟网卡（TUN），同时保持严格 Fail-Closed 与对宿主机及其他软件的零影响隔离。

### Modified Capabilities
<!-- 本次变更不修改已有 `browser-startup-tab-shortcut` 与 `manager-window-lifecycle` 规范中的需求契约。 -->

## Impact

- **`SafarierCore`**：`Profile.swift`（新增字段、编解码、校验、复制与错误定义）。
- **`SafarierNetwork`**：新增 `LocalNetworkInterfaceResolver.swift`，扩展 `SingboxConfigBuilder.swift` 与 `SingboxProcessManager.swift`。
- **`Safarier`**：`RunnerMain.swift`、`PrivacyReportPopover.swift`、`ManagerModel.swift`、`ProfileEditorState.swift`、`ProfileEditorView.swift`、`SafarierAppView.swift`、`DisplayText.swift`、`ManagerCLI.swift`。
- **资源、测试与文档**：`Resources/en.lproj/Localizable.strings`、`Resources/ru.lproj/Localizable.strings`、`Tests/SafarierCoreTests/`、`Tests/SafarierNetworkTests/`、`Tests/SafarierAppTests/`、`README.zh-CN.md`、`README.md`。
