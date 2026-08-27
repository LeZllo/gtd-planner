import SwiftUI

enum ModernGanttScale: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
        }
    }

    /// The week view keeps two weeks in view so the user can see a useful
    /// planning horizon while preserving readable day cells at the minimum
    /// window width.
    var spanDays: Int {
        switch self {
        case .day: 7
        case .week: 14
        case .month: 28
        }
    }
}

struct ModernGanttPane: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var rangeStart = Calendar.current.startOfDay(for: .now)
    @State private var scale: ModernGanttScale = .week
    @State private var collapsedSectionIDs: Set<String> = []
    @State private var collapsedTaskIDs: Set<UUID> = []
    @State private var showCompleted = true
    @State private var didInitialFit = false

    private let tableWidth: CGFloat = 410
    private let rowHeight: CGFloat = 36

    private var calendar: Calendar { Calendar.current }

    private var visibleTasks: [GTDTask] {
        let tasks = model.filteredTasks(includeSearch: false)
        return showCompleted ? tasks : tasks.filter { !$0.status.isFinished }
    }

    private var sectionDisplays: [TaskSectionDisplay] {
        TaskSectionDisplayBuilder.displays(
            projectID: model.selection.selectedProjectID,
            sections: model.selectedProjectSections,
            tasks: visibleTasks
        )
    }

    private var days: [Date] {
        (0..<scale.spanDays).compactMap {
            calendar.date(byAdding: .day, value: $0, to: rangeStart)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { proxy in
                let gridWidth = max(360, proxy.size.width - tableWidth)

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        tableHeader
                            .frame(width: tableWidth, height: 58)
                        ModernGanttDateHeader(days: days, today: .now, gridWidth: gridWidth)
                            .frame(width: gridWidth, height: 58)
                    }
                    .background(ModernPalette.panel)

                    Divider()

                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(sectionDisplays) { display in
                                let sectionID = display.id
                                let sectionColor = Color(hex: display.section?.colorHex ?? "#8C97A5")
                                let sectionTitle = display.section?.name ?? "未分区"
                                let rows = ModernGanttOutlineBuilder.rows(
                                    for: display.tasks,
                                    collapsedTaskIDs: collapsedTaskIDs
                                )

                                ModernGanttSectionRow(
                                    title: sectionTitle,
                                    count: display.tasks.count,
                                    color: sectionColor,
                                    collapsed: collapsedSectionIDs.contains(sectionID),
                                    gridWidth: gridWidth,
                                    days: days,
                                    onToggle: {
                                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
                                            if collapsedSectionIDs.contains(sectionID) {
                                                collapsedSectionIDs.remove(sectionID)
                                            } else {
                                                collapsedSectionIDs.insert(sectionID)
                                            }
                                        }
                                    }
                                )

                                if !collapsedSectionIDs.contains(sectionID) {
                                    ForEach(rows) { row in
                                        ModernGanttTaskRow(
                                            task: row.task,
                                            depth: row.depth,
                                            hasChildren: row.hasChildren,
                                            expanded: !collapsedTaskIDs.contains(row.task.id),
                                            selected: model.isTaskSelected(row.task.id),
                                            tableWidth: tableWidth,
                                            gridWidth: gridWidth,
                                            days: days,
                                            rangeStart: rangeStart,
                                            rowHeight: rowHeight,
                                            onToggleExpanded: {
                                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.16)) {
                                                    if collapsedTaskIDs.contains(row.task.id) {
                                                        collapsedTaskIDs.remove(row.task.id)
                                                    } else {
                                                        collapsedTaskIDs.insert(row.task.id)
                                                    }
                                                }
                                            }
                                        )
                                    }
                                }
                            }

                            if sectionDisplays.isEmpty {
                                EmptyColumnHint(
                                    icon: "chart.bar.xaxis",
                                    title: "这个项目还没有任务",
                                    message: "先在任务模式中添加一个下一步行动"
                                )
                                .frame(maxWidth: .infinity, minHeight: 220)
                                .padding(.top, 80)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .background(ModernPalette.canvas)
                }
            }
        }
        .background(ModernPalette.canvas)
        .onAppear {
            guard !didInitialFit else { return }
            didInitialFit = true
            fitProject()
        }
        .onChange(of: model.selection.selectedProjectID) { _, _ in
            collapsedSectionIDs.removeAll()
            collapsedTaskIDs.removeAll()
            didInitialFit = false
            fitProject()
            didInitialFit = true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: model.selectedProject?.symbolName ?? "folder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: model.selectedProject?.colorHex ?? "#2F6FD0"))
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedProject?.name ?? "项目甘特图")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ModernPalette.ink)
                        .lineLimit(1)
                    Text("项目计划")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ModernPalette.muted)
                }
            }

            Spacer(minLength: 16)

            HStack(spacing: 4) {
                Button { shiftRange(by: -1) } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(ModernQuietButtonStyle())
                .help("上一时间段")

                Button("今天", action: jumpToToday)
                    .buttonStyle(ModernToolbarButtonStyle(tint: ModernPalette.ink))
                    .frame(height: 30)

                Button { shiftRange(by: 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(ModernQuietButtonStyle())
                .help("下一时间段")
            }

            Text(rangeLabel)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(ModernPalette.muted)
                .lineLimit(1)

            Picker("时间尺度", selection: $scale) {
                ForEach(ModernGanttScale.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 126)

            Button("适合项目", action: fitProject)
                .buttonStyle(ModernToolbarButtonStyle(tint: ModernPalette.ink))
                .frame(height: 30)
                .help("让时间范围适合项目中的计划任务")

            Menu {
                Toggle("显示已完成", isOn: $showCompleted)
                Divider()
                Text("计划条可直接拖动调整")
                    .foregroundStyle(ModernPalette.muted)
            } label: {
                Label("视图选项", systemImage: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(ModernToolbarButtonStyle(tint: ModernPalette.ink))
            .frame(height: 30)

        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(ModernPalette.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ModernPalette.line.opacity(0.56))
                .frame(height: 0.75)
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("任务名称")
                .frame(width: 220, alignment: .leading)
            Text("状态")
                .frame(width: 62, alignment: .leading)
            Text("计划")
                .frame(width: 72, alignment: .leading)
            Text("截止")
                .frame(width: 56, alignment: .leading)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(ModernPalette.muted)
        .padding(.horizontal, 10)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(ModernPalette.line.opacity(0.72))
                .frame(width: 0.75)
        }
    }

    private var rangeLabel: String {
        guard let end = days.last else { return "" }
        return "\(shortDate(rangeStart)) – \(shortDate(end))"
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
    }

    private func shiftRange(by direction: Int) {
        guard let next = calendar.date(byAdding: .day, value: direction * scale.spanDays, to: rangeStart) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            rangeStart = calendar.startOfDay(for: next)
        }
    }

    private func jumpToToday() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            rangeStart = calendar.startOfDay(for: .now)
        }
    }

    private func fitProject() {
        let dates = visibleTasks.flatMap { task in
            [task.plannedStart, task.plannedEnd, task.deadline].compactMap { $0 }
        }
        let target = dates.min() ?? .now
        rangeStart = calendar.startOfDay(for: target)
    }
}

