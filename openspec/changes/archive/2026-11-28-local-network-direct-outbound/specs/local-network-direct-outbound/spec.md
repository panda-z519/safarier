# local-network-direct-outbound Specification

## Purpose

定义单个 Safarier 环境在「直连」出站模式下启用「强制使用本机网络」时的完整行为契约，使该浏览器窗口绕过 macOS 系统代理、Clash 等代理软件的虚拟网卡（TUN）及假 IP DNS，直接经本机物理网卡与本地直连 DNS 出网，同时严格遵守 Fail-Closed、不修改宿主机网络配置，并确保对电脑上其他软件与 Safarier 其他环境零影响。

## ADDED Requirements

### Requirement: 环境配置支持本机网络直连标志并保持向后兼容与互斥校验
系统 MUST 在环境配置中提供可选的本机网络直连标志（默认关闭），兼容缺少该字段的历史配置，并在保存与校验阶段确保该标志与代理出站配置严格互斥。

#### Scenario: 读取历史环境配置文件时默认关闭本机网络直连
- **GIVEN** 一份由旧版本生成的 `profiles.json`，记录中不包含 `bypassSystemProxy` 字段
- **WHEN** 系统加载并解码该环境配置
- **THEN** 该环境的本机网络直连标志 SHALL 默认为 `false`，原有直连行为保持跟随系统网络，不产生任何破坏性变化

#### Scenario: 复制环境时完整保留本机网络直连配置
- **GIVEN** 源环境配置为直连且开启了「强制使用本机网络」（`bypassSystemProxy == true`）
- **WHEN** 用户执行复制环境操作
- **THEN** 新生成的环境副本 SHALL 保留 `bypassSystemProxy == true`，并使用全新的独立数据目录与环境 ID

#### Scenario: 与独立代理、订阅节点或自定义出站同时存在时校验失败
- **GIVEN** 某环境同时配置了 `bypassSystemProxy == true` 以及独立代理、订阅节点或自定义出站 JSON 中的任意一项
- **WHEN** 系统对该环境执行校验
- **THEN** 校验 SHALL 抛出冲突错误并阻止保存或启动该无效配置

#### Scenario: 开启本机网络直连不触发代理专用默认策略
- **GIVEN** 环境选择直连并开启「强制使用本机网络」
- **WHEN** 系统判断该环境是否配置了出站代理以及确定默认隐私能力与区域来源
- **THEN** 系统 SHALL 仍将其视作直连而非远程代理：不默认强制关闭 WebRTC，且语言与时区不允许设置为「跟随代理」

---

### Requirement: 自动识别活跃物理网卡与本地真实 DNS
在启动开启「强制使用本机网络」的环境时，系统 MUST 自动识别当前可用的物理网络接口及对应本地直连 DNS，过滤各类虚拟网卡与假 IP（Fake-IP）地址，且不要求用户手动填写网卡名或 DNS 地址。

#### Scenario: 电脑同时存在物理网卡与 Clash 虚拟网卡时优先选择活跃物理网卡
- **GIVEN** 宿主机当前同时存在活跃物理网卡 `en0` 与虚拟隧道网卡 `utun1024`（包括默认路由指向 `utun1024` 或存在多个 `utun*`/`ppp*`/`awdl*`/`bridge*`/`lo*` 接口）
- **WHEN** 系统为环境解析本地物理网络出口
- **THEN** 系统 SHALL 过滤所有非物理/虚拟接口并准确选出当前活跃的物理网卡（如 `en0`）

#### Scenario: 解析本地直连 DNS 时过滤回环与 Fake-IP 地址
- **GIVEN** 所选物理网卡下存在 DHCP 下发的 DNS 列表，其中混有 `198.18.0.2`（Fake-IP 段）或 `127.0.0.1` 等不可用于物理直连的 DNS 地址，或同时存在有效的路由器/本地 DNS（如 `192.168.31.1`）
- **WHEN** 系统确定直连 DNS 地址
- **THEN** 系统 SHALL 自动丢弃 `127.0.0.0/8`、`::1` 及 `198.18.0.0/15` 地址，优先选用该物理网卡剩余的有效 DHCP DNS；若无可用 DHCP DNS，则依次回退至该物理网卡关联的路由器网关 IP 或绑定同一物理网卡的直连公共 DNS

#### Scenario: 仅存在虚拟网卡且无可用物理网卡时拒绝启动
- **GIVEN** 宿主机物理网络已断开（例如 Wi-Fi 与有线网均未连接），系统中仅剩 `lo0` 与 `utun*` 虚拟接口
- **WHEN** 用户尝试启动开启「强制使用本机网络」的环境
- **THEN** 解析 SHALL 直接返回无可用物理网络接口的错误并中止启动，绝不选入虚拟网卡

---

### Requirement: 隔离本地通道生成、Fail-Closed 拦截与零宿主机影响
系统 MUST 为开启「强制使用本机网络」的环境生成独立配置并运行专属本地代理核心，将浏览器内核流量强制指向该本地通道并在物理网卡层直接出站；该过程 SHALL 不需要管理员权限、不修改宿主机任何网络状态，并在异常时严格 Fail-Closed 阻断，绝不静默回退到系统代理或虚拟网卡。

#### Scenario: 生成绑定物理网卡的 sing-box 直连配置并校验通过
- **GIVEN** 已解析出有效物理网卡名（如 `en0`）与非空本地直连 DNS 地址
- **WHEN** 系统构造该环境的 `sing-box` 运行配置
- **THEN** 配置 SHALL 包含仅监听 `127.0.0.1` 随机可用端口的 `socks` 入站、声明 `bind_interface` 为该物理网卡且绑定 `domain_resolver` 的 `direct` 出站，以及绑定同一 `bind_interface` 的 `udp` DNS 服务器；默认路由 `final` 指向 `direct` 出站，且完整配置能够通过内置 `sing-box check` 校验

