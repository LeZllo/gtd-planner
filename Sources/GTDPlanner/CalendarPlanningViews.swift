import SwiftUI

/// Calendar is a dated planning surface. It shares task identity, scheduling,
/// and the canonical inspector with Today without importing Today's backlog.
struct CalendarPlanningWorkspace: View {
    @Environment(AppModel.self) private var model: AppModel
    let now: Date
    @FocusState.Binding var inspectorNoteFocused: Bool
    @State private var visibleMonth: Date?
    @State private var query = ""
    @State private var showsTaskPicker = false
    @State private var showsNewTaskEditor = false

    private var selectedDay: Date {
        Calendar.current.startOfDay(for: model.selection.calendarDay ?? now)
    }

    private var month: Date { visibleMonth ?? selectedDay }

    var body: some View {
        Group {
            if let snapshot = model.calendarPlanningSnapshot(month: month, now: now) {
                workspace(snapshot)
            } else {
                ContentUnavailableView("无法显示这个月份", systemImage: "calendar",
                                       description: Text("请返回今天重新选择日期"))
                    .overlay(alignment: .bottom) {
                        Button("返回今天", action: returnToToday).padding(30)
                    }
            }
        }
        .sheet(isPresented: $showsTaskPicker) {
            DayPlanningTaskPicker(day: selectedDay, now: now) { showsTaskPicker = false }
                .environment(model)
        }
        .sheet(isPresented: $showsNewTaskEditor) {
            TaskEditor(task: nil, initialPlannedDay: selectedDay)
                .environment(model)
        }
        .onAppear {
            model.selection.calendarDay = selectedDay
            visibleMonth = Calendar.current.dateInterval(of: .month, for: selectedDay)?.start
        }
        .onChange(of: selectedDay) { _, day in
            guard !Calendar.current.isDate(day, equalTo: month, toGranularity: .month) else { return }
            visibleMonth = Calendar.current.dateInterval(of: .month, for: day)?.start
        }
        .onChange(of: model.selection.selectedWorkspaceID) { _, _ in
            query = ""
            showsTaskPicker = false
            showsNewTaskEditor = false
            model.clearSelectedTask()
            returnToToday()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("日历计划面板")
    }

    private func workspace(_ snapshot: CalendarPlanningSnapshot) -> some View {
        let day = snapshot.day(on: selectedDay)
            ?? model.todayExecutionSnapshot(on: selectedDay, now: now, includeOverdueBacklog: false)
        let matchingTasks = day.tasks.filter(matchesSearch)
        let visibleIDs = Set(matchingTasks.map(\.id))
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                header(snapshot)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        monthGrid(snapshot)
                        selectedDayHeader(day)
                        searchBar
                        dayTaskList(day, tasks: matchingTasks)
                        Text("格内统计属于当天的计划、截止与完成记录。仅已逾期的积压任务不会自动铺入日历，可用“安排任务”指定日期。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(ModernPalette.muted)
                            .lineSpacing(4)
                    }
                    .padding(18)
                }
            }
            .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
            .background(ModernPalette.canvas)
            Divider()
            inspector(day)
                .frame(width: 390)
        }
        .onChange(of: visibleIDs, initial: true) { _, ids in
            if let selectedID = model.selection.taskSelection?.taskID, !ids.contains(selectedID) {
                model.clearSelectedTask()
            }
        }
    }

    private func header(_ snapshot: CalendarPlanningSnapshot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("日历")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                Text("本月 \(snapshot.taskCount) 项任务 · \(snapshot.deadlineCount) 项待截止")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ModernPalette.muted)
                    .help("任务数按任务去重；跨日与每日重复任务会出现在各自日期中")
            }
            Spacer()
            HStack(spacing: 10) {
                Button(action: { moveMonth(-1) }) {
                    Image(systemName: "chevron.left").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("上个月")
                Text(snapshot.grid.month.formatted(.dateTime.year().month(.wide)))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                    .frame(minWidth: 100)
                    .accessibilityAddTraits(.isHeader)
                Button(action: { moveMonth(1) }) {
                    Image(systemName: "chevron.right").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("下个月")
                Button("今天", action: returnToToday)
                    .buttonStyle(.plain)
                    .help("返回今天并选择今天")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .plannerControlSurface(in: Capsule())
        }
        .foregroundStyle(ModernPalette.railInk)
        .padding(.horizontal, 22)
        .frame(height: 82)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ModernPalette.line.opacity(0.58)).frame(height: 0.5)
        }
    }

    private func monthGrid(_ snapshot: CalendarPlanningSnapshot) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(CalendarMonthGrid.weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(ModernPalette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 7), spacing: 6) {
                ForEach(snapshot.grid.days) { gridDay in
                    CalendarDateCell(
                        gridDay: gridDay,
                        snapshot: snapshot.day(on: gridDay.date),
                        isSelected: Calendar.current.isDate(gridDay.date, inSameDayAs: selectedDay),
                        isToday: Calendar.current.isDate(gridDay.date, inSameDayAs: now)
                    ) { selectDay(gridDay.date) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(snapshot.grid.month.formatted(.dateTime.year().month(.wide)))
    }

    private func selectedDayHeader(_ day: TodayExecutionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(calendarPlanningDate(day.day))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ModernPalette.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(day.totalCount) 项 · \(day.completedCount) 项已完成 · \(day.planBlocks.count) 个具体时段")
                        .font(.system(size: 11))
                        .foregroundStyle(ModernPalette.muted)
                }
                Spacer()
                Button { query = ""; showsTaskPicker = true } label: {
                    Label("安排任务", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
                Button { query = ""; showsNewTaskEditor = true } label: {
                    Label("新建任务", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(ModernPalette.accent)
                .accessibilityLabel("在 \(calendarPlanningDate(day.day)) 新建任务")
            }
            Text(completionExplanation(for: day.day))
                .font(.system(size: 10.5))
                .foregroundStyle(ModernPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(ModernPalette.muted)
            TextField("搜索所选日期的任务、项目、标签或笔记", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(ModernPalette.muted)
                    .accessibilityLabel("清除日历任务搜索")
            }
        }
        .font(.system(size: 12))
        .padding(11)
        .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 8))
    }

    private func dayTaskList(_ day: TodayExecutionSnapshot, tasks: [GTDTask]) -> some View {
        VStack(spacing: 0) {
            if tasks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: query.isEmpty ? "calendar.badge.plus" : "magnifyingglass")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(ModernPalette.muted)
                    Text(query.isEmpty ? "这一天还没有任务" : "所选日期没有匹配的任务")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ModernPalette.ink)
                    Text(query.isEmpty ? "新建任务，或从当前工作区安排已有任务到具体时段" : "清除搜索，或选择另一个日期")
                        .font(.system(size: 11))
                        .foregroundStyle(ModernPalette.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(28)
            } else {
                ForEach(tasks) { task in
                    CalendarPlanningTaskRow(task: task, snapshot: day, now: now)
                }
            }
        }
        .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).stroke(ModernPalette.line.opacity(0.65), lineWidth: 0.75)
        }
    }

    @ViewBuilder
    private func inspector(_ day: TodayExecutionSnapshot) -> some View {
        if model.selectedTask != nil {
            VStack(spacing: 0) {
                Text("详情中的状态修改作用于整项任务；计时从现在开始，不会补记为所选日期的实际用时")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.muted)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(ModernPalette.panel)
                Divider()
                ModernInspectorPane(inspectorNoteFocused: $inspectorNoteFocused)
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                Label("当天计划", systemImage: "calendar")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                Text(calendarPlanningDate(day.day))
                    .font(.system(size: 12))
                    .foregroundStyle(ModernPalette.muted)
                summaryValue("待办任务", value: "\(day.remainingCount)")
                summaryValue("已完成", value: "\(day.completedCount)")
                summaryValue("具体时段", value: "\(day.planBlocks.count)")
                summaryValue("具体计划时长", value: calendarPlanningDuration(day.plannedDuration))
                summaryValue("当天待截止", value: "\(day.deadlineTasks.count)")
                Divider()
                Text("选择日期查看任务，再选择任务打开详情。\n“安排任务”也能找到没有计划日期的积压任务。\n日期范围不计为全天工时；具体时段按各时段累计。")
                    .font(.system(size: 12))
                    .foregroundStyle(ModernPalette.railInk)
                    .lineSpacing(7)
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(ModernPalette.panel)
        }
    }

    private func summaryValue(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(ModernPalette.muted)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(ModernPalette.ink).monospacedDigit()
        }
        .font(.system(size: 12))
    }

    private func matchesSearch(_ task: GTDTask) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty || [task.title, task.note, model.project(for: task)?.name ?? "",
                                  task.tags.joined(separator: " "), task.contexts.joined(separator: " ")]
            .joined(separator: " ").localizedCaseInsensitiveContains(needle)
    }

    private func selectDay(_ day: Date) {
        model.selection.calendarDay = Calendar.current.startOfDay(for: day)
        visibleMonth = Calendar.current.dateInterval(of: .month, for: day)?.start
    }

    private func moveMonth(_ offset: Int) {
        guard let destination = CalendarMonthGrid.navigation(from: month, selectedDay: selectedDay, offset: offset) else { return }
        visibleMonth = destination.month
        model.selection.calendarDay = destination.selectedDay
    }

    private func returnToToday() { selectDay(now) }

    private func completionExplanation(for day: Date) -> String {
        let today = Calendar.current.startOfDay(for: now)
        if day > today { return "未来日期用于计划，不提前完成每日实例。新建任务默认使用所选日期。" }
        if day < today { return "过去的普通任务为只读完成记录；每日任务可补记或撤销该日实例。新建任务默认使用所选日期。" }
        return "普通任务按整项完成；每日任务只切换今天的实例。新建任务默认使用所选日期。"
    }
}