struct ModernGanttOutlineRow: Identifiable {
    let task: GTDTask
    let depth: Int
    let hasChildren: Bool

    var id: UUID { task.id }
}

enum ModernGanttOutlineBuilder {
    static func rows(for tasks: [GTDTask], collapsedTaskIDs: Set<UUID>) -> [ModernGanttOutlineRow] {
        let ids = Set(tasks.map(\.id))
        let children = Dictionary(grouping: tasks.filter { $0.parentID != nil }, by: { $0.parentID! })
        let roots = tasks
            .filter { $0.parentID == nil || !ids.contains($0.parentID!) }
            .sorted(by: TaskDisplayOrdering.flatList)

        var result: [ModernGanttOutlineRow] = []

        func append(_ task: GTDTask, depth: Int) {
            let childTasks = (children[task.id] ?? []).sorted(by: TaskDisplayOrdering.hierarchyChild)
            result.append(ModernGanttOutlineRow(task: task, depth: depth, hasChildren: !childTasks.isEmpty))
            guard !collapsedTaskIDs.contains(task.id) else { return }
            for child in childTasks {
                append(child, depth: min(depth + 1, 6))
            }
        }

        for root in roots { append(root, depth: 0) }
        return result
    }
}

private struct ModernGanttSectionRow: View {
    let title: String
    let count: Int
    let color: Color
    let collapsed: Bool
    let gridWidth: CGFloat
    let days: [Date]
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 7) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ModernPalette.muted)
                        .frame(width: 14)
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ModernPalette.muted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 410, height: 32, alignment: .leading)
            .background(color.opacity(0.045))

            ModernGanttGridBackdrop(days: days, today: .now)
                .frame(width: gridWidth, height: 32)
                .background(color.opacity(0.025))
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(color.opacity(0.32))
                .frame(height: 0.75)
        }
    }
}

private struct ModernGanttTaskRow: View {
    @Environment(AppModel.self) private var model: AppModel

