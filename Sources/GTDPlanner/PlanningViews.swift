import SwiftUI

/// Future planning deliberately has no completion or actual-focus controls.
/// Day groups are occurrences; the inspector continues to edit the canonical task.
struct UpcomingPlanningWorkspace: View {
    @Environment(AppModel.self) private var model: AppModel
    let horizon: PlanningHorizon
    let now: Date
    @Binding var quickTaskDraft: ModernQuickTaskDraft
    @FocusState.Binding var quickTaskFocused: Bool
    @FocusState.Binding var inspectorNoteFocused: Bool
    @State private var query = ""
    @State private var showsTaskPicker = false

    private var snapshot: PlanningHorizonSnapshot {
        model.planningHorizonSnapshot(for: horizon, now: now)
    }

    private var selectedDay: Date {
        let days = horizon.days(relativeTo: now)
        if let proposed = model.selection.planningDay,
           let day = days.first(where: { Calendar.current.isDate($0, inSameDayAs: proposed) }) {
            return day
        }
        return days.first ?? Calendar.current.startOfDay(for: now)
    }

    private var newTaskDay: Date {
        quickTaskDraft.hasPlan ? quickTaskDraft.plannedStart : selectedDay
    }

    private var visibleTaskIDs: Set<UUID> {
        Set(snapshot.tasks.filter(matchesSearch).map(\.id))
    }

