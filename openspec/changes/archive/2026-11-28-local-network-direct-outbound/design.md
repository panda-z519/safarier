# Design

## Context

详见 `proposal.md` 与 `specs/local-network-direct-outbound/spec.md`。

当前 Safarier 支持 4 种环境出站形态：普通直连（不设 `WKWebsiteDataStore.proxyConfigurations`）、独立 SOCKS5/HTTP CONNECT 代理、订阅节点（经环境专属 `sing-box` 转本地 SOCKS5）、自定义单条 `sing-box` JSON 出站。普通直连在电脑开启系统代理或 Clash TUN（如 `utun1024` 接管默认网段与 DNS Fake-IP `198.18.0.0/15`）时，WebKit 流量与系统 DNS 会进入代理软件通道。此外，由于 macOS WebKit 网络进程名为系统共用的 `com.apple.WebKit.Networking`，也无法靠 Clash 进程规则精确区分“只放行某个 Safarier 窗口”。

## Goals / Non-Goals

**Goals:**
- 为单个环境的「直连」出站增加「强制使用本机网络」开关（`Profile.bypassSystemProxy`），无需管理员权限即可绕过 macOS 系统代理与 Clash / VPN 虚拟网卡（TUN），直接通过活跃物理网卡与真实本地 DNS 联网。
- 严格保证对宿主机（系统代理、路由表、系统 DNS、Clash 配置）及其他软件、Safarier 其他环境零影响。
- 严格遵循项目既有架构与规范：零 JS 注入、零私有 SPI、复用内置未修改的 `sing-box 1.14.4`、严格 Fail-Closed 断连阻断、配置文件 `0600` 权限与退出自动清理、详情页内联编辑与大白话多语言文案。

**Non-Goals:**
- 不提供手动选择网卡名或手动输入 DNS 的界面或 CLI 选项（保持零配置自动化）。
- 不支持在浏览器窗口运行期间动态热切换物理网卡（如从 Wi-Fi 拔插切换到有线网卡，按提示重启该环境生效）。
- 不修改上游 `sing-box` 源码或编译参数，不引入 `root` 权限或系统级网络扩展（Network Extension）。
- 不放开 `CustomOutbound` 对 `direct` 类型的禁用限制，保持「高级 JSON」仅用于单个远程代理出站。

## Decisions

### 1. 采用「本地 SOCKS5 + `sing-box` `direct` `bind_interface` + 同接口绑定 `udp` DNS」架构
- **方案选择**：当 `profile.bypassSystemProxy == true` 时，`RunnerMain` 为该环境单独拉起一个本地 `sing-box` 进程，配置：
  - `inbounds`：监听 `127.0.0.1:<随机空闲端口>` 的 `socks` 入站；
  - `outbounds`：单个 `direct` 出站，设置 `"bind_interface": "<物理网卡名>"` 与 `"domain_resolver": "local-direct-dns"`；
  - `dns`：`udp` 类型 DNS 服务器（标签 `local-direct-dns`），指向解析出的真实本地 DNS IP，并同样设置 `"bind_interface": "<物理网卡名>"`；
  - `route`：`"final": "direct"`。
  - `RunnerMain` 将 `127.0.0.1:<端口>` 组装为临时 `ProxySettings` 并经 `WebViewConfigurationFactory` 写入 `WKWebsiteDataStore.proxyConfigurations`（`allowFailover = false`）。
- **选择理由**：
  1. **跳过系统代理**：WebKit 一旦在 `WKWebsiteDataStore.proxyConfigurations` 中配置了本地 SOCKS5（且 `allowFailover = false`），就会忽略 macOS 系统代理并把域名完整交给本地 `sing-box` 解析，而不是在系统层面被代理截走；
  2. **跳过 TUN 路由表**：`sing-box` 在 Darwin/macOS 上对 `bind_interface` 底层调用 `IP_BOUND_IF` / `IPV6_BOUND_IF` 套接字选项，直接将 TCP/UDP 数据包锚定到物理网卡接口（如 `en0`），绕开 `utun` 路由表接管且无需管理员权限；
  3. **跳过 Clash Fake-IP**：若只绑出站流量、不绑 DNS，域名解析仍可能拿到 `198.18.x.x` 假 IP 导致直连彻底不可达；把 `udp` DNS 服务器也绑定到同一个 `bind_interface`，才能从本地路由器或上游真实 DNS 拿到公网真实 IP。
  4. **兼容性已实测**：项目内置 `sing-box 1.14.4` 已离线通过 `sing-box check` 校验。
- **替代方案与拒绝原因**：
  - *方案 B：让用户在 Clash 里按进程放行* → `com.apple.WebKit.Networking` 为系统 Safari 与所有环境共用进程名，无法按环境精确隔离，且强依赖用户外部配置。
  - *方案 C：放开 `CustomOutbound` 支持 `direct`* → 会破坏 `CustomOutbound` 仅允许远程代理出站的安全约束，且需要用户手写易失效的网卡名与 DNS JSON，不符合零配置易用目标。

