import AppKit
import SwiftUI

struct TodayExecutionPane: View {
    @Environment(AppModel.self) private var model: AppModel
    @Binding var quickTaskDraft: ModernQuickTaskDraft
    @FocusState.Binding var quickTaskFocused: Bool

    @State private var showsWaitingDrawer = false
    @State private var waitingFilter = TodayTaskFilter.all
    @State private var query = ""
    @State private var showsTaskPicker = false

    var day: Date = Calendar.current.startOfDay(for: .now)

    var body: some View {
        @Bindable var selection = model.selection
        let fullSnapshot = model.todayExecutionSnapshot(on: day)
        let snapshot = filteredSnapshot(fullSnapshot)

        VStack(spacing: 0) {
            TodayExecutionHeader(
                day: day,
                mode: $selection.todayViewMode,
                completedCount: fullSnapshot.completedCount,
                totalCount: fullSnapshot.totalCount
            )

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(ModernPalette.muted)
                TextField("搜索今日任务、项目、标签或笔记", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除今日任务搜索")
                }
                Button { showsTaskPicker = true } label: {
                    Label("安排已有任务", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            TodaySummaryBar(
                snapshot: snapshot,
                onOpenDrawer: openWaitingDrawer,
                onSelectTask: model.selectTask
            )
            .popover(isPresented: $showsWaitingDrawer, arrowEdge: .top) {
                TodayWaitingDrawer(
                    snapshot: snapshot,
                    day: day,
                    filter: $waitingFilter
                )
                .environment(model)
                .frame(width: 500, height: 560)
            }

            switch selection.todayViewMode {
            case .list:
                TodayTaskList(snapshot: snapshot, day: day)
            case .schedule:
                TodayVerticalSchedule(snapshot: snapshot, day: day)
            }

            ModernQuickTaskComposer(
                draft: $quickTaskDraft,
                isFocused: $quickTaskFocused,
                placeholder: "安排任务到今天，按 Enter 创建",
                onSubmit: createTodayTask
            )
        }
        .background(ModernPalette.canvas)
        .sheet(isPresented: $showsTaskPicker) {
            DayPlanningTaskPicker(day: day) { showsTaskPicker = false }
                .environment(model)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("UI-05 今日执行面板")
        .onChange(of: snapshot.tasks.map(\.id), initial: true) { _, visible in
            if let taskID = model.selection.taskSelection?.taskID, !visible.contains(taskID) {
                model.clearSelectedTask()
            }
        }
        .onAppear {
            if !quickTaskDraft.hasPlan {
                quickTaskDraft.plannedStart = day
                quickTaskDraft.plannedEnd = day
            }
        }

    }

    private func filteredSnapshot(_ snapshot: TodayExecutionSnapshot) -> TodayExecutionSnapshot {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return snapshot }
        let ids = Set(snapshot.tasks.filter { task in
            [task.title, task.note, model.project(for: task)?.name ?? "", task.tags.joined(separator: " "), task.contexts.joined(separator: " ")]
                .joined(separator: " ").localizedCaseInsensitiveContains(needle)
        }.map(\.id))
        return snapshot.filteringTasks(to: ids)
    }

    private func openWaitingDrawer(_ filter: TodayTaskFilter) {
        waitingFilter = filter
        showsWaitingDrawer = true
    }

    private func createTodayTask() {
        let title = quickTaskDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let normalizedPlan: (start: Date, end: Date?)?
        if quickTaskDraft.hasPlan {
            guard let plan = TaskDateNormalizer.normalizedPlan(
                start: quickTaskDraft.plannedStart,
                end: quickTaskDraft.hasPlannedEnd ? quickTaskDraft.plannedEnd : nil,
                precision: quickTaskDraft.plannedPrecision
            ) else {
                model.notice = "计划结束必须晚于计划时间"
                return
            }
            normalizedPlan = plan
        } else {
            normalizedPlan = (day, nil)
        }

        let normalizedDeadline = quickTaskDraft.hasDeadline
            ? TaskDateNormalizer.normalizedDeadline(
                quickTaskDraft.deadline,
                precision: quickTaskDraft.deadlinePrecision
            )
            : nil

        model.addTask(
            title: title,
            status: .open,
            priority: quickTaskDraft.priority,
            actionList: quickTaskDraft.actionList,
            plannedStart: normalizedPlan?.start,
            plannedEnd: normalizedPlan?.end,
            plannedPrecision: quickTaskDraft.hasPlan ? quickTaskDraft.plannedPrecision : .date,
            deadline: normalizedDeadline,
            deadlinePrecision: quickTaskDraft.hasDeadline ? quickTaskDraft.deadlinePrecision : .none,
            tags: quickTaskDraft.tags
        )
        quickTaskDraft.reset()
        quickTaskDraft.plannedStart = day
        quickTaskDraft.plannedEnd = day
        query = ""
    }
}

private struct TodayExecutionHeader: View {
    let day: Date
    @Binding var mode: TodayViewMode
    let completedCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("今天")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                Text(day.formatted(.dateTime.year().month(.wide).day().weekday(.wide)))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)
            }

            Spacer(minLength: 16)

            Picker("今日视图", selection: $mode) {
                ForEach(TodayViewMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 166)

            TodayCompactProgress(completedCount: completedCount, totalCount: totalCount)
        }
        .padding(.horizontal, 22)
        .frame(height: 72)
        .background(ModernPalette.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ModernPalette.line.opacity(0.58)).frame(height: 0.5)
        }
    }
}

private struct TodayCompactProgress: View {
    let completedCount: Int
    let totalCount: Int

    private var progress: Double {
        guard totalCount > 0 else { return 0 }
        return min(1, max(0, Double(completedCount) / Double(totalCount)))
    }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().stroke(ModernPalette.line.opacity(0.65), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ModernPalette.blue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 27, height: 27)
            Text("\(completedCount)/\(totalCount) 已完成")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ModernPalette.railInk)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日已完成 \(completedCount) 项，共 \(totalCount) 项")
    }
}

private struct TodaySummaryBar: View {
    let snapshot: TodayExecutionSnapshot
    let onOpenDrawer: (TodayTaskFilter) -> Void
    let onSelectTask: (UUID) -> Void