    var body: some View {
        let snapshot = self.snapshot
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header(snapshot)
                if horizon == .nextSevenDays { dayPicker(snapshot) }
                searchBar
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(snapshot.days, id: \.day) { day in
                            daySection(day)
                        }
                    }
                    .padding(18)
                }
                Divider()
                HStack {
                    Label("\(quickTaskDraft.hasPlan ? "自定计划优先" : "新任务日期")：\(planningDateText(newTaskDay))", systemImage: "calendar")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ModernPalette.muted)
                    Spacer()
                    Button("安排已有任务") { showsTaskPicker = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(ModernPalette.blue)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                ModernQuickTaskComposer(
                    draft: $quickTaskDraft,
                    isFocused: $quickTaskFocused,
                    placeholder: "安排到 \(planningDateText(newTaskDay))，按 Enter 创建",
                    onSubmit: createTask
                )
            }
            .frame(minWidth: 650, maxWidth: .infinity, maxHeight: .infinity)
            .background(ModernPalette.canvas)
            Divider()
            Group {
                if model.selectedTask != nil {
                    VStack(spacing: 0) {
                        Text("任务详情中的状态修改作用于整项任务；计时从现在开始")
                            .font(.system(size: 10.5))
                            .foregroundStyle(ModernPalette.muted)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(ModernPalette.panel)
                        Divider()
                        ModernInspectorPane(inspectorNoteFocused: $inspectorNoteFocused)
                    }
                } else {
                    PlanningOverviewPane(snapshot: snapshot, horizon: horizon)
                }
            }
            .frame(width: 390)
        }
        .sheet(isPresented: $showsTaskPicker) {
            DayPlanningTaskPicker(day: selectedDay, now: now) {
                showsTaskPicker = false
            }
            .environment(model)
        }
        .onAppear {
            if !quickTaskDraft.hasPlan {
                quickTaskDraft.plannedStart = selectedDay
                quickTaskDraft.plannedEnd = selectedDay
            }
        }
        .onChange(of: visibleTaskIDs, initial: true) { _, visible in
            if let taskID = model.selection.taskSelection?.taskID, !visible.contains(taskID) {
                model.clearSelectedTask()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(horizon.title)计划面板")
    }

    private func header(_ snapshot: PlanningHorizonSnapshot) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(horizon.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                Text(horizon == .tomorrow
                     ? planningDateText(selectedDay)
                     : "从明天起连续 7 个自然日，不含今天")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ModernPalette.muted)
            }
            Spacer()
            Text("\(snapshot.totalCount) 项任务")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ModernPalette.railInk)
                .monospacedDigit()
                .help("跨日和每日重复任务按任务去重；每天的分组按出现次数统计")
            Button {
                showsTaskPicker = true
            } label: {
                Label("安排任务", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 22)
        .frame(height: 82)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ModernPalette.line.opacity(0.58)).frame(height: 0.5)
        }
    }

    private func dayPicker(_ snapshot: PlanningHorizonSnapshot) -> some View {
        HStack(spacing: 6) {
            ForEach(snapshot.days, id: \.day) { day in
                let isSelected = Calendar.current.isDate(day.day, inSameDayAs: selectedDay)
                Button {
                    selectDay(day.day)
                } label: {
                    VStack(spacing: 5) {
                        Text(day.day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 10.5, weight: .medium))
                        Text(day.day.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits)))
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(day.totalCount) 项")
                            .font(.system(size: 10))
                            .monospacedDigit()
                    }
                    .foregroundStyle(isSelected ? ModernPalette.blue : ModernPalette.railInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSelected ? ModernPalette.blue.opacity(0.09) : ModernPalette.panel,
                                in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(isSelected ? ModernPalette.blue.opacity(0.4) : ModernPalette.line.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新任务日期 \(planningDateText(day.day))，\(day.totalCount) 项任务")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(ModernPalette.muted)
            TextField("搜索任务、项目、标签或笔记", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(ModernPalette.muted)
                    .accessibilityLabel("清除任务搜索")
            }
        }
        .font(.system(size: 12))
        .padding(10)
        .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private func daySection(_ day: TodayExecutionSnapshot) -> some View {
        let tasks = day.tasks.filter(matchesSearch)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(planningDateText(day.day))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                Text(query.isEmpty ? "\(day.totalCount) 项 · \(day.waitingCount) 项待安排" : "\(tasks.count) 项匹配")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.muted)
                Spacer()
                Button {
                    selectDay(day.day)
                    showsTaskPicker = true
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.blue)
                .help("安排已有任务到 \(planningDateText(day.day))")
                .accessibilityLabel("安排已有任务到 \(planningDateText(day.day))")
                Button {
                    selectDay(day.day)
                    Task { @MainActor in
                        await Task.yield()
                        quickTaskFocused = true
                    }
                } label: {
                    Image(systemName: "plus").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.blue)
                .accessibilityLabel("在 \(planningDateText(day.day)) 新建任务")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            if tasks.isEmpty {
                Text(query.isEmpty ? "还没有安排，可添加任务或从现有任务中选择" : "这一天没有匹配的任务")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ModernPalette.muted)
                    .padding(18)
            } else {
                ForEach(tasks) { task in
                    PlanningTaskRow(task: task, snapshot: day)
                }
            }
        }
        .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).stroke(ModernPalette.line.opacity(0.65), lineWidth: 0.75)
        }
    }

    private func matchesSearch(_ task: GTDTask) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return [task.title, task.note, model.project(for: task)?.name ?? "", task.tags.joined(separator: " "), task.contexts.joined(separator: " ")]
            .joined(separator: " ").localizedCaseInsensitiveContains(needle)
    }

    private func selectDay(_ day: Date) {
        model.selection.planningDay = day
        // An explicit draft plan is retained; only the contextual default changes.
        if !quickTaskDraft.hasPlan {
            quickTaskDraft.plannedStart = day
            quickTaskDraft.plannedEnd = day
        }
    }

    private func createTask() {
        let title = quickTaskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let plan: (start: Date, end: Date?)
        if quickTaskDraft.hasPlan {
            guard let explicitPlan = TaskDateNormalizer.normalizedPlan(
                start: quickTaskDraft.plannedStart,
                end: quickTaskDraft.hasPlannedEnd ? quickTaskDraft.plannedEnd : nil,
                precision: quickTaskDraft.plannedPrecision
            ) else {
                model.notice = "计划结束必须晚于计划时间"
                return
            }
            plan = explicitPlan
        } else {
            plan = (selectedDay, nil)
        }
        model.addTask(
            title: title, status: .open, priority: quickTaskDraft.priority,
            actionList: quickTaskDraft.actionList, plannedStart: plan.start, plannedEnd: plan.end,
            plannedPrecision: quickTaskDraft.hasPlan ? quickTaskDraft.plannedPrecision : .date,
            deadline: quickTaskDraft.hasDeadline
                ? TaskDateNormalizer.normalizedDeadline(quickTaskDraft.deadline, precision: quickTaskDraft.deadlinePrecision)
                : nil,
            deadlinePrecision: quickTaskDraft.hasDeadline ? quickTaskDraft.deadlinePrecision : .none,
            tags: quickTaskDraft.tags
        )
        quickTaskDraft.reset()
        quickTaskDraft.plannedStart = selectedDay
        quickTaskDraft.plannedEnd = selectedDay
        if !query.isEmpty { query = "" }
        model.notice = "已创建任务，计划于 \(planningDateText(plan.start))"
    }
}