#### Scenario: 严格隔离于宿主机系统代理、路由表与其他软件
- **GIVEN** 用户电脑正开启 Clash TUN 或系统代理，且同时运行系统 Safari、终端及其他配置了订阅节点的 Safarier 环境
- **WHEN** 启动并运行开启「强制使用本机网络」的 Safarier 环境
- **THEN** 当前环境的网页请求与域名解析 SHALL 经 `WKWebsiteDataStore.proxyConfigurations`（`allowFailover = false`）进入其专属本地 `sing-box` 并经物理网卡直接出网；宿主机系统代理、路由表、系统 DNS、Clash 配置，以及电脑上其他软件和 Safarier 其他环境的网络走向均 MUST 保持完全不变

#### Scenario: 本地通道失败或物理网卡不可用时绝不静默回退
- **GIVEN** 本地物理网卡不可用、内置 `sing-box` 缺失或启动失败，或在运行过程中该环境专属 `sing-box` 进程意外退出
- **WHEN** 环境启动或尝试加载网页
- **THEN** 启动阶段 SHALL 直接提示错误并中止启动；运行阶段网页加载 SHALL 立即失败，绝不静默退回宿主机系统代理或 Clash 虚拟网卡

#### Scenario: 配置权限保护与进程生命周期清理
- **GIVEN** 本机网络直连环境正在运行且生成了临时配置与 PID 文件
- **WHEN** 环境窗口正常关闭、收到终止信号，或下次启动时发现残留孤儿进程
- **THEN** 配置文件权限 MUST 为 `0600`，且专属 `sing-box` 子进程及其状态文件 SHALL 被完整清理，不遗留后台残留进程

---

### Requirement: 详情页内联编辑、界面展示与隐私报告同步
环境管理界面与浏览器界面 MUST 使用通俗易懂的中文交互文案（及对应多语言翻译），清晰区分「普通直连」与「强制使用本机网络」，并在缺少运行时依赖时给出明确提示。

#### Scenario: 在详情页内联编辑中切换「强制使用本机网络」开关
- **GIVEN** 用户在环境管理器详情页（或新建环境弹窗）中将出站方式选为「直连」
- **WHEN** 查看「网络」分组表单
- **THEN** 界面 SHALL 显示标题为「强制使用本机网络」的开关及清晰说明（解释即使电脑开着 Clash 等代理软件或 VPN，本窗口也直接走本地 Wi-Fi / 网线且不影响其他软件），且不提供手动网卡或 DNS 输入框

#### Scenario: 开启开关后展示断连与切换网络提示，切走其他出站后隐藏
- **GIVEN** 用户在详情页内联编辑中将「强制使用本机网络」开关打开
- **WHEN** 开关处于开启状态
- **THEN** 「网络」分组底部 SHALL 显示提示，说明连不上本地网络时将直接停止加载且不会偷偷切回代理软件，切换 Wi-Fi 或网线后需重启本环境生效
- **WHEN** 用户将出站切换为「独立代理」「订阅节点」或「高级 JSON」
- **THEN** 「强制使用本机网络」开关 SHALL 自动隐藏，保存时对应的 `bypassSystemProxy` 标志自动清除

#### Scenario: 侧边栏、浏览器隐私报告与探针输出清晰体现本机网络状态
- **GIVEN** 某环境配置了直连且开启「强制使用本机网络」，绑定物理网卡 `en0`
- **WHEN** 在环境管理器侧边栏查看该环境、点击「启动浏览器」并查看浏览器「隐私报告」弹窗，或运行 `safarier probe`
- **THEN** 侧边栏该环境行 SHALL 显示「本机网络」与专属标识图标；若启动时缺少 `sing-box` 可执行文件，管理器 SHALL 提前拦截并提示；浏览器「隐私报告」弹窗 SHALL 展示 `本机网络（en0）`；探针输出的 `outbound` 对象 SHALL 包含 `kind: "localDirect"`、`interface`、`dns`、`singboxPID` 与 `localProxy` 字段

---

### Requirement: 命令行管理与多语言本地化覆盖
命令行管理工具 MUST 支持创建、更新与展示本机网络直连配置，且所有新增用户可见文案 MUST 完成多语言覆盖并通过本地化覆盖率校验。

#### Scenario: 使用命令行创建或更新本机网络直连环境
- **GIVEN** 用户通过 `safarier profile create` 或 `safarier profile update` 管理环境
- **WHEN** 传入 `--bypass-system-proxy`（且未同时传入 `--proxy` 或 `--sub`/`--node`）
- **THEN** 环境 SHALL 保存为直连并开启 `bypassSystemProxy`，`safarier profile list` 在出站列显示 `direct(local)`；若同时传入 `--bypass-system-proxy` 与 `--proxy`/`--sub`/`--node`，或传入 `--no-bypass-system-proxy` 关闭该开关，系统 SHALL 按互斥规则拒绝冲突组合或准确更新状态

#### Scenario: 多语言翻译完整且全量测试零警告通过
- **GIVEN** 本次变更在源码中引入了新的中文 UI 文案与错误提示
- **WHEN** 同步更新 `Resources/en.lproj/Localizable.strings` 与 `Resources/ru.lproj/Localizable.strings` 并运行 `swift test`
- **THEN** 本地化覆盖率校验（`LocalizationCoverageTests`）及全部测试套件 SHALL 全部通过且编译无警告