    private var visibleProgressTasks: [GTDTask] {
        Array(snapshot.drawerTasks(for: .progress).prefix(2))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                summaryButton("待安排", count: snapshot.waitingCount, filter: .all)
                summaryButton("跨日推进", count: snapshot.count(for: .progress), filter: .progress)
                summaryButton("区间内完成", count: snapshot.count(for: .completeWithin), filter: .completeWithin)
                summaryButton("逾期", count: snapshot.count(for: .overdue), filter: .overdue, tint: ModernPalette.red)
                Spacer(minLength: 8)
                Button {
                    onOpenDrawer(.all)
                } label: {
                    HStack(spacing: 5) {
                        Text("查看")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(ModernPalette.blue)
                .frame(minHeight: 32)
                .accessibilityLabel("查看待安排任务")
            }
            .padding(.horizontal, 18)
            .frame(height: 42)

            if !visibleProgressTasks.isEmpty {
                Divider().opacity(0.7)
                ForEach(visibleProgressTasks) { task in
                    TodayProgressSummaryRow(
                        task: task,
                        extraCount: task.id == visibleProgressTasks.last?.id
                            ? max(0, snapshot.count(for: .progress) - visibleProgressTasks.count)
                            : 0,
                        onSelect: { onSelectTask(task.id) },
                        onShowMore: { onOpenDrawer(.progress) }
                    )
                    if task.id != visibleProgressTasks.last?.id {
                        Divider().padding(.leading, 34).opacity(0.58)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(ModernPalette.panel)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ModernPalette.line.opacity(0.62), lineWidth: 0.75)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func summaryButton(
        _ title: String,
        count: Int,
        filter: TodayTaskFilter,
        tint: Color = ModernPalette.ink
    ) -> some View {
        Button {
            onOpenDrawer(filter)
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Text("\(count)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .padding(.horizontal, 9)
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(tint)
        .accessibilityLabel("\(title) \(count) 项")
    }
}

private struct TodayProgressSummaryRow: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask
    let extraCount: Int
    let onSelect: () -> Void
    let onShowMore: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(ModernPalette.muted)
                .accessibilityHidden(true)
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Text(task.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(ModernPalette.ink)
                        .lineLimit(1)
                    Text(todayPlanRangeText(task))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(ModernPalette.muted)
                        .lineLimit(1)
                    TodayProjectLabel(task: task)
                    Spacer(minLength: 8)
                    Text(task.status == .inProgress ? "进行中" : task.actionList.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(ModernPalette.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if extraCount > 0 {
                Button("+\(extraCount)", action: onShowMore)
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(ModernPalette.railInk)
                    .frame(minWidth: 28, minHeight: 24)
                    .accessibilityLabel("还有 \(extraCount) 个跨日推进任务")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
    }
}

private struct TodayWaitingDrawer: View {
    @Environment(AppModel.self) private var model: AppModel
    let snapshot: TodayExecutionSnapshot
    let day: Date
    @Binding var filter: TodayTaskFilter
    @State private var query = ""

    private var visibleTasks: [GTDTask] {
        let base = snapshot.drawerTasks(for: filter)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return base }
        return base.filter { task in
            let project = model.project(for: task)?.name ?? ""
            return [task.title, task.note, project, task.tags.joined(separator: " ")]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("待安排任务")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(snapshot.waitingCount) 项")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)
                    .monospacedDigit()
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 48)

            TextField("搜索待安排任务", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)

            HStack(spacing: 4) {
                ForEach(TodayTaskFilter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        HStack(spacing: 5) {
                            Text(item.title)
                            Text("\(snapshot.count(for: item))")
                                .monospacedDigit()
                        }
                        .font(.system(size: 10.5, weight: filter == item ? .semibold : .medium))
                        .foregroundStyle(filter == item ? ModernPalette.blue : ModernPalette.railInk)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(
                            filter == item ? ModernPalette.blue.opacity(0.09) : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == item ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 9)

            Divider()

            if visibleTasks.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "这个分类已安排完" : "没有匹配的任务",
                    systemImage: query.isEmpty ? "calendar.badge.checkmark" : "magnifyingglass",
                    description: Text(query.isEmpty ? "具体执行时段会进入今日计划轨" : "请尝试其他关键词")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleTasks) { task in
                            TodayWaitingTaskRow(task: task, day: day)
                            Divider().padding(.leading, 50).opacity(0.62)
                        }
                    }
                }
                .background(ModernPalette.panel)
            }

            Divider()
            Text("只有具体的今日执行时段进入时间轴；日期区间不计入今日计划时长。")
                .font(.system(size: 10.5))
                .foregroundStyle(ModernPalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .frame(height: 42)
        }
        .background(ModernPalette.panel)
    }
}

private struct TodayWaitingTaskRow: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask
    let day: Date
    @State private var showsScheduler = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.toggleTodayCompletion(taskID: task.id, on: day)
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(ModernPalette.line)
                    .frame(width: 26, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("完成 \(task.title)")

            Button {
                model.selectTask(task.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(task.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(ModernPalette.ink)
                            .lineLimit(1)
                        if TodayExecutionProjection.isMultiDayPlan(task) {
                            TodayIntentBadge(intent: task.planRangeIntent)
                        } else if TodayExecutionProjection.isDailyRecurring(task) {
                            TodaySmallBadge(title: "每天重复", tint: ModernPalette.green)
                        }
                    }
                    HStack(spacing: 7) {
                        if task.plannedStart != nil {
                            Text(todayPlanRangeText(task))
                        }
                        if let deadline = task.deadline {
                            Text(todayDeadlineText(deadline, isOverdue: deadline < .now))
                                .foregroundStyle(deadline < .now ? ModernPalette.red : ModernPalette.muted)
                        }
                        TodayProjectLabel(task: task)
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                showsScheduler = true
            } label: {
                Label("安排今日时段", systemImage: "calendar.badge.plus")
                    .font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $showsScheduler, arrowEdge: .trailing) {
                DayScheduleEditor(task: task, day: day) {
                    showsScheduler = false
                }
                .environment(model)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 66)
        .plannerTaskActions(taskID: task.id, scope: .day(day))
    }
}

struct DayScheduleEditor: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask
    let day: Date
    let onSaved: () -> Void
    @State private var start: Date
    @State private var end: Date
    @State private var validationMessage: String?

    init(task: GTDTask, day: Date, onSaved: @escaping () -> Void) {
        self.task = task
        self.day = day
        self.onSaved = onSaved
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let proposedHour = calendar.isDateInToday(day)
            ? min(21, max(8, calendar.component(.hour, from: .now) + 1)) : 9
        let proposedStart = calendar.date(bySettingHour: proposedHour, minute: 0, second: 0, of: dayStart) ?? dayStart
        _start = State(initialValue: proposedStart)
        _end = State(initialValue: proposedStart.addingTimeInterval(60 * 60))
    }

    private var dayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: day)
            ?? DateInterval(start: day, duration: 24 * 60 * 60)
    }

    private var currentTask: GTDTask? { model.task(withID: task.id) }

    private var valid: Bool {
        guard let currentTask, currentTask.workspaceID == model.selection.selectedWorkspaceID,
              TaskDayRules.canSchedule(currentTask, on: day, calendar: .current) else { return false }
        return end > start && start >= dayInterval.start && start < dayInterval.end && end <= dayInterval.end
    }

    private var hasConflict: Bool {
        guard end > start else { return false }
        let selection = TodayScheduleDragSelection(lane: .plan, start: start, end: end)
        return TodayScheduleConflictRules.planConflicts(
            with: selection,
            blocks: model.todayExecutionSnapshot(on: day).planBlocks
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("安排执行时段")
                    .font(.system(size: 14, weight: .semibold))
                Text(day.formatted(.dateTime.year().month(.defaultDigits).day(.defaultDigits).weekday(.wide)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ModernPalette.blue)
                Text(currentTask?.title ?? "任务已不存在")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(ModernPalette.railInk)
                    .lineLimit(2)
            }

            DatePicker("开始", selection: $start, in: dayInterval.start...dayInterval.end, displayedComponents: [.date, .hourAndMinute])
            DatePicker("结束", selection: $end, in: dayInterval.start...dayInterval.end, displayedComponents: [.date, .hourAndMinute])

            if !valid {
                Text("请选择当天有效的起止时间；已完成、跳过或移出的任务无法安排")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.red)
            } else if hasConflict {
                Label("与已有计划重叠，仍可安排；相同时段不会重复添加", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.red)
            }
            if let validationMessage {
                Text(validationMessage).font(.system(size: 10.5)).foregroundStyle(ModernPalette.red)
            }
            Text("只添加执行时段，保留原计划和截止时间。结束可设为次日 00:00。")
                .font(.system(size: 10.5))
                .foregroundStyle(ModernPalette.muted)

            HStack {
                Spacer()
                Button("取消", action: onSaved).keyboardShortcut(.cancelAction)
                Button("安排") {
                    guard valid, model.addExecutionSlot(taskID: task.id, start: start, end: end) != nil else {
                        validationMessage = "无法安排，请检查任务状态和时间后重试"
                        return
                    }
                    onSaved()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(16)
        .frame(width: 370)
    }
}

private struct TodayTaskList: View {
    let snapshot: TodayExecutionSnapshot
    let day: Date

    private var scheduledTasks: [GTDTask] {
        let ids = Set(snapshot.planBlocks.map(\.taskID))
        return snapshot.tasks.filter { task in
            ids.contains(task.id) && !snapshot.completedTasks.contains(where: { $0.id == task.id })
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !scheduledTasks.isEmpty {
                    TodayListSectionHeader(title: "已安排", count: scheduledTasks.count)
                    ForEach(scheduledTasks) { task in
                        TodayListTaskRow(task: task, day: day, snapshot: snapshot)
                    }
                }

                if !snapshot.drawerTasks.isEmpty {
                    TodayListSectionHeader(title: "待安排", count: snapshot.drawerTasks.count)
                    ForEach(snapshot.drawerTasks) { task in
                        TodayListTaskRow(task: task, day: day, snapshot: snapshot)
                    }
                }

                if !snapshot.completedTasks.isEmpty {
                    TodayListSectionHeader(title: "已完成", count: snapshot.completedTasks.count)
                    ForEach(snapshot.completedTasks) { task in
                        TodayListTaskRow(task: task, day: day, snapshot: snapshot)
                    }
                }

                if snapshot.tasks.isEmpty {
                    ContentUnavailableView(
                        "今天没有待办",
                        systemImage: "checkmark.circle",
                        description: Text("可在下方输入栏安排一项今天要做的任务")
                    )
                    .padding(.top, 90)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(ModernPalette.canvas)
    }
}

private struct TodayListSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ModernPalette.railInk)
            Text("\(count)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ModernPalette.line.opacity(0.68)).frame(height: 0.5)
        }
    }
}

private struct TodayListTaskRow: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask
    let day: Date
    let snapshot: TodayExecutionSnapshot
    @State private var showsScheduler = false

    private var completed: Bool {
        TodayExecutionProjection.isCompleted(task, on: day)
    }

    private var taskBlocks: [TodayPlanBlock] {
        snapshot.planBlocks.filter { $0.taskID == task.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
            Button {
                model.toggleTodayCompletion(taskID: task.id, on: day)
            } label: {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(completed ? ModernPalette.completion : ModernPalette.line)
                    .frame(width: 26, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(completed ? "重新打开 \(task.title)" : "完成 \(task.title)")

            Button {
                model.selectTask(task.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(task.title)
                            .font(.system(size: 13, weight: completed ? .regular : .medium))
                            .foregroundStyle(completed ? ModernPalette.muted : ModernPalette.ink)
                            .strikethrough(completed, color: ModernPalette.muted)
                            .lineLimit(1)
                        if TodayExecutionProjection.isMultiDayPlan(task) {
                            TodayIntentBadge(intent: task.planRangeIntent)
                        }
                        if TodayExecutionProjection.isDailyRecurring(task) {
                            TodaySmallBadge(title: "每天重复", tint: ModernPalette.green)
                        }
                    }

                    HStack(spacing: 8) {
                        if let block = taskBlocks.first {
                            Text(block.isPoint ? block.start.formatted(date: .omitted, time: .shortened) : todayTimeRange(start: block.start, end: block.end))
                                .foregroundStyle(ModernPalette.accent)
                        } else if task.plannedStart != nil {
                            Text(todayPlanRangeText(task))
                        }
                        TodayProjectLabel(task: task)
                        if let deadline = task.deadline {
                            Text(todayDeadlineText(deadline, isOverdue: deadline < .now))
                                .foregroundStyle(deadline < .now ? ModernPalette.red : ModernPalette.muted)
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !completed {
                Button {
                    showsScheduler = true
                } label: {
                    Image(systemName: taskBlocks.isEmpty ? "calendar.badge.plus" : "calendar.badge.clock")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.railInk)
                .help("安排另一个今日时段")
                .accessibilityLabel("为 \(task.title) 安排今日时段")
                .popover(isPresented: $showsScheduler, arrowEdge: .trailing) {
                    DayScheduleEditor(task: task, day: day) {
                        showsScheduler = false
                    }
                    .environment(model)
                }

                Button {
                    guard model.activeTimer == nil else {
                        model.notice = "请先结束当前计时"
                        return
                    }
                    model.startStopwatch(for: task)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.blue)
                .help("开始正计时")
                .accessibilityLabel("为 \(task.title) 开始正计时")
            }
        }
        .frame(minHeight: 58)
        ForEach(taskBlocks.filter { $0.id.source == .executionSlot }) { block in
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(todayTimeRange(start: block.start, end: block.end))
                Spacer()
                if let slotID = block.id.slotID {
                    Button { _ = model.removeExecutionSlot(taskID: task.id, slotID: slotID) } label: {
                        Image(systemName: "xmark.circle").frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("移除 \(task.title) 的整个执行时段")
                    .help("移除整个执行时段，保留任务计划和截止时间")
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(ModernPalette.accent)
            .padding(.leading, 36)
            .padding(.bottom, 5)
        }
        }
        .plannerTaskActions(taskID: task.id, scope: .day(day))
        .padding(.horizontal, 8)
        .background(
            model.isTaskSelected(task.id) ? ModernPalette.blue.opacity(0.055) : .clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay(alignment: .bottom) {
            Rectangle().fill(ModernPalette.line.opacity(0.48)).frame(height: 0.5)
        }
    }
}

private struct TodayVerticalSchedule: View {
    let snapshot: TodayExecutionSnapshot
    let day: Date

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 64)
                Text("计划")
                    .frame(maxWidth: .infinity)
                Divider()
                Text("实际")
                    .frame(maxWidth: .infinity)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(ModernPalette.ink)
            .frame(height: 34)
            .overlay(alignment: .bottom) {
                Rectangle().fill(ModernPalette.line.opacity(0.62)).frame(height: 0.5)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        TodayTimelineCanvas(snapshot: snapshot, day: day)

                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                Color.clear
                                    .frame(width: 1, height: 64)
                                    .id("hour-\(hour)")
                            }
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .task {
                    do {
                        try await Task.sleep(for: .milliseconds(120))
                    } catch {
                        return
                    }
                    proxy.scrollTo("hour-8", anchor: .top)
                }
            }
        }
        .background(ModernPalette.canvas)
    }
}

private struct TodaySchedulePendingSelection: Identifiable {
    let selection: TodayScheduleDragSelection
    let anchor: CGPoint

    var id: UUID { selection.id }
}

private struct TodayTimelineCanvas: View {
    @Environment(AppModel.self) private var model: AppModel
    let snapshot: TodayExecutionSnapshot
    let day: Date

    @State private var dragSelection: TodayScheduleDragSelection?
    @State private var pendingSelection: TodaySchedulePendingSelection?

    private let startHour = 0
    private let endHour = 24
    private let hourHeight: CGFloat = 64
    private let axisWidth: CGFloat = 64

    private var totalHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }
    private var visibleInterval: DateInterval {
        DayTimelineLayout.visibleInterval(day: day, startHour: startHour, endHour: endHour)
            ?? DateInterval(start: Calendar.current.startOfDay(for: day), duration: 24 * 3_600)
    }


    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            timelineAxis
                .frame(width: axisWidth, height: totalHeight, alignment: .top)

            GeometryReader { proxy in
                let laneWidth = max(1, (proxy.size.width - 1) / 2)
                ZStack(alignment: .topLeading) {
                    timelineGrid(width: proxy.size.width, laneWidth: laneWidth)

                    dragSurface(for: .plan, laneWidth: laneWidth)
                    dragSurface(for: .actual, laneWidth: laneWidth)
                        .offset(x: laneWidth)

                    ForEach(snapshot.planBlocks) { block in
                        if let clipped = DayTimelineLayout.clipped(start: block.start, end: block.end, to: visibleInterval) {
                            TodayPlanBlockView(block: block)
                                .frame(width: max(80, laneWidth - 18), height: blockHeight(start: clipped.start, end: clipped.end))
                                .offset(x: 8, y: yOffset(for: clipped.start))
                        }
                    }

                    ForEach(snapshot.actualEntries) { entry in
                        if let clipped = DayTimelineLayout.clipped(start: entry.startedAt, end: entry.endedAt, to: visibleInterval) {
                            TodayActualBlockView(entry: entry)
                                .frame(width: max(80, laneWidth - 18), height: blockHeight(start: clipped.start, end: clipped.end))
                                .offset(x: laneWidth + 10, y: yOffset(for: clipped.start))
                        }
                    }

                    ForEach(snapshot.deadlineTasks) { task in
                        if let deadline = task.deadline {
                            TodayDeadlineMarker(task: task)
                                .offset(x: 10, y: yOffset(for: deadline) - 10)
                        }
                    }

                    if let selection = dragSelection ?? pendingSelection?.selection {
                        TodayScheduleDragPreview(selection: selection)
                            .frame(
                                width: max(80, laneWidth - 18),
                                height: selectionHeight(selection)
                            )
                            .offset(
                                x: selection.lane == .plan ? 8 : laneWidth + 10,
                                y: yOffset(for: selection.start)
                            )
                            .zIndex(30)
                    }

                    schedulePopoverAnchor(
                        laneWidth: laneWidth,
                        totalWidth: proxy.size.width
                    )

                    TodayLiveTimelineOverlay(
                        day: day,
                        startHour: startHour,
                        endHour: endHour,
                        hourHeight: hourHeight,
                        laneWidth: laneWidth,
                        totalWidth: proxy.size.width
                    )
                    .environment(model)
                    .allowsHitTesting(true)
                    .zIndex(20)
                }
            }
            .frame(height: totalHeight)
        }
        .padding(.trailing, 14)
        .frame(height: totalHeight)
        .onExitCommand {
            dragSelection = nil
            pendingSelection = nil
        }
    }

    private var timelineAxis: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(startHour...endHour, id: \.self) { hour in
                Text(String(format: "%02d:00", hour % 24))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(ModernPalette.muted)
                    .padding(.trailing, 10)
                    .offset(y: CGFloat(hour - startHour) * hourHeight - 7)
            }
        }
    }

    private func timelineGrid(width: CGFloat, laneWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(startHour...endHour, id: \.self) { hour in
                Rectangle()
                    .fill(ModernPalette.line.opacity(hour.isMultiple(of: 2) ? 0.65 : 0.38))
                    .frame(width: width, height: 0.5)
                    .offset(y: CGFloat(hour - startHour) * hourHeight)
            }
            Rectangle()
                .fill(ModernPalette.line.opacity(0.55))
                .frame(width: 0.5, height: totalHeight)
                .offset(x: laneWidth)
        }
    }

