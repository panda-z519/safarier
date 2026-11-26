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
    struct DeletedTabSnapshot: Equatable {
        let tab: StartupTabDraft
        let index: Int
        let remainingIDs: [UUID]
    }

    @Binding var tabs: [StartupTabDraft]
    var showsAllValidationErrors = false

    @FocusState private var focusedTabID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var touchedIDs: Set<UUID> = []
    @State private var deletedSnapshot: DeletedTabSnapshot?
    @State private var undoDismissTask: Task<Void, Never>?

    var body: some View {
        let firstEnabledID = Self.firstEnabledID(in: tabs)
        let enabledCount = tabs.filter(\.isEnabled).count

        Section {
            if tabs.isEmpty {
                emptyStateView
            } else {
                ForEach($tabs) { $tab in
                    let index = tabs.firstIndex(where: { $0.id == tab.id }) ?? 0
                    let order = Self.enabledOrder(of: tab.id, in: tabs)
                    let isHome = tab.id == firstEnabledID
                    let showError = Self.shouldShowInlineError(
                        tab: tab,
                        focusedID: focusedTabID,
                        touchedIDs: touchedIDs,
                        showsAll: showsAllValidationErrors
                    )
                    StartupTabRow(
                        tab: $tab,
                        index: index,
                        totalCount: tabs.count,
                        enabledOrder: order,
                        isHome: isHome,
                        showsError: showError,
                        focusedTabID: $focusedTabID,
                        reduceMotion: reduceMotion,
                        onSubmit: { handleSubmit(for: tab.id) },
                        onMove: { offset in animateChange { Self.move(&tabs, id: tab.id, by: offset) } },
                        onMoveToTop: { animateChange { Self.moveToTop(&tabs, id: tab.id) } },
                        onReorderFrom: { draggedID in
                            animateChange { Self.reorder(&tabs, moving: draggedID, to: tab.id) }
                        },
                        onDelete: { deleteTab(tab.id) }
                    )
                }
                addFooterRow
            }
        } header: {
            HStack(spacing: 8) {
                Text("启动页签")
                Spacer()
                headerStatusBadge(enabledCount: enabledCount, totalCount: tabs.count)
            }
        } footer: {
            Text("启动时按顺序打开已启用的网址，第 1 个启用项同时作为主页（⇧⌘H）。修改在下次启动时生效。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: focusedTabID) { previous, _ in
            if let previous { touchedIDs.insert(previous) }
        }
        .onChange(of: tabs.map(\.id)) { _, currentIDs in
            let validIDs = Set(currentIDs)
            touchedIDs.formIntersection(validIDs)
            if let snapshot = deletedSnapshot, currentIDs != snapshot.remainingIDs {
                clearUndoSnapshot()
            }
        }
        .onDisappear {
            undoDismissTask?.cancel()
            undoDismissTask = nil
        }
    }

    // MARK: - 子视图

    @ViewBuilder
    private func headerStatusBadge(enabledCount: Int, totalCount: Int) -> some View {
        if totalCount == 0 {
            EmptyView()
        } else if enabledCount == 0 {
            Text(L10n.text("全部已暂停（共 %lld 个）", totalCount))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .foregroundStyle(.orange)
                .background(Capsule().fill(Color.orange.opacity(0.14)))
        } else {
            Text(L10n.text("%lld / %lld 已启用", enabledCount, totalCount))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .foregroundStyle(.secondary)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
                .accessibilityHidden(true)
            VStack(spacing: 3) {
                Text("未配置启动页签")
                    .font(.callout.weight(.medium))
                Text("启动时默认打开起始页，可按顺序添加多个常用网址。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                Button { addTab() } label: {
                    Label("添加启动页签", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if deletedSnapshot != nil {
                    Button("撤销删除") { undoDelete() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var addFooterRow: some View {
        HStack(spacing: 10) {
            Button { addTab() } label: {
                Label("添加启动页签", systemImage: "plus")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            if deletedSnapshot != nil {
                HStack(spacing: 6) {
                    Text("已删除 1 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("撤销") { undoDelete() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .transition(.opacity)
            } else {
                Text("按回车可连续添加")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 交互操作

    private func addTab() {
        let tab = StartupTabDraft()
        clearUndoSnapshot()
        animateChange { tabs.append(tab) }
        focusedTabID = tab.id
    }

    private func deleteTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let removed = tabs[index]
        animateChange {
            tabs.remove(at: index)
            deletedSnapshot = DeletedTabSnapshot(tab: removed, index: index, remainingIDs: tabs.map(\.id))
        }
        touchedIDs.remove(id)
        if focusedTabID == id { focusedTabID = nil }
        scheduleUndoDismiss()
    }

    private func undoDelete() {
        guard let snapshot = deletedSnapshot else { return }
        clearUndoSnapshot()
        var restored = false
        animateChange { restored = Self.restoreDeleted(&tabs, from: snapshot) }
        if restored, snapshot.tab.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            focusedTabID = snapshot.tab.id
        }
    }

    private func scheduleUndoDismiss() {
        undoDismissTask?.cancel()
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            animateChange { deletedSnapshot = nil }
        }
    }

    private func clearUndoSnapshot() {
        undoDismissTask?.cancel()
        undoDismissTask = nil
        deletedSnapshot = nil
    }

    private func handleSubmit(for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        touchedIDs.insert(id)
        if index < tabs.count - 1 {
            focusedTabID = tabs[index + 1].id
        } else if tabs[index].webURL != nil {
            addTab()
        } else {
            focusedTabID = nil
        }
    }

    private func animateChange(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.snappy(duration: 0.2), updates)
        }
    }

    // MARK: - 纯逻辑辅助（便于单元测试）

    static func firstEnabledID(in tabs: [StartupTabDraft]) -> UUID? {
        tabs.first(where: \.isEnabled)?.id
    }

    static func enabledOrder(of id: UUID, in tabs: [StartupTabDraft]) -> Int? {
        var order = 0
        for tab in tabs {
            if tab.isEnabled { order += 1 }
            if tab.id == id { return tab.isEnabled ? order : nil }
        }
        return nil
    }

    static func move(_ tabs: inout [StartupTabDraft], id: UUID, by offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == id }),
              tabs.indices.contains(index + offset) else { return }
        tabs.swapAt(index, index + offset)
    }

    static func moveToTop(_ tabs: inout [StartupTabDraft], id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        var item = tabs.remove(at: index)
        item.isEnabled = true
        tabs.insert(item, at: 0)
    }

    static func reorder(_ tabs: inout [StartupTabDraft], moving sourceID: UUID, to targetID: UUID) {
        guard sourceID != targetID,
              let fromIndex = tabs.firstIndex(where: { $0.id == sourceID }),
              let toIndex = tabs.firstIndex(where: { $0.id == targetID }) else { return }
        let item = tabs.remove(at: fromIndex)
        tabs.insert(item, at: toIndex)
    }

    /// 撤销删除：若该标识已重新存在（例如刚点击过还原），拒绝重复插入。
    @discardableResult
    static func restoreDeleted(_ tabs: inout [StartupTabDraft], from snapshot: DeletedTabSnapshot) -> Bool {
        guard !tabs.contains(where: { $0.id == snapshot.tab.id }) else { return false }
        let insertIndex = min(max(0, snapshot.index), tabs.count)
        tabs.insert(snapshot.tab, at: insertIndex)
        return true
    }

    /// 失焦后才提示非空无效输入；触发提交校验时同时标出空行与无效行。
    static func shouldShowInlineError(
        tab: StartupTabDraft,
        focusedID: UUID?,
        touchedIDs: Set<UUID>,
        showsAll: Bool
    ) -> Bool {
        guard tab.webURL == nil else { return false }
        if showsAll { return true }
        let trimmed = tab.url.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && focusedID != tab.id && touchedIDs.contains(tab.id)
    }
}

/// 单行启动页签：序号/主页标识 + 融入式网址输入 + 悬停排序/删除 + 迷你拨动开关。
private struct StartupTabRow: View {
    @Binding var tab: StartupTabDraft
    let index: Int
    let totalCount: Int
    let enabledOrder: Int?
    let isHome: Bool
    let showsError: Bool
    var focusedTabID: FocusState<UUID?>.Binding
    let reduceMotion: Bool
    let onSubmit: () -> Void
    let onMove: (Int) -> Void
    let onMoveToTop: () -> Void
    let onReorderFrom: (UUID) -> Void
    let onDelete: () -> Void

    private enum ControlFocus: Hashable {
        case moveUp
        case moveDown
        case delete
        case toggle
    }

    @State private var isHovered = false
    @State private var isDeleteHovered = false
    @State private var isDropTargeted = false
    @FocusState private var controlFocus: ControlFocus?

    private var isFocused: Bool { focusedTabID.wrappedValue == tab.id }
    private var showsActions: Bool { isHovered || isFocused || controlFocus != nil || isDropTargeted }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                leadingHandleAndBadge
                urlInputField
                hoverActionCluster
                Toggle("启动时打开", isOn: $tab.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .fixedSize()
                    .focused($controlFocus, equals: .toggle)
                    .help(tab.isEnabled
                        ? L10n.text("关闭开关可暂停此页签的自动启动")
                        : L10n.text("开启开关以恢复此页签的自动启动"))
                    .accessibilityLabel(Text(L10n.text("启动时打开第 %lld 个页签", index + 1)))
            }

            if showsError {
                Text(tab.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? L10n.text("请输入网址，或删除此空白行。")
                    : L10n.text("请输入有效的 http 或 https 网址。"))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, totalCount > 1 ? 46 : 30)
            }
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isDropTargeted ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if reduceMotion {
                isHovered = hovering
            } else {
                withAnimation(.easeInOut(duration: 0.14)) { isHovered = hovering }
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let draggedID = UUID(uuidString: raw), draggedID != tab.id else {
                return false
            }
            onReorderFrom(draggedID)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .contextMenu {
            Button("设为首个（主页）") { onMoveToTop() }
                .disabled(index == 0 && tab.isEnabled)
            Button("上移") { onMove(-1) }
                .disabled(index == 0)
            Button("下移") { onMove(1) }
                .disabled(index == totalCount - 1)
            Divider()
            Button(tab.isEnabled ? L10n.text("暂停此页签") : L10n.text("启用此页签")) {
                tab.isEnabled.toggle()
            }
            Button("删除页签", role: .destructive) { onDelete() }
        }
    }

    @ViewBuilder
    private var leadingHandleAndBadge: some View {
        let content = HStack(spacing: 6) {
            if totalCount > 1 {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 0.8 : 0.3)
                    .frame(width: 12)
                    .help("拖拽调整打开顺序")
                    .accessibilityHidden(true)
            }
            orderBadge
        }

        if totalCount > 1 {
            content.draggable(tab.id.uuidString)
        } else {
            content
        }
    }

    @ViewBuilder
    private var orderBadge: some View {
        if let enabledOrder {
            Text(verbatim: "\(enabledOrder)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isHome ? Color.accentColor : .secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHome ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.07))
                )
                .help(isHome
                    ? L10n.text("启动时自动聚焦，并作为主页（⇧⌘H）")
                    : L10n.text("启动打开顺序第 %lld 位", enabledOrder))
        } else {
            Image(systemName: "pause.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .opacity(0.75)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                )
                .help("已暂停，启动时跳过")
                .accessibilityHidden(true)
        }
    }

    private var urlInputField: some View {
        HStack(spacing: 6) {
            Image(systemName: showsError ? "exclamationmark.circle.fill" : "globe")
                .font(.system(size: 12))
                .foregroundStyle(showsError ? .red : .secondary)
                .opacity(!tab.isEnabled && !showsError ? 0.5 : 1)
                .accessibilityHidden(true)

            TextField("网址", text: $tab.url, prompt: Text("https://example.com"))
                .textFieldStyle(.plain)
                .labelsHidden()
                .autocorrectionDisabled()
                .focused(focusedTabID, equals: tab.id)
                .foregroundStyle(tab.isEnabled ? .primary : .secondary)
                .opacity(tab.isEnabled ? 1 : 0.78)
                .onSubmit(onSubmit)
                .accessibilityLabel(Text(L10n.text("第 %lld 个启动页签的网址", index + 1)))

            if isHome {
                Text("主页")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(Color.accentColor)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    .help("启动时自动聚焦，并作为主页（⇧⌘H）")
            } else if !tab.isEnabled {
                Text("已暂停")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.secondary)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(urlFieldBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(urlFieldBorder, lineWidth: 1)
        )
    }

    private var urlFieldBackground: Color {
        if showsError { return Color.red.opacity(0.05) }
        if isFocused { return Color.primary.opacity(0.04) }
        if isHovered { return Color.primary.opacity(0.03) }
        return .clear
    }

    private var urlFieldBorder: Color {
        if showsError { return Color.red.opacity(0.75) }
        if isFocused { return Color.accentColor.opacity(0.6) }
        return .clear
    }

    private var hoverActionCluster: some View {
        HStack(spacing: 5) {
            if totalCount > 1 {
                HStack(spacing: 0) {
                    Button { onMove(-1) } label: {
                        Label("上移", systemImage: "chevron.up")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .focused($controlFocus, equals: .moveUp)
                    .help("上移")
                    .disabled(index == 0)

                    Rectangle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 1, height: 12)

                    Button { onMove(1) } label: {
                        Label("下移", systemImage: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .focused($controlFocus, equals: .moveDown)
                    .help("下移")
                    .disabled(index == totalCount - 1)
                }
                .foregroundStyle(.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )

                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 1, height: 12)
            }

            Button(role: .destructive) { onDelete() } label: {
                Label("删除页签", systemImage: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isDeleteHovered ? .red : .secondary)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(isDeleteHovered ? Color.red.opacity(0.12) : .clear)
                    )
                    .contentShape(Rectangle())
            }
            .focused($controlFocus, equals: .delete)
            .help("删除页签")
            .onHover { isDeleteHovered = $0 }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .opacity(showsActions ? 1 : 0)
        .allowsHitTesting(showsActions)
    }
}
