import SwiftUI

struct WorkspaceCenterPopover: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onClose: () -> Void

    @State private var query = ""
    @State private var draft: WorkspaceDraft?
    @State private var dragState: WorkspacePopoverDragState?
    @State private var rowFrames: [UUID: CGRect] = [:]

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedWorkspaces: [Workspace] {
        model.orderedWorkspaces.filter { workspace in
            workspace.id != model.defaultWorkspaceID &&
                (normalizedQuery.isEmpty || workspace.name.localizedCaseInsensitiveContains(normalizedQuery))
        }
    }

    private var canReorder: Bool {
        normalizedQuery.isEmpty && model.database.workspaceSortMode == .manual && draft == nil
    }

    private var preferredHeight: CGFloat {
        let rowCount = 1 + displayedWorkspaces.count + (draft == nil ? 0 : 1)
        return min(570, max(380, 245 + CGFloat(rowCount * 50)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            SearchField(text: $query, placeholder: "搜索工作区")
                .disabled(draft != nil)

            HStack(spacing: 8) {
                Label("排序", systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)
                Spacer()
                Picker("排序", selection: Binding(
                    get: { model.database.workspaceSortMode },
                    set: { model.setWorkspaceSortMode($0) }
                )) {
                    ForEach(WorkspaceSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .disabled(draft != nil)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if let draft, draft.workspaceID == nil {
                        WorkspaceInlineEditor(
                            draft: Binding(
                                get: { self.draft ?? WorkspaceDraft.new() },
                                set: { self.draft = $0 }
                            ),
                            modeTitle: "新建工作区",
                            onSave: saveDraft,
                            onCancel: cancelDraft
                        )
                        .padding(.bottom, 8)
                    }

                    WorkspacePopoverSectionLabel(title: "默认工作区")
                    workspaceContent(model.defaultWorkspace, isDefault: true)

                    WorkspacePopoverSectionLabel(title: "其他工作区")
                        .padding(.top, 9)

                    if displayedWorkspaces.isEmpty {
                        VStack(spacing: 7) {
                            Image(systemName: normalizedQuery.isEmpty ? "square.stack.3d.up.slash" : "magnifyingglass")
                                .font(.system(size: 21))
                            Text(normalizedQuery.isEmpty ? "还没有其他工作区" : "没有匹配的工作区")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(ModernPalette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                    } else {
                        ForEach(displayedWorkspaces) { workspace in
                            workspaceContent(workspace, isDefault: false)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()
            HStack(spacing: 7) {
                Image(systemName: canReorder ? "line.3.horizontal" : "star.fill")
                    .foregroundStyle(ModernPalette.muted)
                Text(canReorder
                     ? "拖动手柄调整手动顺序"
                     : "星标项会在下次启动时自动打开")
                    .font(.system(size: 10))
                    .foregroundStyle(ModernPalette.muted)
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 410, height: preferredHeight)
        .coordinateSpace(.named("workspace-center"))
        .onPreferenceChange(WorkspacePopoverRowFramesKey.self) { frames in
            if frames != rowFrames { rowFrames = frames }
        }
        .onChange(of: model.workspaceRevision) { _, _ in dragState = nil }
        .onChange(of: query) { _, _ in dragState = nil }
        .onDisappear {
            draft = nil
            dragState = nil
        }
        .overlay {
            GeometryReader { proxy in
                if let dragState {
                    WorkspacePopoverDragPreview(title: dragState.title)
                        .position(
                            x: min(max(dragState.location.x + 72, 108), max(108, proxy.size.width - 108)),
                            y: min(max(dragState.location.y, 24), max(24, proxy.size.height - 24))
                        )
                        .allowsHitTesting(false)
                        .zIndex(20)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("工作区")
                    .font(.system(size: 17, weight: .semibold))
                Text("切换、整理或创建工作环境")
                    .font(.system(size: 11))
                    .foregroundStyle(ModernPalette.muted)
            }
            Spacer()
            Button {
                beginCreation()
            } label: {
                Label("新建", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(draft != nil)
            .accessibilityHint("在此弹窗中创建工作区")
        }
    }

    @ViewBuilder
    private func workspaceContent(_ workspace: Workspace, isDefault: Bool) -> some View {
        if let draft, draft.workspaceID == workspace.id {
            WorkspaceInlineEditor(
                draft: Binding(
                    get: { self.draft ?? WorkspaceDraft(workspace: workspace) },
                    set: { self.draft = $0 }
                ),
                modeTitle: "编辑工作区",
                onSave: saveDraft,
                onCancel: cancelDraft
            )
        } else {
            WorkspaceCenterRow(
                workspace: workspace,
                isDefault: isDefault,
                isSelected: model.selection.selectedWorkspaceID == workspace.id,
                canDelete: model.database.workspaces.count > 1,
                canReorder: canReorder && !isDefault,
                isBeingDragged: dragState?.sourceID == workspace.id,
                isDropTargeted: dragState?.beforeID == workspace.id,
                isEndDropTargeted: dragState != nil && dragState?.beforeID == nil && workspace.id == displayedWorkspaces.last?.id,
                onSelect: {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                        model.selectWorkspace(workspace.id)
                    }
                    onClose()
                },
                onMakeDefault: { model.setDefaultWorkspace(workspace.id) },
                onEdit: { beginEditing(workspace) },
                onDelete: {
                    model.requestDeleteWorkspace(workspace)
                    onClose()
                },
                onDragChanged: { location in updateDrag(workspace, location: location) },
                onDragEnded: { location in finishDrag(workspace, location: location) },
                onMoveUp: { moveUp(workspace.id) },
                onMoveDown: { moveDown(workspace.id) }
            )
        }
    }

    private func beginCreation() {
        query = ""
        draft = .new()
    }

    private func beginEditing(_ workspace: Workspace) {
        query = ""
        draft = WorkspaceDraft(workspace: workspace)
    }

    private func cancelDraft() {
        draft = nil
    }

    private func saveDraft() {
        guard let draft else { return }
        let cleanName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        if let workspaceID = draft.workspaceID {
            model.updateWorkspace(
                workspaceID,
                name: cleanName,
                symbolName: draft.symbolName,
                colorHex: draft.colorHex
            )
        } else {
            model.addWorkspace(name: cleanName, symbolName: draft.symbolName, colorHex: draft.colorHex)
        }
        self.draft = nil
    }

    private func updateDrag(_ workspace: Workspace, location: CGPoint) {
        guard canReorder else { return }
        dragState = WorkspacePopoverDragState(
            sourceID: workspace.id,
            title: workspace.name,
            location: location,
            beforeID: workspaceBeforeID(at: location, moving: workspace.id)
        )
    }

    private func finishDrag(_ workspace: Workspace, location: CGPoint) {
        guard canReorder else { return }
        let beforeID = workspaceBeforeID(at: location, moving: workspace.id)
        dragState = nil
        guard beforeID != workspace.id else { return }
        model.moveWorkspace(workspace.id, before: beforeID)
    }

    private func workspaceBeforeID(at location: CGPoint, moving sourceID: UUID) -> UUID? {
        for workspace in displayedWorkspaces where workspace.id != sourceID {
            guard let frame = rowFrames[workspace.id] else { continue }
            if location.y < frame.midY { return workspace.id }
        }
        return nil
    }

    private func moveUp(_ id: UUID) {
        guard canReorder,
              let index = displayedWorkspaces.firstIndex(where: { $0.id == id }),
              index > 0 else { return }
        model.moveWorkspace(id, before: displayedWorkspaces[index - 1].id)
    }

    private func moveDown(_ id: UUID) {
        guard canReorder,
              let index = displayedWorkspaces.firstIndex(where: { $0.id == id }),
              index < displayedWorkspaces.count - 1 else { return }
        let beforeID = index + 2 < displayedWorkspaces.count ? displayedWorkspaces[index + 2].id : nil
        model.moveWorkspace(id, before: beforeID)
    }
}

private struct WorkspaceDraft: Equatable {
    let workspaceID: UUID?
    var name: String
    var symbolName: String
    var colorHex: String

    init(workspace: Workspace) {
        workspaceID = workspace.id
        name = workspace.name
        symbolName = workspace.symbolName
        colorHex = workspace.colorHex
    }

    static func new() -> WorkspaceDraft {
        WorkspaceDraft(workspaceID: nil, name: "", symbolName: "square.grid.2x2", colorHex: "#0A84FF")
    }

    private init(workspaceID: UUID?, name: String, symbolName: String, colorHex: String) {
        self.workspaceID = workspaceID
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
    }
}

private struct WorkspaceInlineEditor: View {
    @Binding var draft: WorkspaceDraft
    let modeTitle: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @State private var showIconPicker = false
    @FocusState private var nameFocused: Bool

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(modeTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ModernPalette.muted)

            HStack(spacing: 8) {
                Button {
                    showIconPicker = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: draft.symbolName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: draft.colorHex))
                            .frame(width: 28, height: 28)
                            .background(Color(hex: draft.colorHex).opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(ModernPalette.muted)
                    }
                }
                .buttonStyle(.plain)
                .help("选择图标和颜色")
                .accessibilityLabel("工作区图标与颜色")
                .popover(isPresented: $showIconPicker, arrowEdge: .leading) {
                    WorkspaceIconPicker(symbolName: $draft.symbolName, colorHex: $draft.colorHex)
                }

                TextField("工作区名称", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .focused($nameFocused)
                    .onSubmit { if canSave { onSave() } }
                    .onExitCommand(perform: onCancel)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.muted)
                .accessibilityLabel("取消")

                Button(action: onSave) {
                    Image(systemName: "checkmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSave ? ModernPalette.blue : ModernPalette.muted.opacity(0.45))
                .disabled(!canSave)
                .accessibilityLabel("保存")
            }
        }
        .padding(10)
        .background(ModernPalette.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ModernPalette.blue.opacity(0.34), lineWidth: 1)
        }
        .task {
            await Task.yield()
            nameFocused = true
        }
    }
}

private struct WorkspaceCenterRow: View {
    let workspace: Workspace
    let isDefault: Bool
    let isSelected: Bool
    let canDelete: Bool
    let canReorder: Bool
    let isBeingDragged: Bool
    let isDropTargeted: Bool
    let isEndDropTargeted: Bool
    let onSelect: () -> Void
    let onMakeDefault: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: (CGPoint) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            if canReorder {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted.opacity(0.76))
                    .frame(width: 20, height: 34)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .named("workspace-center"))
                            .onChanged { onDragChanged($0.location) }
                            .onEnded { onDragEnded($0.location) }
                    )
                    .help("拖动调整顺序")
                    .accessibilityLabel("调整“\(workspace.name)”的顺序")
                    .accessibilityAction(named: "上移", onMoveUp)
                    .accessibilityAction(named: "下移", onMoveDown)
            } else {
                Color.clear.frame(width: 20, height: 34)
            }

            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Image(systemName: workspace.symbolName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(hex: workspace.colorHex))
                        .frame(width: 28, height: 28)
                        .background(Color(hex: workspace.colorHex).opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ModernPalette.ink)
                            .lineLimit(1)
                        Text(isDefault ? "启动时打开" : "切换到此工作区")
                            .font(.system(size: 10))
                            .foregroundStyle(ModernPalette.muted)
                    }
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(ModernPalette.blue)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onMakeDefault) {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isDefault ? ModernPalette.blue : ModernPalette.muted)
                    .frame(width: 25, height: 25)
            }
            .buttonStyle(.plain)
            .disabled(isDefault)
            .help(isDefault ? "默认工作区" : "设为默认工作区")
            .accessibilityLabel(isDefault ? "默认工作区" : "设为默认工作区")

            Menu {
                Button("编辑", systemImage: "pencil", action: onEdit)
                if canReorder {
                    Button("上移", systemImage: "arrow.up", action: onMoveUp)
                    Button("下移", systemImage: "arrow.down", action: onMoveDown)
                }
                Divider()
                Button("删除工作区", systemImage: "trash", role: .destructive, action: onDelete)
                    .disabled(!canDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(width: 25, height: 25)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("更多操作")
            .accessibilityLabel("“\(workspace.name)”的更多操作")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .opacity(isBeingDragged ? 0.34 : 1)
        .background(isSelected ? ModernPalette.blue.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .top) {
            if isDropTargeted {
                Capsule().fill(ModernPalette.blue).frame(height: 2).padding(.horizontal, 5)
            }
        }
        .overlay(alignment: .bottom) {
            if isEndDropTargeted {
                Capsule().fill(ModernPalette.blue).frame(height: 2).padding(.horizontal, 5)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: WorkspacePopoverRowFramesKey.self,
                    value: [workspace.id: proxy.frame(in: .named("workspace-center"))]
                )
            }
        }
    }
}

private struct WorkspacePopoverSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(ModernPalette.muted)
            .textCase(.uppercase)
            .padding(.horizontal, 5)
            .padding(.bottom, 2)
    }
}