    private func yOffset(for date: Date) -> CGFloat {
        DayTimelineLayout.yOffset(for: date, in: visibleInterval, startHour: startHour, endHour: endHour, hourHeight: hourHeight)
    }

    private func blockHeight(start: Date, end: Date) -> CGFloat {
        max(24, yOffset(for: end) - yOffset(for: start) - 3)
    }

    private func selectionHeight(_ selection: TodayScheduleDragSelection) -> CGFloat {
        blockHeight(start: selection.start, end: selection.end)
    }

    private func dragSurface(for lane: TodayScheduleLane, laneWidth: CGFloat) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: laneWidth, height: totalHeight)
            .contentShape(Rectangle())
            .gesture(dragGesture(for: lane, laneWidth: laneWidth))
            .accessibilityLabel("在\(lane.title)轨拖拽创建时间段")
    }

    private func dragGesture(for lane: TodayScheduleLane, laneWidth: CGFloat) -> some Gesture {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .local
        )
            .onChanged { value in
                dragSelection = dragSelection(
                    lane: lane,
                    startY: value.startLocation.y,
                    currentY: value.location.y,
                    id: dragSelection?.id
                )
            }
            .onEnded { value in
                let selection = dragSelection(
                    lane: lane,
                    startY: value.startLocation.y,
                    currentY: value.location.y,
                    id: dragSelection?.id
                )
                pendingSelection = TodaySchedulePendingSelection(
                    selection: selection,
                    anchor: TodayScheduleDragRules.popoverAnchor(
                        for: lane,
                        location: value.location,
                        laneWidth: laneWidth,
                        totalHeight: totalHeight
                    )
                )
                dragSelection = nil
            }
    }

    private func dragSelection(
        lane: TodayScheduleLane,
        startY: CGFloat,
        currentY: CGFloat,
        id: UUID?
    ) -> TodayScheduleDragSelection {
        TodayScheduleDragRules.selection(
            lane: lane,
            day: day,
            startY: startY,
            currentY: currentY,
            startHour: startHour,
            endHour: endHour,
            hourHeight: hourHeight,
            fineSnap: NSEvent.modifierFlags.contains(.option),
            id: id ?? UUID()
        )
    }

    private func schedulePopoverAnchor(
        laneWidth: CGFloat,
        totalWidth: CGFloat
    ) -> some View {
        let fallback = CGPoint(x: laneWidth / 2, y: hourHeight * 3)
        let anchor = pendingSelection?.anchor ?? fallback

        return TimelinePopoverPointLayout(point: anchor) {
            Circle()
                .fill(ModernPalette.ink.opacity(0.001))
                .frame(width: 2, height: 2)
                .popover(
                    item: $pendingSelection,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .top
                ) { pending in
                    TodayScheduleSelectionPopover(
                        selection: pending.selection,
                        snapshot: snapshot,
                        day: day,
                        preferredTaskID: model.selectedTask?.id,
                        onDismiss: { pendingSelection = nil }
                    )
                    .environment(model)
                }
        }
            .frame(width: totalWidth, height: totalHeight)
            .accessibilityHidden(true)
            .zIndex(40)
    }
}