    let task: GTDTask
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
    let selected: Bool
    let tableWidth: CGFloat
    let gridWidth: CGFloat
    let days: [Date]
    let rangeStart: Date
    let rowHeight: CGFloat
    let onToggleExpanded: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tableContent
                .frame(width: tableWidth, height: rowHeight)
                .background(selected ? ModernPalette.blue.opacity(0.09) : .clear)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(ModernPalette.line.opacity(0.56))
                        .frame(width: 0.75)
                }

            ModernGanttGridRow(
                task: task,
                selected: selected,
                days: days,
                rangeStart: rangeStart,
                gridWidth: gridWidth,
                rowHeight: rowHeight
            )
            .background(selected ? ModernPalette.blue.opacity(0.09) : .clear)
            .frame(width: gridWidth, height: rowHeight)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ModernPalette.line.opacity(0.40))
                .frame(height: 0.55)
        }
    }

    private var tableContent: some View {
        HStack(spacing: 0) {
            Button {
                model.selectTask(task.id)
            } label: {
                HStack(spacing: 4) {
                    Color.clear.frame(width: CGFloat(min(depth, 6)) * 14)

                    if hasChildren {
                        Button(action: onToggleExpanded) {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(ModernPalette.muted)
                                .frame(width: 15, height: 24)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 15)
                    }

                    Button { model.toggleTask(task.id) } label: {
                        Image(systemName: completionSymbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(completionColor)
                            .frame(width: 22, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(task.status == .done ? "重新打开任务" : "完成任务")

                    Text(task.title)
                        .font(.system(size: 11.5, weight: task.status.isFinished ? .regular : .medium))
                        .foregroundStyle(task.status.isFinished ? ModernPalette.muted : ModernPalette.ink)
                        .strikethrough(task.status.isFinished, color: ModernPalette.muted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 8)
                .padding(.trailing, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 220, height: rowHeight, alignment: .leading)
            .help("选择任务")

            Text(task.status.title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.11), in: Capsule())
                .frame(width: 62, alignment: .leading)

            Text(ganttPlanColumnText)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(task.plannedStart == nil ? ModernPalette.muted : ModernPalette.ink)
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)

            Text(ganttDeadlineColumnText)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(task.deadline == nil ? ModernPalette.muted : ModernPalette.red)
                .lineLimit(1)
                .frame(width: 56, alignment: .leading)
        }
    }

    private var completionSymbol: String {
        switch task.status {
        case .done: "checkmark.circle.fill"
        case .cancelled: "minus.circle.fill"
        default: "circle"
        }
    }

    private var completionColor: Color {
        switch task.status {
        case .done: ModernPalette.accent
        case .cancelled: ModernPalette.muted
        default: ModernPalette.muted
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .done: ModernPalette.accent
        case .inProgress: ModernPalette.blue
        case .waiting: Color(nsColor: NSColor.systemOrange)
        case .cancelled: ModernPalette.muted
        default: ModernPalette.muted
        }
    }

    private var ganttPlanColumnText: String {
        guard let start = task.plannedStart else { return "—" }
        let startText = start.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
        guard let end = task.plannedEnd else { return startText }
        let endDate = task.plannedPrecision == .date ? end.addingTimeInterval(-1) : end
        return "\(startText)–\(endDate.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits)))"
    }

    private var ganttDeadlineColumnText: String {
        guard let deadline = task.deadline else { return "—" }
        return deadline.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
    }
}

private struct ModernGanttDateHeader: View {
    let days: [Date]
    let today: Date
    let gridWidth: CGFloat

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    Text(isFirstDayOfMonth(day) ? day.formatted(.dateTime.month(.defaultDigits)) : "")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(ModernPalette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 6)
                }
            }
            .frame(height: 20)

            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 2) {
                        Text(day.formatted(.dateTime.day(.twoDigits)))
                            .font(.system(size: 10, weight: isToday(day) ? .bold : .medium, design: .monospaced))
                        Text(weekdayText(day))
                            .font(.system(size: 8.5, weight: isToday(day) ? .semibold : .regular))
                    }
                    .foregroundStyle(isToday(day) ? ModernPalette.blue : isWeekend(day) ? ModernPalette.red : ModernPalette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isWeekend(day) ? ModernPalette.red.opacity(0.035) : .clear)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(ModernPalette.line.opacity(0.44))
                            .frame(width: 0.55)
                    }
                }
            }
            .frame(height: 38)
        }
        .frame(width: gridWidth)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ModernPalette.line.opacity(0.66))
                .frame(height: 0.75)
        }
    }

    private func isFirstDayOfMonth(_ day: Date) -> Bool {
        calendar.component(.day, from: day) == 1 || day == days.first
    }

    private func isToday(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: today)
    }

    private func isWeekend(_ day: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: day)
        return weekday == 1 || weekday == 7
    }

    private func weekdayText(_ day: Date) -> String {
        ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][
            calendar.component(.weekday, from: day) - 1
        ]
    }
}