private struct PlanningTaskRow: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask
    let snapshot: TodayExecutionSnapshot
    @State private var showsScheduler = false

    private var completed: Bool { snapshot.completedTasks.contains { $0.id == task.id } }
    private var blocks: [TodayPlanBlock] { snapshot.planBlocks.filter { $0.taskID == task.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: completed ? "checkmark.circle.fill" : (TodayExecutionProjection.isDailyRecurring(task) ? "repeat" : "circle.dotted"))
                    .foregroundStyle(completed ? ModernPalette.completion : ModernPalette.muted)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Button { model.selectTask(task.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(ModernPalette.ink)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            if let project = model.project(for: task) { Text(project.name) }
                            if TodayExecutionProjection.isDailyRecurring(task) { Text("每天重复") }
                            if TodayExecutionProjection.isMultiDayPlan(task) { Text(task.planRangeIntent.title) }
                            if let deadline = task.deadline {
                                Text(task.deadlinePrecision == .minute
                                     ? "\(deadline.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).hour().minute())) 截止"
                                     : "\(deadline.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))) 截止")
                                    .foregroundStyle(deadline < .now ? ModernPalette.red : ModernPalette.muted)
                            }
                            if blocks.isEmpty && !completed { Text("待安排时段") }
                            if completed { Text("这一天已完成") }
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(ModernPalette.muted)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !completed && !task.status.isFinished {
                    Button { showsScheduler = true } label: {
                        Label("安排", systemImage: "calendar.badge.plus")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("为 \(task.title) 安排 \(planningDateText(snapshot.day)) 的时段")
                    .popover(isPresented: $showsScheduler, arrowEdge: .trailing) {
                        DayScheduleEditor(task: task, day: snapshot.day) { showsScheduler = false }
                            .id("\(task.id)-\(Calendar.current.startOfDay(for: snapshot.day))")
                            .environment(model)
                    }
                }
            }
            ForEach(blocks) { block in
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(block.isPoint ? block.start.formatted(date: .omitted, time: .shortened)
                         : planningTimeRange(start: block.start, end: block.end, day: snapshot.day))
                    Text(block.id.source == .executionSlot ? "执行时段" : (block.isPoint ? "计划时间点" : "任务计划"))
                        .foregroundStyle(ModernPalette.muted)
                    Spacer()
                    if let slotID = block.id.slotID {
                        Button {
                            _ = model.removeExecutionSlot(taskID: task.id, slotID: slotID)
                        } label: { Image(systemName: "xmark.circle").frame(width: 22, height: 22) }
                            .buttonStyle(.plain)
                            .foregroundStyle(ModernPalette.muted)
                            .help("移除整个执行时段，保留任务计划和截止时间")
                            .accessibilityLabel("移除 \(task.title) 的 \(planningTimeRange(start: block.start, end: block.end, day: snapshot.day)) 执行时段")
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(ModernPalette.blue)
                .padding(.leading, 32)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .plannerTaskActions(taskID: task.id, scope: .day(snapshot.day))
        .background(model.isTaskSelected(task.id) ? ModernPalette.blue.opacity(0.055) : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ModernPalette.line.opacity(0.45)).frame(height: 0.5).padding(.leading, 46)
        }
    }
}

struct DayPlanningTaskPicker: View {
    @Environment(AppModel.self) private var model: AppModel
    let day: Date
    var now: Date = .now
    let onDismiss: () -> Void
    @State private var query = ""
    @State private var selectedTaskID: UUID?

    private var candidates: [GTDTask] {
        model.dayPlanningCandidates(on: day, now: now)
            .filter { task in
                let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
                return needle.isEmpty || [task.title, model.project(for: task)?.name ?? "", task.tags.joined(separator: " ")]
                    .joined(separator: " ").localizedCaseInsensitiveContains(needle)
            }
    }

    var body: some View {
        if let selectedTaskID, let task = model.task(withID: selectedTaskID) {
            VStack(alignment: .leading, spacing: 0) {
                Button("返回任务选择") { self.selectedTaskID = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(ModernPalette.blue)
                    .padding([.top, .horizontal], 16)
                DayScheduleEditor(task: task, day: day, onSaved: onDismiss)
                    .id("\(task.id)-\(Calendar.current.startOfDay(for: day))")
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("安排已有任务").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button("取消", action: onDismiss).keyboardShortcut(.cancelAction)
                }
                Text(planningDateText(day)).foregroundStyle(ModernPalette.muted)
                Text("从当前工作区选择任务。这里只添加执行时段，不改动原计划或截止时间。")
                    .font(.system(size: 11))
                    .foregroundStyle(ModernPalette.muted)
                TextField("搜索任务、项目或标签", text: $query).textFieldStyle(.roundedBorder)
                Divider()
                if candidates.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "没有可安排的任务" : "没有匹配的任务",
                                           systemImage: "calendar.badge.checkmark",
                                           description: Text("已安排的任务可在日期清单中添加另一个时段"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(candidates) { task in
                                Button { selectedTaskID = task.id } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(task.title).foregroundStyle(ModernPalette.ink)
                                            if let project = model.project(for: task) {
                                                Text(project.name).font(.system(size: 10.5)).foregroundStyle(ModernPalette.muted)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(ModernPalette.muted)
                                    }
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 440, height: 500)
        }
    }
}

private struct PlanningOverviewPane: View {
    let snapshot: PlanningHorizonSnapshot
    let horizon: PlanningHorizon

    private var plannedMinutes: Int {
        Int((snapshot.days.reduce(0) { $0 + $1.plannedDuration } / 60).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("计划概览", systemImage: "calendar")
                .font(.system(size: 16, weight: .semibold))
            if let first = snapshot.days.first, let last = snapshot.days.last {
                Text(first.day == last.day ? planningDateText(first.day)
                     : "\(planningDateText(first.day)) – \(planningDateText(last.day))")
                    .font(.system(size: 12))
                    .foregroundStyle(ModernPalette.muted)
            }
            overviewValue("任务总数（去重）", value: "\(snapshot.totalCount)")
            overviewValue("具体计划时长", value: "\(plannedMinutes / 60) 小时 \(plannedMinutes % 60) 分")
            Divider()
            Text("选择任务查看详情\n使用日期卡片或分组中的 ＋ 设置新任务日期\n用“安排任务”为现有任务添加具体执行时段")
                .font(.system(size: 12))
                .foregroundStyle(ModernPalette.railInk)
                .lineSpacing(8)
            Text("跨日任务会出现在对应的各天，顶部总数按任务去重。日期范围不换算成全天工时；重叠时段按各时段累计。仅已逾期任务留在今天，可手动安排到未来。")
                .font(.system(size: 11))
                .foregroundStyle(ModernPalette.muted)
                .lineSpacing(5)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ModernPalette.panel)
    }

    private func overviewValue(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(ModernPalette.muted)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

private func planningDateText(_ date: Date) -> String {
    date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).weekday(.wide))
}

private func planningTimeRange(start: Date, end: Date, day: Date) -> String {
    let endPrefix = Calendar.current.isDate(end, inSameDayAs: day) ? "" : "次日 "
    return "\(start.formatted(date: .omitted, time: .shortened))–\(endPrefix)\(end.formatted(date: .omitted, time: .shortened))"
}
