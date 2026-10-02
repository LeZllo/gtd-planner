import SwiftUI

/// A workspace-wide matrix, independent from the dated planning views.
struct QuadrantWorkspace: View {
    @Environment(AppModel.self) private var model: AppModel
    let now: Date
    @FocusState.Binding var inspectorNoteFocused: Bool
    @State private var query = ""
    @State private var creationQuadrant: TaskQuadrant?

    private var snapshot: QuadrantSnapshot { model.quadrantSnapshot(now: now) }
    private var visibleTaskIDs: Set<UUID> { Set(snapshot.tasks.filter(matchesSearch).map(\.id)) }

    var body: some View {
        let snapshot = self.snapshot
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header(snapshot)
                searchBar
                GeometryReader { geometry in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(snapshot.buckets) { bucket in
                                quadrantCard(bucket)
                                    .frame(height: max(250, (geometry.size.height - 16) / 2))
                            }
                        }
                    }
                }
                .padding(18)
                Text("重要 = 高优先级  ·  紧急 = 截止时间早于本地明天 00:00（含今天截止和逾期）")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
            }
            .frame(minWidth: 650, maxWidth: .infinity, maxHeight: .infinity)
            .background(ModernPalette.canvas)
            Divider()
            Group {
                if model.selectedTask != nil {
                    ModernInspectorPane(inspectorNoteFocused: $inspectorNoteFocused)
                } else {
                    QuadrantOverviewPane(snapshot: snapshot)
                }
            }
            .frame(width: 390)
        }
        .sheet(item: $creationQuadrant) { quadrant in
            QuadrantTaskComposer(quadrant: quadrant, now: now, onCreated: { query = "" }) { creationQuadrant = nil }
                .environment(model)
        }
        .onChange(of: visibleTaskIDs, initial: true) { _, visible in
            if let taskID = model.selection.taskSelection?.taskID, !visible.contains(taskID) {
                model.clearSelectedTask()
            }
        }
        .onChange(of: model.selection.selectedWorkspaceID) { _, _ in
            creationQuadrant = nil
            query = ""
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("四象限任务面板")
        .tint(ModernPalette.accent)
    }

    private func header(_ snapshot: QuadrantSnapshot) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("四象限")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                Text("当前工作区全部未完成任务，包含无日期任务")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ModernPalette.muted)
            }
            Spacer()
            Text("\(snapshot.totalCount) 项任务")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ModernPalette.railInk)
                .monospacedDigit()
            Menu {
                ForEach(TaskQuadrant.allCases) { quadrant in
                    Button(quadrant.title) { creationQuadrant = quadrant }
                }
            } label: {
                Label("新建任务", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(ModernPalette.accent)
        }
        .padding(.horizontal, 22)
        .frame(height: 82)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ModernPalette.line.opacity(0.58)).frame(height: 0.5)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(ModernPalette.muted)
            TextField("搜索任务、项目、标签或笔记", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Text("\(visibleTaskIDs.count) 项匹配")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.muted)
                    .fixedSize()
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(ModernPalette.muted)
                    .accessibilityLabel("清除四象限搜索")
            }
        }
        .font(.system(size: 12))
        .padding(10)
        .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private func quadrantCard(_ bucket: QuadrantBucket) -> some View {
        let tasks = bucket.tasks.filter(matchesSearch)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: bucket.quadrant.symbol)
                    .foregroundStyle(bucket.quadrant.isUrgent ? ModernPalette.red : ModernPalette.accent)
                    .accessibilityHidden(true)
                Text(bucket.quadrant.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "\(bucket.count)" : "\(tasks.count)/\(bucket.count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)
                    .monospacedDigit()
                    .help("匹配任务数 / 此象限全部任务数")
                Spacer(minLength: 2)
                Button { creationQuadrant = bucket.quadrant } label: {
                    Image(systemName: "plus").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.accent)
                .accessibilityLabel("在\(bucket.quadrant.title)象限新建任务")
            }
            .padding(.horizontal, 14)
            .padding(.top, 9)
            Text(bucket.quadrant.subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(ModernPalette.muted)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            Divider()
            if tasks.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: query.isEmpty ? bucket.quadrant.symbol : "magnifyingglass")
                        .font(.system(size: 23, weight: .light))
                        .foregroundStyle(ModernPalette.muted)
                    Text(query.isEmpty ? "此象限暂无任务" : "此象限没有匹配任务")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ModernPalette.muted)
                    if query.isEmpty {
                        Button("新建任务") { creationQuadrant = bucket.quadrant }
                            .buttonStyle(.plain)
                            .foregroundStyle(ModernPalette.accent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tasks) { task in
                            QuadrantTaskRow(task: task, now: now)
                        }
                    }
                }
            }
        }
        .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).stroke(ModernPalette.line.opacity(0.65), lineWidth: 0.75)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(bucket.quadrant.title)，共 \(bucket.count) 项任务")
    }

    private func matchesSearch(_ task: GTDTask) -> Bool {
        QuadrantProjection.matchesSearch(task, query: query, projectName: model.project(for: task)?.name ?? "")
    }
}