private struct ModernGanttGridBackdrop: View {
    let days: [Date]
    let today: Date

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        Rectangle()
                            .fill(isWeekend(day) ? ModernPalette.red.opacity(0.026) : .clear)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(ModernPalette.line.opacity(0.40))
                                    .frame(width: 0.55)
                            }
                    }
                }

                if let todayIndex = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: today) }) {
                    Rectangle()
                        .fill(ModernPalette.blue.opacity(0.78))
                        .frame(width: 1.25, height: proxy.size.height)
                        .offset(x: proxy.size.width * CGFloat(todayIndex) / CGFloat(max(days.count, 1)))
                }
            }
        }
    }

    private func isWeekend(_ day: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: day)
        return weekday == 1 || weekday == 7
    }
}

private struct ModernGanttGridRow: View {
    @Environment(AppModel.self) private var model: AppModel

    let task: GTDTask
    let selected: Bool
    let days: [Date]
    let rangeStart: Date
    let gridWidth: CGFloat
    let rowHeight: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                ModernGanttGridBackdrop(days: days, today: .now)

                if let start = task.plannedStart {
                    ModernGanttScheduleBar(
                        task: task,
                        startX: offset(for: start, width: proxy.size.width),
                        barWidth: width(for: start, end: task.plannedEnd, width: proxy.size.width),
                        dayWidth: proxy.size.width / CGFloat(max(days.count, 1)),
                        selected: selected
                    )
                }

                if let deadline = task.deadline {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ModernPalette.red)
                        .frame(width: 12, height: rowHeight)
                        .offset(x: min(max(offset(for: deadline, width: proxy.size.width) - 6, 0), proxy.size.width - 12))
                        .accessibilityLabel("截止时间")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                model.selectTask(task.id)
            }
        }
        .frame(width: gridWidth, height: rowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(task.title)
        .accessibilityValue(ganttAccessibilityRange)
    }

    private func offset(for date: Date, width: CGFloat) -> CGFloat {
        let seconds = date.timeIntervalSince(rangeStart)
        let fraction = seconds / Double(max(days.count, 1) * 86_400)
        return CGFloat(min(1, max(0, fraction))) * width
    }

    private func width(for start: Date, end: Date?, width: CGFloat) -> CGFloat {
        guard let end else { return 8 }
        let seconds = max(900, end.timeIntervalSince(start))
        let fraction = seconds / Double(max(days.count, 1) * 86_400)
        return max(8, min(width, CGFloat(fraction) * width))
    }

    private var ganttAccessibilityRange: String {
        guard let start = task.plannedStart else { return "未设置计划时间" }
        if let end = task.plannedEnd {
            return "计划 \(start.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))) 至 \(end.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits)))"
        }
        return "计划于 \(start.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits)))"
    }
}

private struct ModernGanttScheduleBar: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let task: GTDTask
    let startX: CGFloat
    let barWidth: CGFloat
    let dayWidth: CGFloat
    let selected: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var dragOriginal: GTDTask?

    var body: some View {
        barShape
            .offset(x: startX + dragOffset)
            .onTapGesture {
                model.selectTask(task.id)
            }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        if dragOriginal == nil { dragOriginal = task }
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        commitDrag(value.translation.width)
                    }
            )
            .accessibilityLabel(task.plannedEnd == nil ? "计划时间点" : "计划时间段")
            .accessibilityHint("拖动以移动计划时间")
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: dragOffset)
    }

    @ViewBuilder
    private var barShape: some View {
        if task.plannedEnd == nil {
            Capsule()
                .fill(ModernPalette.blue.opacity(selected ? 0.96 : 0.86))
                .frame(width: 8, height: 18)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(ModernPalette.blue.opacity(selected ? 0.96 : 0.82))
                .frame(width: max(12, barWidth), height: 18)
        }
    }

    private func commitDrag(_ translation: CGFloat) {
        defer {
            dragOffset = 0
            dragOriginal = nil
        }
        guard let original = dragOriginal, let start = original.plannedStart else { return }
        let secondsPerDay = 86_400.0
        let rawSeconds = Double(translation / max(dayWidth, 1)) * secondsPerDay
        let step = original.plannedPrecision == .date ? secondsPerDay : 900.0
        let delta = (rawSeconds / step).rounded() * step
        guard delta != 0 else { return }

        var updated = original
        updated.plannedStart = start.addingTimeInterval(delta)
        if let end = original.plannedEnd {
            updated.plannedEnd = end.addingTimeInterval(delta)
        }
        model.updateTask(updated)
    }
}