private struct TodayScheduleDragPreview: View {
    let selection: TodayScheduleDragSelection

    private var tint: Color {
        selection.lane == .plan ? ModernPalette.blue : ModernPalette.green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(selection.lane == .plan ? "安排计划" : "记录实际 / 番茄")
                .font(.system(size: 10.5, weight: .semibold))
            Text(todayTimeRange(start: selection.start, end: selection.end))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tint.opacity(0.9), style: StrokeStyle(lineWidth: 1.25, dash: [5, 3]))
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(selection.lane.title)时间段，\(todayTimeRange(start: selection.start, end: selection.end))")
    }
}

private struct TodayLiveTimelineOverlay: View {
    @Environment(AppModel.self) private var model: AppModel
    let day: Date
    let startHour: Int
    let endHour: Int
    let hourHeight: CGFloat
    let laneWidth: CGFloat
    let totalWidth: CGFloat

    private var totalHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }
    private var dayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: day)
            ?? DateInterval(start: day, duration: 24 * 60 * 60)
    }

    var body: some View {
        SwiftUI.TimelineView(SwiftUI.PeriodicTimelineSchedule(from: .now, by: 1)) { context in
            ZStack(alignment: .topLeading) {
                if Calendar.current.isDateInToday(day), TaskDayRules.contains(context.date, in: dayInterval) {
                    Rectangle()
                        .fill(ModernPalette.blue)
                        .frame(width: totalWidth, height: 1.5)
                        .offset(y: yOffset(for: context.date))
                        .overlay(alignment: .leading) {
                            Circle()
                                .fill(ModernPalette.blue)
                                .frame(width: 7, height: 7)
                                .offset(x: -3)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                if let timer = visibleTimer {
                    activeTimerContent(timer: timer, now: context.date)
                }
            }
            .frame(width: totalWidth, height: totalHeight, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func activeTimerContent(timer: ActiveTimer, now: Date) -> some View {
        let elapsed = model.timerElapsed(at: now)
        if let wallClock = ActiveTimerDisplayRules.wallClockInterval(for: timer, now: now),
           let clipped = DayTimelineLayout.clipped(start: wallClock.start, end: wallClock.end, to: dayInterval) {
            let clippedStart = clipped.start
            let clippedEnd = clipped.end

            if let targetDate = ActiveTimerDisplayRules.targetDate(for: timer, elapsed: elapsed, now: now) {
                if TaskDayRules.contains(targetDate, in: dayInterval) {
                    Rectangle()
                        .stroke(
                            ModernPalette.red.opacity(0.8),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                        .frame(width: max(80, laneWidth - 18), height: 1)
                        .offset(x: laneWidth + 10, y: yOffset(for: targetDate))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }

            TodayActiveTimerBlockView(timer: timer, elapsed: elapsed)
                .frame(
                    width: max(80, laneWidth - 18),
                    height: max(52, blockHeight(start: clippedStart, end: clippedEnd))
                )
                .offset(x: laneWidth + 10, y: yOffset(for: clippedStart))
        }
    }

    private var visibleTimer: ActiveTimer? {
        guard let timer = model.activeTimer,
              (timer.workspaceID ?? model.selection.selectedWorkspaceID) == model.selection.selectedWorkspaceID else {
            return nil
        }
        return timer
    }

    private func yOffset(for date: Date) -> CGFloat {
        DayTimelineLayout.yOffset(for: date, in: dayInterval, startHour: startHour, endHour: endHour, hourHeight: hourHeight)
    }

    private func blockHeight(start: Date, end: Date) -> CGFloat {
        max(24, yOffset(for: end) - yOffset(for: start) - 3)
    }
}

private struct TodayActiveTimerBlockView: View {
    @Environment(AppModel.self) private var model: AppModel
    let timer: ActiveTimer
    let elapsed: TimeInterval

    private var tint: Color {
        timer.mode == .pomodoro ? ModernPalette.red : ModernPalette.blue
    }

    private var clockText: String {
        if timer.mode == .pomodoro {
            return PomodoroClockState.make(
                targetSeconds: timer.targetSeconds ?? 25 * 60,
                elapsed: elapsed
            ).text
        }
        return "已专注 \(todayCompactDuration(elapsed))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: timer.mode == .pomodoro ? "timer" : "stopwatch")
                    .font(.system(size: 9.5, weight: .semibold))
                Text(timer.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                if timer.pausedAt != nil {
                    Text("已暂停")
                        .font(.system(size: 9, weight: .semibold))
                }
            }

            HStack(spacing: 8) {
                Text(clockText)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Button {
                    timer.pausedAt == nil ? model.pauseTimer() : model.resumeTimer()
                } label: {
                    Image(systemName: timer.pausedAt == nil ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.plain)
                .help(timer.pausedAt == nil ? "暂停" : "继续")
                Button {
                    _ = model.stopTimer()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.plain)
                .help("停止并记录")
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tint.opacity(0.45), lineWidth: 0.9)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("正在\(timer.mode == .pomodoro ? "番茄专注" : "正计时")，\(timer.title)，\(clockText)")
    }
}

private struct TodayScheduleSelectionPopover: View {
    let selection: TodayScheduleDragSelection
    let snapshot: TodayExecutionSnapshot
    let day: Date
    let preferredTaskID: UUID?
    let onDismiss: () -> Void

    var body: some View {
        switch selection.lane {
        case .plan:
            TodayPlanSelectionPopover(
                selection: selection,
                snapshot: snapshot,
                preferredTaskID: preferredTaskID,
                onDismiss: onDismiss
            )
        case .actual:
            TodayActualSelectionPopover(
                selection: selection,
                snapshot: snapshot,
                preferredTaskID: preferredTaskID,
                onDismiss: onDismiss
            )
        }
    }
}

private struct TodayPlanSelectionPopover: View {
    @Environment(AppModel.self) private var model: AppModel
    let selection: TodayScheduleDragSelection
    let snapshot: TodayExecutionSnapshot
    let preferredTaskID: UUID?
    let onDismiss: () -> Void

    @State private var selectedTaskID: UUID?
    @State private var validationMessage: String?

    init(
        selection: TodayScheduleDragSelection,
        snapshot: TodayExecutionSnapshot,
        preferredTaskID: UUID?,
        onDismiss: @escaping () -> Void
    ) {
        self.selection = selection
        self.snapshot = snapshot
        self.preferredTaskID = preferredTaskID
        self.onDismiss = onDismiss
        let candidates = TodayScheduleTaskCandidates.make(
            snapshot: snapshot,
            selectedTaskID: preferredTaskID
        )
        _selectedTaskID = State(initialValue: candidates.first?.id)
    }

    private var candidates: [GTDTask] {
        TodayScheduleTaskCandidates.make(snapshot: snapshot, selectedTaskID: preferredTaskID)
    }

    private var hasPlanConflict: Bool {
        TodayScheduleConflictRules.planConflicts(
            with: selection, blocks: model.todayExecutionSnapshot(on: snapshot.day).planBlocks
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TodaySchedulePopoverHeader(
                title: "安排今日执行时段",
                subtitle: todayTimeRange(start: selection.start, end: selection.end),
                icon: "calendar.badge.plus",
                tint: ModernPalette.blue
            )

            if hasPlanConflict {
                Label("这个时段与已有计划重叠，仍可继续安排", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ModernPalette.red)
            }

            Text("选择今天的任务")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(ModernPalette.muted)

            TodayScheduleTaskChoiceList(
                candidates: candidates,
                selectedTaskID: $selectedTaskID
            )

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ModernPalette.red)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("取消", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Button("安排时段", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedTaskID == nil)
            }
        }
        .padding(16)
        .frame(width: 390)
    }

    private func save() {
        guard let selectedTaskID else {
            validationMessage = "请选择一项今天的任务"
            return
        }
        guard model.addExecutionSlot(
            taskID: selectedTaskID,
            start: selection.start,
            end: selection.end
        ) != nil else {
            validationMessage = "无法安排这个执行时段"
            return
        }
        onDismiss()
    }
}

private struct TodayActualSelectionPopover: View {
    @Environment(AppModel.self) private var model: AppModel
    let selection: TodayScheduleDragSelection
    let snapshot: TodayExecutionSnapshot
    let preferredTaskID: UUID?
    let onDismiss: () -> Void

    @State private var action: TodayActualDraftAction
    @State private var selectedTaskID: UUID?
    @State private var validationMessage: String?

    init(
        selection: TodayScheduleDragSelection,
        snapshot: TodayExecutionSnapshot,
        preferredTaskID: UUID?,
        onDismiss: @escaping () -> Void
    ) {
        self.selection = selection
        self.snapshot = snapshot
        self.preferredTaskID = preferredTaskID
        self.onDismiss = onDismiss
        let candidates = TodayScheduleTaskCandidates.make(
            snapshot: snapshot,
            selectedTaskID: preferredTaskID
        )
        _action = State(initialValue: TodayActualDraftAction.defaultAction(for: selection.interval))
        _selectedTaskID = State(initialValue: candidates.first?.id)
    }

    private var candidates: [GTDTask] {
        TodayScheduleTaskCandidates.make(snapshot: snapshot, selectedTaskID: preferredTaskID)
    }

    private var normalizedPomodoroDuration: TimeInterval {
        model.normalizedPomodoroDuration(selection.duration)
    }

    private var manualValidationMessage: String? {
        if selection.end > Date.now {
            return "补录实际的结束时间不能晚于现在"
        }
        if model.hasTimeEntryConflict(
            workspaceID: model.selection.selectedWorkspaceID,
            startedAt: selection.start,
            endedAt: selection.end
        ) {
            return "这个时段与已有实际记录或当前计时重叠"
        }
        return nil
    }

    private var primaryDisabled: Bool {
        if selectedTaskID == nil { return true }
        switch action {
        case .manual:
            return manualValidationMessage != nil
        case .pomodoro:
            return model.activeTimer != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TodaySchedulePopoverHeader(
                title: "使用实际轨时间段",
                subtitle: todayTimeRange(start: selection.start, end: selection.end),
                icon: "clock.badge.checkmark",
                tint: ModernPalette.green
            )

            Picker("操作", selection: $action) {
                ForEach(TodayActualDraftAction.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: action) {
                validationMessage = nil
            }

            actionExplanation

            Text("选择今天的任务")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(ModernPalette.muted)

            TodayScheduleTaskChoiceList(
                candidates: candidates,
                selectedTaskID: $selectedTaskID
            )

            if let message = validationMessage ?? (action == .manual ? manualValidationMessage : nil) {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ModernPalette.red)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("取消", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Button(action.title, action: commit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(primaryDisabled)
            }
        }
        .padding(16)
        .frame(width: 390)
    }

    @ViewBuilder
    private var actionExplanation: some View {
        switch action {
        case .manual:
            Text("按拖出的具体起止时间保存，并明确标记为“手动补录”。")
                .font(.system(size: 10.5))
                .foregroundStyle(ModernPalette.muted)
        case .pomodoro:
            VStack(alignment: .leading, spacing: 4) {
                Text("以 \(Int(normalizedPomodoroDuration / 60)) 分钟从现在开始")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                Text("到达目标后不会自动停止；超时继续计入专注，直到你主动停止。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.muted)
                if model.activeTimer != nil {
                    Text("当前已有计时，结束后才能开始新的番茄钟。")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(ModernPalette.red)
                }
            }
        }
    }

    private func commit() {
        guard let selectedTaskID,
              let task = model.task(withID: selectedTaskID) else {
            validationMessage = "请选择一项今天的任务"
            return
        }

        switch action {
        case .manual:
            guard manualValidationMessage == nil else { return }
            guard model.addTimeEntry(
                workspaceID: model.selection.selectedWorkspaceID,
                taskID: task.id,
                startedAt: selection.start,
                endedAt: selection.end,
                source: .manual
            ) != nil else {
                validationMessage = "无法保存；请检查是否与已有实际记录重叠"
                return
            }
        case .pomodoro:
            guard model.activeTimer == nil else {
                validationMessage = "请先结束当前计时"
                return
            }
            model.startPomodoro(for: task, duration: normalizedPomodoroDuration)
        }
        onDismiss()
    }
}

private struct TodaySchedulePopoverHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(ModernPalette.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TodayScheduleTaskChoiceList: View {
    @Environment(AppModel.self) private var model: AppModel
    let candidates: [GTDTask]
    @Binding var selectedTaskID: UUID?

    var body: some View {
        if candidates.isEmpty {
            ContentUnavailableView(
                "今天没有可选择的任务",
                systemImage: "checkmark.circle",
                description: Text("可先在今日输入栏创建或安排任务")
            )
            .frame(height: 120)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(candidates) { task in
                        Button {
                            selectedTaskID = task.id
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: selectedTaskID == task.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedTaskID == task.id ? ModernPalette.blue : ModernPalette.line)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.system(size: 11.5, weight: selectedTaskID == task.id ? .semibold : .medium))
                                        .foregroundStyle(ModernPalette.ink)
                                        .lineLimit(1)
                                    if let project = model.project(for: task) {
                                        Text(project.name)
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(ModernPalette.muted)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 38)
                            .background(
                                selectedTaskID == task.id ? ModernPalette.blue.opacity(0.07) : .clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedTaskID == task.id ? .isSelected : [])
                    }
                }
            }
            .frame(maxHeight: 178)
            .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ModernPalette.line.opacity(0.62), lineWidth: 0.75)
            }
        }
    }
}

private struct TodayPlanBlockView: View {
    @Environment(AppModel.self) private var model: AppModel
    let block: TodayPlanBlock

    private var task: GTDTask? { model.task(withID: block.taskID) }
    private var tint: Color {
        task.flatMap { model.project(for: $0) }.map { Color(hex: $0.colorHex) } ?? ModernPalette.blue
    }

    var body: some View {
        Button {
            model.selectTask(block.taskID)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                    .lineLimit(1)
                Text(block.isPoint ? block.start.formatted(date: .omitted, time: .shortened) : todayTimeRange(start: block.start, end: block.end))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(ModernPalette.railInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: 3)
                    .padding(.vertical, 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if block.id.source == .executionSlot, let slotID = block.id.slotID {
                Button("移除整个执行时段", role: .destructive) {
                    _ = model.removeExecutionSlot(taskID: block.taskID, slotID: slotID)
                }
            }
        }
        .accessibilityLabel("计划，\(block.title)，\(todayTimeRange(start: block.start, end: block.end))")
    }
}

private struct TodayActualBlockView: View {
    @Environment(AppModel.self) private var model: AppModel
    let entry: TimeEntry
    @State private var showsEditor = false
    @State private var confirmsDeletion = false

    var body: some View {
        Button {
            showsEditor = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                    .lineLimit(1)
                Text("\(todayTimeRange(start: entry.startedAt, end: entry.endedAt)) · \(entry.source.title)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(ModernPalette.railInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ModernPalette.blue.opacity(0.095), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(ModernPalette.blue)
                    .frame(width: 4)
                    .padding(.vertical, 4)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsEditor) {
            if let canonical = model.timeEntry(withID: entry.id) {
                FocusEntryEditorSheet(entry: canonical, workspaceID: canonical.workspaceID, defaultDate: canonical.startedAt)
                    .environment(model)
                    .frame(width: 560, height: 560)
            }
        }
        .contextMenu {
            Button("编辑实际记录") { showsEditor = true }
            if let taskID = entry.taskID { Button("查看任务") { model.selectTask(taskID) } }
            Button("删除实际记录", role: .destructive) { confirmsDeletion = true }
        }
        .confirmationDialog("删除这条实际专注记录？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("删除", role: .destructive) { _ = model.deleteTimeEntry(withID: entry.id) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除完整记录，不会更改任务计划或截止时间")
        }
        .help("点击编辑完整实际记录；右键可删除")
        .accessibilityLabel("实际专注，\(entry.title)，\(todayTimeRange(start: entry.startedAt, end: entry.endedAt))")
    }
}

private struct TodayDeadlineMarker: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask

    var body: some View {
        Button {
            model.selectTask(task.id)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(task.deadline?.formatted(date: .omitted, time: .shortened) ?? "")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(ModernPalette.red)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("截止时间，\(task.title)")
    }
}

struct TodayContextPane: View {
    @Environment(AppModel.self) private var model: AppModel
    @FocusState.Binding var inspectorNoteFocused: Bool

    var body: some View {
        if model.selectedTask != nil {
            ModernInspectorPane(inspectorNoteFocused: $inspectorNoteFocused)
        } else {
            TodayOverviewPane(snapshot: model.todayExecutionSnapshot())
        }
    }
}

private struct TodayOverviewPane: View {
    let snapshot: TodayExecutionSnapshot

    private var progress: Double {
        guard snapshot.totalCount > 0 else { return 0 }
        return min(1, max(0, Double(snapshot.completedCount) / Double(snapshot.totalCount)))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("今日概览")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)

                ZStack {
                    Circle().stroke(ModernPalette.line.opacity(0.62), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(ModernPalette.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text("\(snapshot.completedCount)/\(snapshot.totalCount)")
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("已完成")
                            .font(.system(size: 10.5))
                            .foregroundStyle(ModernPalette.muted)
                    }
                }
                .frame(width: 78, height: 78)
                .padding(.top, 18)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("今日完成 \(snapshot.completedCount) 项，共 \(snapshot.totalCount) 项")

                HStack(spacing: 0) {
                    TodayOverviewStat(title: "剩余", value: snapshot.remainingCount, tint: ModernPalette.blue)
                    Divider().frame(height: 54)
                    TodayOverviewStat(title: "逾期", value: snapshot.overdueCount, tint: ModernPalette.red)
                    Divider().frame(height: 54)
                    TodayOverviewStat(title: "完成", value: snapshot.completedCount, tint: ModernPalette.ink)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Divider().padding(.vertical, 22)

                TodayTimeInvestmentSection(snapshot: snapshot)
                    .padding(.horizontal, 24)

                Divider().padding(.vertical, 22)

                VStack(spacing: 15) {
                    TodayLegendRow(color: ModernPalette.red, title: "已逾期", value: snapshot.overdueCount)
                    TodayLegendRow(color: ModernPalette.blue, title: "待安排", value: snapshot.waitingCount)
                    TodayLegendRow(color: ModernPalette.line, title: "已完成", value: snapshot.completedCount)
                }
                .padding(.horizontal, 26)

                Text("跨日范围不换算成全天工时；计划与实际专注分别统计。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.muted)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
            }
        }
        .background(ModernPalette.panel)
    }
}

private struct TodayOverviewStat: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
            Text("\(value)")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct TodayTimeInvestmentSection: View {
    let snapshot: TodayExecutionSnapshot

    private var maximum: TimeInterval {
        max(60, snapshot.plannedDuration, snapshot.actualDuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("时间投入")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ModernPalette.muted)

            timeRow(
                title: "计划时间",
                duration: snapshot.plannedDuration,
                tint: ModernPalette.railInk
            )
            timeRow(
                title: "实际专注",
                duration: snapshot.actualDuration,
                tint: ModernPalette.blue
            )

            Text("实际专注来自正计时、番茄钟与手动补录，不含计划时间")
                .font(.system(size: 10))
                .foregroundStyle(ModernPalette.muted)
            if let interval = snapshot.dayInterval,
               snapshot.actualEntries.contains(where: {
                   $0.activeSeconds != nil && ($0.startedAt < interval.start || $0.endedAt > interval.end)
               }) {
                Text("跨日计时按覆盖时长比例估算每日专注，原始记录保持完整")
                    .font(.system(size: 10))
                    .foregroundStyle(ModernPalette.muted)
            }
        }
    }

    private func timeRow(title: String, duration: TimeInterval, tint: Color) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 11.5, weight: title == "实际专注" ? .semibold : .medium))
                    .foregroundStyle(title == "实际专注" ? ModernPalette.blue : ModernPalette.ink)
                Spacer()
                Text(todayDurationText(duration))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tint)
            }
            GeometryReader { proxy in
                Capsule().fill(ModernPalette.line.opacity(0.42))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * min(1, max(0, duration / maximum)))
                    }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(todayDurationText(duration))")
    }
}