private struct WorkspacePopoverDragState: Equatable {
    let sourceID: UUID
    let title: String
    let location: CGPoint
    let beforeID: UUID?
}

private struct WorkspacePopoverRowFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct WorkspacePopoverDragPreview: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(ModernPalette.muted)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .frame(width: 210, height: 36)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
    }
}

private struct WorkspaceIconPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var symbolName: String
    @Binding var colorHex: String
    @AppStorage("workspace.recent-symbols") private var recentSymbolsStorage = ""
    @State private var query = ""
    @State private var category: WorkspaceIconCategory = .common
    @State private var keyboardSymbol: String?
    @FocusState private var gridFocused: Bool

    private let columns = Array(repeating: GridItem(.fixed(36), spacing: 7), count: 7)
    private let colors = ["#0A84FF", "#5E5CE6", "#AF52DE", "#FF2D55", "#FF9500", "#34C759", "#00A59A", "#8E8E93"]

    private var recentSymbols: [String] {
        recentSymbolsStorage.split(separator: ",").map(String.init)
    }

    private var filteredIcons: [WorkspaceIconOption] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            return WorkspaceIconCatalog.options.filter { option in
                option.symbol.localizedCaseInsensitiveContains(needle) ||
                    option.label.localizedCaseInsensitiveContains(needle) ||
                    option.keywords.contains { $0.localizedCaseInsensitiveContains(needle) }
            }
        }
        switch category {
        case .common:
            return WorkspaceIconCatalog.options.filter(\.isCommon)
        case .recent:
            return recentSymbols.compactMap { symbol in
                WorkspaceIconCatalog.options.first(where: { $0.symbol == symbol })
            }
        default:
            return WorkspaceIconCatalog.options.filter { $0.category == category }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("选择图标")
                .font(.system(size: 15, weight: .semibold))

            SearchField(text: $query, placeholder: "搜索图标名称")

            HStack(spacing: 5) {
                ForEach(WorkspaceIconCategory.allCases) { item in
                    Button(item.title) {
                        category = item
                        Task { @MainActor in
                            await Task.yield()
                            gridFocused = true
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(category == item ? ModernPalette.blue : ModernPalette.muted)
                    .padding(.horizontal, 7)
                    .frame(height: 25)
                    .background(
                        category == item ? ModernPalette.blue.opacity(0.11) : ModernPalette.subtle,
                        in: Capsule()
                    )
                    .accessibilityAddTraits(category == item ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if filteredIcons.isEmpty {
                    VStack(spacing: 5) {
                        Image(systemName: "magnifyingglass")
                        Text(category == .recent && query.isEmpty ? "选择过的图标会显示在这里" : "没有匹配的图标")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(ModernPalette.muted)
                    .frame(maxWidth: .infinity, minHeight: 83)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical) {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 7) {
                                ForEach(filteredIcons) { option in
                                    iconButton(option)
                                        .id(option.symbol)
                                }
                            }
                            .padding(.leading, 8)
                            .padding(.trailing, 14)
                            .padding(.vertical, 8)
                        }
                        .frame(height: 95)
                        .scrollIndicators(.automatic)
                        .focusable()
                        .focusEffectDisabled()
                        .focused($gridFocused)
                        .onKeyPress(.leftArrow) { moveKeyboardSelection(by: -1, proxy: proxy) }
                        .onKeyPress(.rightArrow) { moveKeyboardSelection(by: 1, proxy: proxy) }
                        .onKeyPress(.upArrow) { moveKeyboardSelection(by: -7, proxy: proxy) }
                        .onKeyPress(.downArrow) { moveKeyboardSelection(by: 7, proxy: proxy) }
                        .onKeyPress(.return) { selectKeyboardSymbol() }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("颜色")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted)
                    .textCase(.uppercase)

                HStack(spacing: 9) {
                    ForEach(colors, id: \.self) { color in
                        Button {
                            colorHex = color
                        } label: {
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if colorHex == color {
                                        Circle()
                                            .strokeBorder(.white, lineWidth: 2)
                                            .padding(2)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("颜色 \(color)")
                        .accessibilityAddTraits(colorHex == color ? .isSelected : [])
                    }
                }
            }
        }
        .padding(15)
        .frame(width: 346)
        .onAppear {
            synchronizeKeyboardSelection()
            Task { @MainActor in
                await Task.yield()
                gridFocused = true
            }
        }
        .onChange(of: query) { _, _ in synchronizeKeyboardSelection() }
        .onChange(of: category) { _, _ in synchronizeKeyboardSelection() }
        .onExitCommand { dismiss() }
    }

    private func iconButton(_ option: WorkspaceIconOption) -> some View {
        let selected = symbolName == option.symbol
        let keyboardSelected = keyboardSymbol == option.symbol && gridFocused
        let ringColor = keyboardSelected ? ModernPalette.blue : Color(hex: colorHex)
        return Button {
            choose(option.symbol)
        } label: {
            Image(systemName: option.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(selected ? Color(hex: colorHex) : ModernPalette.ink)
                .frame(width: 36, height: 36)
                .background(selected ? Color(hex: colorHex).opacity(0.13) : ModernPalette.subtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    if selected || keyboardSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(ringColor, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(option.label)
        .accessibilityLabel(option.label)
        .accessibilityValue(selected ? "已选择" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func synchronizeKeyboardSelection() {
        let icons = filteredIcons
        if icons.contains(where: { $0.symbol == symbolName }) {
            keyboardSymbol = symbolName
        } else {
            keyboardSymbol = icons.first?.symbol
        }
    }

    private func moveKeyboardSelection(by offset: Int, proxy: ScrollViewProxy) -> KeyPress.Result {
        let icons = filteredIcons
        guard !icons.isEmpty else { return .ignored }
        let currentIndex = keyboardSymbol.flatMap { symbol in icons.firstIndex(where: { $0.symbol == symbol }) } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), icons.count - 1)
        keyboardSymbol = icons[nextIndex].symbol
        proxy.scrollTo(icons[nextIndex].symbol, anchor: .center)
        return .handled
    }

    private func selectKeyboardSymbol() -> KeyPress.Result {
        guard let keyboardSymbol else { return .ignored }
        choose(keyboardSymbol)
        return .handled
    }

    private func choose(_ symbol: String) {
        symbolName = symbol
        keyboardSymbol = symbol
        var recent = recentSymbols.filter { $0 != symbol }
        recent.insert(symbol, at: 0)
        recentSymbolsStorage = recent.prefix(14).joined(separator: ",")
    }
}

private enum WorkspaceIconCategory: String, CaseIterable, Identifiable {
    case common
    case recent
    case work
    case life
    case learning
    case creative
    case health
    case travel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .common: "常用"
        case .recent: "最近"
        case .work: "工作"
        case .life: "生活"
        case .learning: "学习"
        case .creative: "创作"
        case .health: "健康"
        case .travel: "出行"
        }
    }
}

private struct WorkspaceIconOption: Identifiable {
    let symbol: String
    let label: String
    let category: WorkspaceIconCategory
    let isCommon: Bool
    let keywords: [String]

    var id: String { symbol }
}

private enum WorkspaceIconCatalog {
    static let options: [WorkspaceIconOption] = [
        icon("square.grid.2x2", "工作区", .work, true, "总览", "面板"),
        icon("briefcase", "工作", .work, true, "职业", "办公"),
        icon("folder", "项目", .work, true, "文件夹", "资料"),
        icon("building.2", "公司", .work, true, "组织", "企业"),
        icon("person.2", "团队", .work, true, "协作", "伙伴"),
        icon("chart.bar", "业务", .work, true, "统计", "数据"),
        icon("target", "目标", .work, true, "结果", "计划"),
        icon("calendar", "日程", .work, true, "日期", "安排"),
        icon("house", "家庭", .life, true, "家", "住所"),
        icon("heart", "生活", .life, true, "喜欢", "关爱"),
        icon("cart", "购物", .life, false, "采购", "清单"),
        icon("fork.knife", "饮食", .life, false, "餐饮", "做饭"),
        icon("leaf", "自然", .life, false, "植物", "环保"),
        icon("pawprint", "宠物", .life, false, "动物"),
        icon("gift", "礼物", .life, false, "节日", "赠送"),
        icon("graduationcap", "学习", .learning, true, "学校", "课程"),
        icon("book.closed", "阅读", .learning, true, "书籍", "知识"),
        icon("text.book.closed", "笔记", .learning, false, "文档", "记录"),
        icon("brain.head.profile", "思考", .learning, false, "研究", "知识"),
        icon("function", "数学", .learning, false, "公式", "计算"),
        icon("globe", "语言", .learning, false, "外语", "世界"),
        icon("pencil.and.outline", "写作", .creative, true, "文字", "编辑"),
        icon("camera", "摄影", .creative, true, "照片", "影像"),
        icon("paintpalette", "设计", .creative, true, "绘画", "颜色"),
        icon("music.note", "音乐", .creative, false, "歌曲", "声音"),
        icon("film", "视频", .creative, false, "电影", "剪辑"),
        icon("hammer", "制作", .creative, false, "手工", "工具"),
        icon("figure.run", "运动", .health, true, "跑步", "锻炼"),
        icon("dumbbell", "健身", .health, true, "力量", "训练"),
        icon("cross.case", "健康", .health, false, "医疗", "医生"),
        icon("bed.double", "睡眠", .health, false, "休息", "卧室"),
        icon("figure.mind.and.body", "冥想", .health, false, "专注", "瑜伽"),
        icon("bicycle", "骑行", .health, false, "单车", "运动"),
        icon("airplane", "旅行", .travel, true, "飞机", "远行"),
        icon("car", "驾车", .travel, false, "汽车", "通勤"),
        icon("tram", "公共交通", .travel, false, "地铁", "火车"),
        icon("map", "地点", .travel, false, "地图", "路线"),
        icon("suitcase.rolling", "行李", .travel, false, "出差", "箱包"),
        icon("tent", "露营", .travel, false, "户外", "营地"),
        icon("star", "收藏", .life, true, "重要", "喜爱"),
        icon("flag", "里程碑", .work, false, "重点", "阶段"),
        icon("lightbulb", "灵感", .creative, false, "创意", "想法"),
        icon("bolt", "效率", .work, false, "快速", "能量"),
        icon("checkmark.circle", "完成", .work, false, "任务", "检查"),
        icon("clock", "时间", .work, false, "计时", "安排"),
        icon("tray", "收集箱", .work, false, "收件", "输入"),
        icon("archivebox", "归档", .work, false, "保存", "历史"),
        icon("tag", "标签", .work, false, "分类", "标记"),
        icon("person", "个人", .life, true, "自己", "私人"),
        icon("figure.2.and.child.holdinghands", "亲子", .life, false, "孩子", "家庭"),
        icon("gamecontroller", "游戏", .life, false, "娱乐", "休闲"),
        icon("cup.and.saucer", "休息", .life, false, "咖啡", "放松"),
        icon("banknote", "财务", .life, true, "金钱", "预算"),
        icon("creditcard", "账单", .life, false, "支付", "消费"),
        icon("wifi", "网络", .work, false, "在线", "连接"),
        icon("desktopcomputer", "电脑", .work, false, "软件", "开发"),
        icon("curlybraces", "编程", .work, false, "代码", "开发"),
        icon("shippingbox", "产品", .work, false, "交付", "包装")
    ]

    private static func icon(
        _ symbol: String,
        _ label: String,
        _ category: WorkspaceIconCategory,
        _ isCommon: Bool,
        _ keywords: String...
    ) -> WorkspaceIconOption {
        WorkspaceIconOption(symbol: symbol, label: label, category: category, isCommon: isCommon, keywords: keywords)
    }
}
