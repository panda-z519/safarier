import SwiftUI
import SafarierCore

/// 输入未通过校验时只留在草稿中，不把无效网址写入环境。
struct StartupTabDraft: Equatable, Identifiable {
    var id: UUID = UUID()
    var url: String = ""
    var isEnabled = true

    init(id: UUID = UUID(), url: String = "", isEnabled: Bool = true) {
        self.id = id
        self.url = url
        self.isEnabled = isEnabled
    }

    init(_ tab: StartupTab) {
        self.init(id: tab.id, url: tab.url.absoluteString, isEnabled: tab.isEnabled)
    }

    var webURL: URL? { AddressInput.webURL(for: url) }

    func validatedTab(at index: Int) throws -> StartupTab {
        guard let webURL else {
            throw ProfileEditorError.invalid(L10n.text("第 %lld 个启动页签的网址无效，请输入 http 或 https 网址，或删除该项。", index + 1))
        }
        return StartupTab(id: id, url: webURL, isEnabled: isEnabled)
    }
}

/// 新建和详情表单共用的启动页签列表。
struct StartupTabsSection: View {
    @Binding var tabs: [StartupTabDraft]
    @FocusState private var focusedTabID: UUID?

    var body: some View {
        Section {
            if tabs.isEmpty {
                Text("未配置启动页签，启动时显示起始页。")
                    .foregroundStyle(.secondary)
            }
            ForEach($tabs) { $tab in
                let index = tabs.firstIndex(where: { $0.id == tab.id }) ?? 0
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Toggle("启动时打开", isOn: $tab.isEnabled)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .help("取消勾选可暂停此页签的自动启动")
                            .accessibilityLabel(Text(L10n.text("启动时打开第 %lld 个页签", index + 1)))
                        TextField("网址", text: $tab.url, prompt: Text("https://example.com"))
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .focused($focusedTabID, equals: tab.id)
                            .accessibilityLabel(Text(L10n.text("第 %lld 个启动页签的网址", index + 1)))
                        Button { move(tab.id, by: -1) } label: {
                            Label("上移", systemImage: "arrow.up")
                        }
                        .help("上移")
                        .disabled(index == 0)
                        Button { move(tab.id, by: 1) } label: {
                            Label("下移", systemImage: "arrow.down")
                        }
                        .help("下移")
                        .disabled(index == tabs.count - 1)
                        Button(role: .destructive) { tabs.removeAll { $0.id == tab.id } } label: {
                            Label("删除页签", systemImage: "trash")
                        }
                        .help("删除页签")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    if !tab.url.isEmpty, tab.webURL == nil {
                        Text("请输入有效的 http 或 https 网址。")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            Button {
                let tab = StartupTabDraft()
                tabs.append(tab)
                focusedTabID = tab.id
            } label: {
                Label("添加网址", systemImage: "plus")
            }
        } header: {
            HStack {
                Text("启动页签")
                Spacer()
                Text(L10n.text("已启用 %lld / 共 %lld 个", tabs.filter(\.isEnabled).count, tabs.count))
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("启动时按顺序在同一窗口打开勾选的网址。取消勾选可暂停自动打开并保留网址；全部暂停时显示起始页。修改在下次启动环境时生效。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), tabs.indices.contains(index + offset) else { return }
        tabs.swapAt(index, index + offset)
    }
}