private struct CalendarDateCell: View {
    let gridDay: CalendarMonthGrid.Day
    let snapshot: TodayExecutionSnapshot?
    let isSelected: Bool
    let isToday: Bool
    let onSelect: () -> Void

    private var taskCount: Int { snapshot?.totalCount ?? 0 }
    private var deadlineCount: Int { snapshot?.deadlineTasks.count ?? 0 }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 2) {
                    Text("\(Calendar.current.component(.day, from: gridDay.date))")
                        .font(.system(size: 12, weight: isToday || isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected || isToday ? ModernPalette.selection : (gridDay.isInMonth ? ModernPalette.ink : ModernPalette.muted))
                    Spacer(minLength: 0)
                    if isToday {
                        Circle().fill(ModernPalette.accent).frame(width: 4, height: 4)
                    }
                }
                if taskCount > 0 {
                    Text("\(taskCount) 项任务")
                        .font(.system(size: 10))
                        .foregroundStyle(gridDay.isInMonth ? ModernPalette.railInk : ModernPalette.muted)
                        .lineLimit(1)
                } else {
                    Text(" ").font(.system(size: 10))
                }
                HStack(spacing: 3) {
                    if deadlineCount > 0 {
                        Image(systemName: "flag.fill").font(.system(size: 8))
                        Text("\(deadlineCount) 截止").font(.system(size: 9))
                    } else if let snapshot, snapshot.completedCount > 0 {
                        Image(systemName: "checkmark").font(.system(size: 8))
                        Text("\(snapshot.completedCount) 完成").font(.system(size: 9))
                    } else {
                        Text(" ").font(.system(size: 9))
                    }
                }
                .foregroundStyle(deadlineCount > 0 ? ModernPalette.red : ModernPalette.completion)
                .lineLimit(1)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 79, alignment: .topLeading)
            .background(isSelected ? ModernPalette.selection.opacity(0.09) : ModernPalette.panel,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? ModernPalette.selection.opacity(0.7) : ModernPalette.line.opacity(0.55),
                            lineWidth: isSelected ? 1.25 : 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(calendarPlanningDate(gridDay.date))\(isToday ? "，今天" : "")，\(taskCount) 项任务，\(deadlineCount) 项待截止")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CalendarPlanningTaskRow: View {
    @Environment(AppModel.self) private var model: AppModel
    let task: GTDTask
    let snapshot: TodayExecutionSnapshot
    let now: Date
    @State private var showsScheduler = false

    private var completed: Bool { snapshot.completedTasks.contains { $0.id == task.id } }
    private var blocks: [TodayPlanBlock] { snapshot.planBlocks.filter { $0.taskID == task.id } }
    private var completionRule: CalendarTaskCompletionRule {
        CalendarTaskCompletionRule.resolve(task: task, day: snapshot.day, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                completionControl
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
                            if completed { Text("这一天已完成") }
                            if blocks.isEmpty && !completed { Text("未安排具体时段") }
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(ModernPalette.muted)
                        .lineLimit(1)
                        if let deadline = task.deadline {
                            Text("截止：\(calendarPlanningDeadline(deadline, precision: task.deadlinePrecision))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(!completed && deadline < now ? ModernPalette.red : ModernPalette.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if TaskDayRules.canSchedule(task, on: snapshot.day, calendar: .current) {
                    Button { showsScheduler = true } label: {
                        Label("安排", systemImage: "calendar.badge.plus").font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("为 \(task.title) 安排 \(calendarPlanningDate(snapshot.day)) 的时段")
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
                    Text(calendarPlanningTime(block, day: snapshot.day))
                    Text(block.id.source == .executionSlot ? "执行时段" : (block.isPoint ? "计划时间点" : "任务计划"))
                        .foregroundStyle(ModernPalette.muted)
                    Spacer()
                    if let slotID = block.id.slotID {
                        Button { _ = model.removeExecutionSlot(taskID: task.id, slotID: slotID) } label: {
                            Image(systemName: "xmark.circle").frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ModernPalette.muted)
                        .help("移除整个执行时段，保留原计划和截止时间")
                        .accessibilityLabel("移除 \(task.title) 的 \(calendarPlanningTime(block, day: snapshot.day)) 执行时段")
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(ModernPalette.accent)
                .padding(.leading, 34)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .plannerTaskActions(taskID: task.id, scope: .day(snapshot.day))
        .background(model.isTaskSelected(task.id) ? ModernPalette.selection.opacity(0.055) : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ModernPalette.line.opacity(0.45)).frame(height: 0.5).padding(.leading, 46)
        }
    }

    @ViewBuilder
    private var completionControl: some View {
        if completionRule.allowsToggle {
            Button { _ = model.toggleCalendarCompletion(taskID: task.id, day: snapshot.day) } label: {
                Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(completed ? ModernPalette.completion : ModernPalette.line)
                    .frame(width: 24, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(completionLabel)
            .help(completionLabel)
        } else {
            Image(systemName: completed ? "checkmark.circle.fill" : (TodayExecutionProjection.isDailyRecurring(task) ? "repeat" : "circle.dotted"))
                .font(.system(size: 17))
                .foregroundStyle(completed ? ModernPalette.completion : ModernPalette.muted)
                .frame(width: 24, height: 32)
                .accessibilityLabel(completionRule == .futurePlan ? "未来计划，不提前完成" : "历史任务，只读状态")
        }
    }

    private var completionLabel: String {
        if completionRule == .dailyInstance {
            return "\(completed ? "撤销" : "记录") \(task.title) 在 \(calendarPlanningDate(snapshot.day)) 的完成实例"
        }
        return "\(completed ? "重新打开整项任务" : "完成整项任务") \(task.title)"
    }
}

private func calendarPlanningDate(_ date: Date) -> String {
    date.formatted(.dateTime.year().month(.defaultDigits).day(.defaultDigits).weekday(.wide))
}

private func calendarPlanningDeadline(_ date: Date, precision: DeadlinePrecision) -> String {
    precision == .minute
        ? date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits).hour().minute())
        : date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
}

private func calendarPlanningTime(_ block: TodayPlanBlock, day: Date) -> String {
    let start = block.start.formatted(date: .omitted, time: .shortened)
    guard !block.isPoint else { return start }
    let nextDay = Calendar.current.isDate(block.end, inSameDayAs: day) ? "" : "次日 "
    return "\(start)–\(nextDay)\(block.end.formatted(date: .omitted, time: .shortened))"
}

private func calendarPlanningDuration(_ duration: TimeInterval) -> String {
    let minutes = Int((duration / 60).rounded())
    return "\(minutes / 60) 小时 \(minutes % 60) 分"
}