private struct QuadrantTaskRow: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask
    let now: Date
    @State private var showsScheduler = false
    @State private var showsDeadlineEditor = false
    @State private var confirmsRecurringCompletion = false

    private var isDaily: Bool { TodayExecutionProjection.isDailyRecurring(task) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                Button(action: requestCompletion) {
                    Image(systemName: "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(ModernPalette.completion)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(isDaily ? "完成整项任务并结束每日重复" : "完成整项任务及其下级任务")
                .accessibilityLabel("完成整项任务：\(task.title)")
                Button { model.selectTask(task.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ModernPalette.ink)
                            .lineLimit(2)
                        Text([model.project(for: task)?.name, task.status.title, isDaily ? "每天重复" : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10.5))
                            .foregroundStyle(ModernPalette.muted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                PlannerTaskActionsButton(taskID: task.id)
            }
            HStack(spacing: 7) {
                if let deadline = task.deadline {
                    Label(quadrantDeadlineText(task), systemImage: deadline < now ? "exclamationmark.circle" : "calendar")
                        .foregroundStyle(deadline < now ? ModernPalette.red : ModernPalette.muted)
                        .lineLimit(1)
                        .help("截止时间：\(deadline.formatted(date: .complete, time: task.deadlinePrecision == .minute ? .shortened : .omitted))")
                } else {
                    Text("无截止日期").foregroundStyle(ModernPalette.muted)
                }
                Spacer(minLength: 0)
                Button { showsScheduler = true } label: {
                    Label("安排", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(ModernPalette.accent)
                .accessibilityLabel("为\(task.title)安排今天或指定日期的执行时段")
            }
            .font(.system(size: 10.5))
            .padding(.leading, 33)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(model.isTaskSelected(task.id) ? ModernPalette.selection.opacity(0.075) : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ModernPalette.line.opacity(0.45)).frame(height: 0.5).padding(.leading, 45)
        }
        .plannerTaskActions(taskID: task.id)
        .popover(isPresented: $showsScheduler, arrowEdge: .trailing) {
            QuadrantSchedulePopover(taskID: task.id, initialDay: now) { showsScheduler = false }
                .environment(model)
        }
        .popover(isPresented: $showsDeadlineEditor, arrowEdge: .trailing) {
            QuadrantDeadlineEditor(task: task, now: now) { showsDeadlineEditor = false }
                .environment(model)
        }
        .confirmationDialog("完成整项每日重复任务？", isPresented: $confirmsRecurringCompletion, titleVisibility: .visible) {
            Button("完成整项任务并结束重复") { _ = model.completeQuadrantTask(taskID: task.id) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会完成“\(task.title)”及其下级任务，并结束后续重复。只完成今天这一次，请到“今天”视图操作。")
        }
    }

    @ViewBuilder
    private var taskActions: some View {
        Button("查看任务详情") { model.selectTask(task.id) }
        Button("安排今天或指定日期…") { showsScheduler = true }
        Divider()
        Menu("优先级（高 = 重要）") {
            ForEach(Priority.allCases) { priority in
                Button(priority == .high ? "高优先级（重要）" : "\(priority.title)优先级（不重要）") {
                    _ = model.applyQuadrantAction(.setPriority(priority), taskID: task.id)
                }
                .disabled(task.priority == priority)
            }
        }
        Menu("明确修改截止时间") {
            Button("今天截止（日终）") {
                _ = model.applyQuadrantAction(.setDeadline(now, precision: .date), taskID: task.id)
            }
            Button("明天截止（日终）") {
                guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return }
                _ = model.applyQuadrantAction(.setDeadline(tomorrow, precision: .date), taskID: task.id)
            }
            Button("选择截止日期与精度…") { showsDeadlineEditor = true }
            Button("清除截止时间") {
                _ = model.applyQuadrantAction(.clearDeadline, taskID: task.id)
            }
            .disabled(task.deadline == nil)
        }
        Divider()
        Button(isDaily ? "完成整项任务并结束重复…" : "完成整项任务") { requestCompletion() }
    }

    private func requestCompletion() {
        guard let current = model.task(withID: task.id), !current.status.isFinished,
              current.workspaceID == model.selection.selectedWorkspaceID else { return }
        if TodayExecutionProjection.isDailyRecurring(current) {
            confirmsRecurringCompletion = true
        } else {
            _ = model.completeQuadrantTask(taskID: task.id)
        }
    }
}

private struct QuadrantTaskComposer: View {
    @Environment(AppModel.self) private var model: AppModel
    let quadrant: TaskQuadrant
    let now: Date
    let onCreated: () -> Void
    let onDismiss: () -> Void
    @State private var title = ""
    @State private var priority: Priority
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var submitted = false
    @FocusState private var titleFocused: Bool

    init(quadrant: TaskQuadrant, now: Date, onCreated: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.quadrant = quadrant
        self.now = now
        self.onCreated = onCreated
        self.onDismiss = onDismiss
        let defaults = QuadrantTaskDefaults(quadrant: quadrant, now: now)
        _priority = State(initialValue: defaults.priority)
        _hasDeadline = State(initialValue: defaults.deadline != nil)
        _deadline = State(initialValue: defaults.deadline ?? now)
    }

    private var resultingQuadrant: TaskQuadrant {
        var draft = GTDTask(title: title, workspaceID: model.selection.selectedWorkspaceID, parentID: nil, status: .open)
        draft.priority = priority
        draft.deadline = hasDeadline ? TaskDateNormalizer.normalizedDeadline(deadline, precision: .date) : nil
        return QuadrantProjection.quadrant(for: draft, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建任务")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ModernPalette.ink)
            Text("从“\(quadrant.title)”新建 · 当前工作区 · 未分配项目")
                .font(.system(size: 11))
                .foregroundStyle(ModernPalette.muted)
            TextField("任务名称", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
            Picker("优先级", selection: $priority) {
                ForEach(Priority.allCases) { priority in
                    Text(priority == .high ? "高（重要）" : priority.title).tag(priority)
                }
            }
            Toggle("设置截止日期（日终）", isOn: $hasDeadline)
            if hasDeadline {
                DatePicker("截止日期", selection: $deadline, displayedComponents: [.date])
            }
            Label("将归入：\(resultingQuadrant.title)", systemImage: resultingQuadrant.symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ModernPalette.accent)
            Text("这里只设置上方显示的优先级与截止日期，不自动添加计划或执行时段。创建后可用“安排”选择时间。")
                .font(.system(size: 11))
                .foregroundStyle(ModernPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("取消", action: onDismiss).keyboardShortcut(.cancelAction)
                Button("创建任务", action: createTask)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(submitted || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(ModernPalette.panel)
        .tint(ModernPalette.accent)
        .onAppear { titleFocused = true }
    }

    private func createTask() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submitted, !trimmed.isEmpty else { return }
        submitted = true
        model.addTask(
            title: trimmed, status: .open, priority: priority,
            deadline: hasDeadline ? TaskDateNormalizer.normalizedDeadline(deadline, precision: .date) : nil,
            deadlinePrecision: hasDeadline ? .date : .none
        )
        model.notice = "已创建任务，归入\(resultingQuadrant.title)"
        onCreated()
        onDismiss()
    }
}

private struct QuadrantSchedulePopover: View {
    @Environment(AppModel.self) private var model: AppModel
    let taskID: UUID
    let onDismiss: () -> Void
    @State private var day: Date

    init(taskID: UUID, initialDay: Date, onDismiss: @escaping () -> Void) {
        self.taskID = taskID
        self.onDismiss = onDismiss
        _day = State(initialValue: Calendar.current.startOfDay(for: initialDay))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                DatePicker("安排日期", selection: $day, displayedComponents: [.date])
                Text("默认今天，也可明确选择其他日期。选择日期不会改动任务截止时间。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.muted)
            }
            .padding(16)
            Divider()
            if let task = model.task(withID: taskID), task.workspaceID == model.selection.selectedWorkspaceID {
                DayScheduleEditor(task: task, day: day, onSaved: onDismiss)
                    .id(Calendar.current.startOfDay(for: day))
            } else {
                Text("任务已不存在或已移出当前工作区")
                    .foregroundStyle(ModernPalette.muted)
                    .padding(16)
                Button("关闭", action: onDismiss).padding(16)
            }
        }
        .frame(width: 370)
        .background(ModernPalette.panel)
        .tint(ModernPalette.accent)
    }
}

private struct QuadrantDeadlineEditor: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask
    let onDismiss: () -> Void
    @State private var date: Date
    @State private var precision: DeadlinePrecision

    init(task: GTDTask, now: Date, onDismiss: @escaping () -> Void) {
        self.task = task
        self.onDismiss = onDismiss
        _date = State(initialValue: task.deadline ?? now)
        _precision = State(initialValue: task.deadlinePrecision == .minute ? .minute : .date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("修改截止时间").font(.system(size: 15, weight: .semibold))
            Text(task.title).font(.system(size: 11.5)).foregroundStyle(ModernPalette.muted).lineLimit(2)
            Picker("精度", selection: $precision) {
                Text("日期（日终）").tag(DeadlinePrecision.date)
                Text("具体时间").tag(DeadlinePrecision.minute)
            }
            .pickerStyle(.segmented)
            DatePicker("截止", selection: $date, displayedComponents: precision == .minute ? [.date, .hourAndMinute] : [.date])
            Text("此操作会修改截止时间并重新计算紧急程度。优先级、计划和执行时段保持不变。")
                .font(.system(size: 10.5))
                .foregroundStyle(ModernPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("取消", action: onDismiss).keyboardShortcut(.cancelAction)
                Button("保存截止时间") {
                    _ = model.applyQuadrantAction(.setDeadline(date, precision: precision), taskID: task.id)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 370)
        .background(ModernPalette.panel)
        .tint(ModernPalette.accent)
    }
}

private struct QuadrantOverviewPane: View {
    let snapshot: QuadrantSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("优先级概览", systemImage: "square.grid.2x2")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ModernPalette.ink)
            Text(snapshot.day.formatted(.dateTime.year().month(.defaultDigits).day(.defaultDigits).weekday(.wide)))
                .font(.system(size: 12))
                .foregroundStyle(ModernPalette.muted)
            value("未完成任务", count: snapshot.totalCount)
            value("重要 · 高优先级", count: snapshot.importantCount)
            value("紧急 · 今天截止或已逾期", count: snapshot.urgentCount)
            Divider()
            Text("选择任务查看详情\n在每格用 ＋ 新建任务\n用“安排”添加今天或指定日期的执行时段\n用更多操作明确调整优先级或截止时间")
                .font(.system(size: 12))
                .foregroundStyle(ModernPalette.railInk)
                .lineSpacing(8)
            Text("勾选会完成整项任务及其下级任务；每日重复任务会先确认结束。今天实例已完成的重复任务仍保留，直到整项任务完成或取消。")
                .font(.system(size: 11))
                .foregroundStyle(ModernPalette.muted)
                .lineSpacing(5)
            Text("分类只读取优先级和截止时间，不会因为计划或执行时段而改变。无截止任务归入不紧急，非高优先级任务归入不重要。")
                .font(.system(size: 11))
                .foregroundStyle(ModernPalette.muted)
                .lineSpacing(5)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ModernPalette.panel)
    }

    private func value(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).foregroundStyle(ModernPalette.muted)
            Spacer()
            Text("\(count)").fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

private func quadrantDeadlineText(_ task: GTDTask) -> String {
    guard let deadline = task.deadline else { return "无截止日期" }
    return task.deadlinePrecision == .minute
        ? "\(deadline.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).hour().minute())) 截止"
        : "\(deadline.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))) 截止"
}