private struct TodayLegendRow: View {
    let color: Color
    let title: String
    let value: Int

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
            Spacer()
            Text("\(value)")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(title == "已完成" ? ModernPalette.ink : color)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TodayProjectLabel: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask

    var body: some View {
        if let project = model.project(for: task) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(hex: project.colorHex))
                    .frame(width: 7, height: 7)
                Text(project.name).lineLimit(1)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(ModernPalette.muted)
        }
    }
}

private struct TodayIntentBadge: View {
    let intent: TaskPlanRangeIntent

    var body: some View {
        TodaySmallBadge(
            title: intent.title,
            tint: intent == .progress ? ModernPalette.blue : ModernPalette.green
        )
        .help(intent.explanation)
    }
}

private struct TodaySmallBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .frame(height: 19)
            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private func todayPlanRangeText(_ task: GTDTask) -> String {
    guard let start = task.plannedStart else { return "未设置计划范围" }
    let calendar = Calendar.current
    if task.plannedPrecision == .minute {
        guard let end = task.plannedEnd else {
            return start.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
        return "\(start.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))) – \(end.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))"
    }

    let startText = start.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
    guard let storedEnd = task.plannedEnd else { return startText }
    let displayEnd = storedEnd
    guard !calendar.isDate(start, inSameDayAs: displayEnd) else { return startText }
    return "\(startText) – \(displayEnd.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits)))"
}

private func todayDeadlineText(_ deadline: Date, isOverdue: Bool) -> String {
    if isOverdue {
        return "\(deadline.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))) 已截止"
    }
    if Calendar.current.isDateInToday(deadline) {
        return deadline.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) + " 截止"
    }
    return deadline.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits)) + " 截止"
}

private func todayTimeRange(start: Date, end: Date) -> String {
    "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
}

private func todayDurationText(_ duration: TimeInterval) -> String {
    let totalMinutes = max(0, Int((duration / 60).rounded()))
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours == 0 { return "\(minutes)分钟" }
    if minutes == 0 { return "\(hours)小时" }
    return "\(hours)小时\(minutes)分"
}

private func todayCompactDuration(_ duration: TimeInterval) -> String {
    let total = max(0, Int(duration.rounded(.down)))
    let hours = total / 3_600
    let minutes = (total % 3_600) / 60
    let seconds = total % 60
    if hours > 0 {
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}