### 2. 基于 `SystemConfiguration` 与可注入快照的物理网卡及 DNS 自动探测
- **方案选择**：在 `SafarierNetwork` 新增 `LocalNetworkInterfaceResolver`：
  - 实时读取层通过 `SystemConfiguration`（`SCDynamicStoreCreate`）采集 `State:/Network/Global/IPv4`、`State:/Network/Global/IPv6` 及各接口 `State:/Network/Interface/<ifname>/IPv4`、`State:/Network/Service/<serviceID>/DNS` 与 `IPv4` 信息；
  - 解析决策层做成纯函数/纯数据结构输入，方便对所有边界条件做确定性单元测试（无需依赖宿主机真实断网或双网卡）：
    1. **物理网卡过滤**：剔除 `utun`、`tun`、`tap`、`ppp`、`ipsec`、`lo`、`bridge`、`awdl`、`llw`、`gif`、`stf`、`ap`、`anpi` 等虚拟/回环/点对点接口；在剩余接口中优先匹配系统主服务（IPv4/IPv6 `PrimaryInterface`），否则选择具备有效非回环/非链路本地地址且活跃的物理接口（如 `en0`）。无匹配时抛出 `LocalNetworkDirectError.noPhysicalInterface`。
    2. **本地直连 DNS 筛选与回退顺序**：
       - 首先取所选物理网卡对应服务的 DHCP DNS，过滤掉非合法 IP、回环地址（`127.0.0.0/8`、`::1`）、未指定地址以及 Clash/代理常用的 Fake-IP 网段（`198.18.0.0/15`）与链路本地保留 DNS；
       - 若剩余为空，则取该物理网卡所在服务的路由器网关 IP（`Router`，路由器通常提供 DNS 转发）；
       - 若仍为空（如某些桥接/静态 IP 场景），回退至绑定同一 `bind_interface` 的公共直连 DNS（如 `223.5.5.5`、`119.29.29.29` / `1.1.1.1` 首选 IPv4 保证稳健直连）。
- **选择理由**：既能处理用户电脑运行 Clash TUN 时全局 DNS 被改成 `127.0.0.1` 或 `198.18.0.2` 的常见干扰，又能在各种纯 Swift 单测里覆盖全部异常场景。

### 3. 数据模型采用 `Profile.bypassSystemProxy: Bool = false`
- **方案选择**：在 `Profile` 中增加可编码布尔属性 `bypassSystemProxy`（默认 `false`），`init(from:)` 使用 `decodeIfPresent(..., forKey: .bypassSystemProxy) ?? false`；`validate()` 校验若 `bypassSystemProxy == true` 且 `proxyID != nil || subscriptionID != nil || nodeName != nil || customOutboundJSON != nil` 则抛出 `ProfileValidationError.conflictingOutbound`。
- **关键联动**：
  - `Profile.hasOutboundProxy` **保持不变**（仅当存在远程代理/节点/自定义 JSON 时为 `true`），因此开启「强制使用本机网络」的直连环境仍然保持与真 Safari 一致的默认 WebRTC 策略（不强制关闭 WebRTC），且区域/语言不能选「跟随代理」。
  - `ProfileEditorValues` 在 `outboundKind != .direct` 时自动将 `bypassSystemProxy` 置为 `false`，避免 UI 切换出站方式时产生冲突状态。
  - `ManagerModel.launchRunner` 中将 `profile.bypassSystemProxy` 纳入 `sing-box` 可执行文件前置检查范围，确保缺少 `sing-box` 时能给出与订阅节点一致的清晰提示。

### 4. UI 详情页内联编辑与方案一大白话文案
- **方案选择**：沿用用户确认的详情页内联编辑方案与“方案一”大白话文案：
  - 在 `ProfileEditorView` 的「网络」分组中，当 `outboundKind == .direct` 时展示 `Toggle("强制使用本机网络")` 及通俗说明；
  - 调整 `ProfileEditorView` 底部提示显示条件为 `if !inline || editor.values.outboundKind == .custom || (editor.values.outboundKind == .direct && editor.values.bypassSystemProxy)`，让用户在详情页内联开启该开关时也能直接看到 Fail-Closed 与切网重启提示；
  - `ProxyBinding` 新增 `.localDirect`，侧边栏 `ProfileRow` 显示「本机网络」（图标 `network` 或 `cable.connector` / `wifi` 等清晰区分于普通直连 `arrow.up.right`）；
  - `PrivacyReportPopover` 展示 Runner 传入的 `本机网络（<interface>）`，继续标明 Fail-Closed 保护状态。

## Risks / Trade-offs

- **运行中切换物理网络（如拔掉有线网切换至 Wi-Fi）** → 因启动时锁定了当时的物理网卡名，切换网络后旧接口失效会触发 Fail-Closed 断网；通过界面说明文案明确告知用户“切换 Wi-Fi 或网线后，重启本环境即可生效”。
- **企业内网 VPN 专用域名与内网 IP** → 开启「强制使用本机网络」后，环境主动绕过了所有 `utun*`/`ppp*` 虚拟网卡与 VPN DNS，企业 VPN 内部域名将无法解析（这正是用户“只使用本地网络、不使用任何代理/VPN”的预期行为；需要访问企业 VPN 资源时关闭该开关即可）。
- **DNS 服务器响应端口或类型假设** → 默认按标准 UDP 53 端口向本地路由器/DNS 发起解析；若个别极特殊局域网屏蔽普通 UDP 53 仅开放非标 DNS，本机直连同样依赖局域网路由器放行，可通过公共直连 DNS 回退覆盖物理网卡无网关 DNS 的情况，无需复杂 DoH/DoT 引导。

## Migration Plan

- `Profile` 新增字段默认值为 `false`，现有所有 `profiles.json` 无需任何数据迁移脚本即可无缝加载并保持原有直连行为。
- 功能通过环境变量/配置文件无侵入式启用，回滚只需将环境该开关关闭即可恢复系统默认直连。
