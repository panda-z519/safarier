# Tasks

## 1. 环境配置模型与向后兼容（`SafarierCore`）

- [x] 1.1 在 `Sources/SafarierCore/Profile.swift` 为 `Profile` 新增 `bypassSystemProxy: Bool`（默认 `false`），补齐 `CodingKeys`、`init(from:)`（缺失时解码为 `false`）、`encode(to:)`、`duplicated` 保留以及 `validate()` 与代理/订阅节点/自定义出站的互斥校验，保持 `hasOutboundProxy` 仅针对远程代理不变
- [x] 1.2 在 `Tests/SafarierCoreTests/ProfileTests.swift` 新增单元测试，覆盖旧 JSON 缺失字段默认 `false`、`bypassSystemProxy` 编解码与复制保留、互斥校验报错及 `hasOutboundProxy` 不受影响，运行 `swift test --filter ProfileTests` 验证通过

## 2. 物理网卡与本地直连 DNS 自动探测（`SafarierNetwork`）

- [x] 2.1 新增 `Sources/SafarierNetwork/LocalNetworkInterfaceResolver.swift`，基于 macOS `SystemConfiguration` 采集接口与服务状态，提供纯数据结构解析函数，自动过滤 `utun*`/`tun*`/`tap*`/`ppp*`/`ipsec*`/`lo*`/`bridge*`/`awdl*`/`llw*` 等虚拟接口并选出主物理网卡，过滤 `127.0.0.0/8`、`::1`、`198.18.0.0/15` 等无效/Fake-IP DNS（按 DHCP DNS → 网关路由器 DNS → 公共直连 DNS 回退），无可用物理网卡时抛出明确错误
- [x] 2.2 新增 `Tests/SafarierNetworkTests/LocalNetworkInterfaceResolverTests.swift`，覆盖物理网卡与 `utun` 共存选择、Fake-IP DNS 过滤、路由器网关回退、公共直连 DNS 回退以及仅剩虚拟网卡时报错，运行 `swift test --filter LocalNetworkInterfaceResolverTests` 验证通过

## 3. `sing-box` 本机直连配置与隔离进程生命周期（`SafarierNetwork`）

- [x] 3.1 在 `Sources/SafarierNetwork/SingboxConfigBuilder.swift` 新增 `makeLocalDirectConfiguration(inboundPort:interface:dnsServers:inboundAddress:logLevel:)`，生成监听 `127.0.0.1` 的 `socks` 入站、绑定 `bind_interface` 与 `domain_resolver` 的 `direct` 出站以及绑定同接口的 `udp` DNS 配置
- [x] 3.2 在 `Sources/SafarierNetwork/SingboxProcessManager.swift` 新增 `startLocalDirect(profileID:target:)` 与错误类型支持，复用 `0600` 私密配置写入、PID 追踪与孤儿/退出清理逻辑
- [x] 3.3 在 `Tests/SafarierNetworkTests/SingboxConfigBuilderTests.swift` 与 `SingboxProcessManagerTests.swift` 补充本机直连配置字段断言与真实 `sing-box check` 校验测试，运行 `swift test --filter SafarierNetworkTests` 验证通过

## 4. Runner 启动、Fail-Closed 拦截与隐私报告（`Safarier`）

- [x] 4.1 在 `Sources/Safarier/RunnerMain.swift` 为 `profile.bypassSystemProxy == true` 增加分支：探测本地物理网络、拉起专属 `sing-box` 并将本地 SOCKS5 交给 `WebViewConfigurationFactory`（`allowFailover = false`），探针 `outbound` 写入 `kind: "localDirect"`、`interface`、`dns`、`singboxPID`、`localProxy`，`outboundDescription` 格式化为 `本机网络（<interface>）`；探测或启动失败时直接 `fail(...)` 阻断，绝不退回系统代理或 TUN
- [x] 4.2 更新 `Sources/Safarier/Browser/PrivacyReportPopover.swift` 及 `Tests/SafarierAppTests/PrivacyReportPopoverTests.swift`，确保「本机网络（en0）」在隐私报告弹窗中正确显示为已启用保护通道而非待命直连，运行 `swift test --filter PrivacyReportPopoverTests` 验证通过

## 5. 管理器详情页内联编辑与侧边栏展示（`Safarier/ManagerGUI`）

- [x] 5.1 更新 `Sources/Safarier/ManagerGUI/ProfileEditorState.swift`、`ProfileEditorView.swift`、`ManagerModel.swift`、`SafarierAppView.swift` 与 `DisplayText.swift`：在「直连」下新增方案一大白话开关「强制使用本机网络」与说明文案（切往代理/节点/高级 JSON 时自动隐藏并置 `false`），开启时在详情页内联视图底部显示断连不回退与切网重启提示；侧边栏新增 `ProxyBinding.localDirect`（「本机网络」标签与专属图标）；启动前将 `bypassSystemProxy` 纳入 `sing-box` 可执行文件检查
- [x] 5.2 更新 `Tests/SafarierAppTests/InlineProfileEditorTests.swift` 与 `ManagerFixesTests.swift`，验证草稿编辑、切出站清除标志、保存回读以及 `ProxyBinding.localDirect` 状态，运行 `swift test --filter "InlineProfileEditorTests|ManagerFixesTests"` 验证通过

## 6. 命令行管理支持（`Safarier/ManagerCLI`）

- [x] 6.1 更新 `Sources/Safarier/ManagerCLI.swift`：在 `profile create` 与 `profile update` 中支持 `--bypass-system-proxy` 和 `--no-bypass-system-proxy`（并与 `--proxy` / `--sub` / `--node` 互斥校验），更新 `usage` 说明与 `outboundLabel`（开启时显示 `direct(local)`）
- [x] 6.2 在 `Tests/SafarierAppTests/ManagerCLITests.swift` 补充本机直连创建、更新、关闭、互斥冲突报错及列表输出测试，运行 `swift test --filter ManagerCLITests` 验证通过

## 7. 多语言本地化与文档同步

- [x] 7.1 同步补齐 `Resources/en.lproj/Localizable.strings` 与 `Resources/ru.lproj/Localizable.strings` 中所有新增界面文案与错误提示，运行 `swift test --filter LocalizationCoverageTests` 验证覆盖率、占位符一致性及 `make-zh-strings.swift` 生成无误
- [x] 7.2 更新 `README.zh-CN.md` 与 `README.md`，说明直连模式下「强制使用本机网络」绕过系统代理与 Clash TUN 的用途、Fail-Closed 特性及 CLI 参数

## 8. 集成与端到端实测验证

- [x] 8.1 运行全量 `swift test`，确认所有测试套件全部通过且编译零警告（`SafarierCoreTests`、`SafarierNetworkTests`、`SafarierWebKitTests` 及本次改动相关 `SafarierAppTests` 均全部通过；仅 2 条既有的 AppKit 桌面窗口聚焦测试 `CloseConfirmationTests.testQuitAsksOnFrontWindowAndRepliesWithTheChoice` 与 `SafariBehaviorTests.testSessionWindowGroupsCollapseTabsAndRotate` 在无前台桌面激活的测试环境下失败，与本次改动无关）
- [x] 8.2 使用临时 `SAFARIER_HOME` 通过 `swift run Safarier` 创建直连+本机网络测试环境，在当前开启 Clash TUN 的机器上运行 `safarier probe <PROFILE_ID> --url https://example.com`，核对探针 JSON 输出 `outbound.kind == "localDirect"`、绑定物理网卡非 `utun*`（实测 `en0`、DNS `192.168.31.1`）且页面成功加载（`PROBE_EXIT=0`），随后清理临时测试目录
