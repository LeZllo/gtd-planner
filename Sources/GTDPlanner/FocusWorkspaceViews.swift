import SwiftUI

private enum C234FocusField: Hashable {
    case taskSearch
}

/// C234 — 专注执行工作区
///
/// This view intentionally replaces only the content below T1. The source
/// sidebar (C1) and the top toolbar (T1) remain in RedesignViews.swift and are
/// not duplicated here, so focus mode cannot silently change their layout.
struct C234FocusWorkspaceView: View {
    @Environment(AppModel.self) private var model: AppModel

    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var selectedTaskID: UUID?
    @State private var completedEntryID: UUID?
    @State private var editingEntry: TimeEntry?
    @State private var pendingDeleteEntry: TimeEntry?
    @State private var resolvedInitialTask = false
    @FocusState private var focusedField: C234FocusField?

    let mode: TimerMode

    private var workspaceID: UUID {
        model.activeTimer?.workspaceID ?? model.selection.selectedWorkspaceID
    }

    var body: some View {
        GeometryReader { proxy in
            let outerInset = proxy.size.width >= 1320 ? 28.0 : 18.0
            let cardWidth = max(0, proxy.size.width - outerInset * 2)
            let contentInset = cardWidth >= 1180 ? 28.0 : 22.0
            let topInset = cardWidth >= 1180 ? 20.0 : 16.0
            let compactHeight = proxy.size.height < 820
            let timelineAxisHeight: CGFloat = compactHeight ? 30 : 36
            let timelineLaneHeight: CGFloat = compactHeight ? 76 : 94
            let timelineHeadingHeight: CGFloat = 18 + 6
            let timelineTopSpacing = cardWidth >= 1180 ? 18.0 : 14.0
            let cardBottomInset = max(18, contentInset - 4)
            let reservedForTop = max(
                0,
                proxy.size.height
                    - topInset
                    - timelineTopSpacing
                    - timelineHeadingHeight
                    - timelineAxisHeight
                    - timelineLaneHeight * 2
                    - cardBottomInset
                    - 12
            )
            let maxClockDiameter = min(330, max(204, reservedForTop - 174))

            VStack(spacing: 0) {
                topContent(
                    availableWidth: cardWidth - contentInset * 2,
                    maxClockDiameter: maxClockDiameter
                )

                FocusLinearTimeline(
                    day: selectedDate,
                    workspaceID: workspaceID,
                    axisHeight: timelineAxisHeight,
                    laneHeight: timelineLaneHeight,
                    onEditEntry: { editingEntry = $0 },
                    onDeleteEntry: { pendingDeleteEntry = $0 },
                    onInteraction: { focusedField = nil }
                )
                .padding(.top, timelineTopSpacing)
            }
            .padding(.horizontal, contentInset)
            .padding(.top, topInset)
            .padding(.bottom, max(18, contentInset - 4))
            .frame(maxWidth: .infinity, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ModernPalette.panel)
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = nil }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ModernPalette.line.opacity(0.48), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.045), radius: 18, y: 7)
            .padding(.horizontal, outerInset)
            .padding(.top, 0)
            .padding(.bottom, 12)
            .background(ModernPalette.canvas)
        }
        .background(ModernPalette.canvas)
        .onAppear(perform: resolveInitialTaskIfNeeded)
        .onChange(of: mode) { _, _ in
            focusedField = nil
            guard model.activeTimer == nil else { return }
            completedEntryID = nil
        }
        .onChange(of: model.activeTimer?.taskID) { _, activeTaskID in
            if let activeTaskID {
                selectedTaskID = activeTaskID
            }
        }
        .sheet(item: $editingEntry) { entry in
            FocusEntryEditorSheet(
                entry: entry,
                workspaceID: workspaceID,
                defaultDate: selectedDate
            )
            .environment(model)
            .frame(width: 480, height: 560)
        }
        .confirmationDialog(
            "删除实际专注记录？",
            isPresented: Binding(
                get: { pendingDeleteEntry != nil },
                set: { if !$0 { pendingDeleteEntry = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let entry = pendingDeleteEntry {
                    _ = model.deleteTimeEntry(withID: entry.id)
                }
                pendingDeleteEntry = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteEntry = nil
            }
        } message: {
            Text(
                pendingDeleteEntry.map {
                    "\($0.title) · \(focusTimeRange(start: $0.startedAt, end: $0.endedAt))"
                } ?? ""
            )
        }
    }

    @ViewBuilder
    private func topContent(availableWidth: CGFloat, maxClockDiameter: CGFloat) -> some View {
        if availableWidth < 900 {
            VStack(alignment: .leading, spacing: 24) {
                controlColumn(maxClockDiameter: maxClockDiameter)
                dayColumn
            }
        } else {
            HStack(alignment: .top, spacing: availableWidth >= 1180 ? 42 : 30) {
                controlColumn(maxClockDiameter: maxClockDiameter)
                    .frame(width: min(560, max(470, availableWidth * 0.46)))

                dayColumn
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func controlColumn(maxClockDiameter: CGFloat) -> some View {
        C234FocusControlColumn(
            selectedTaskID: $selectedTaskID,
            completedEntryID: $completedEntryID,
            focusedField: $focusedField,
            mode: mode,
            workspaceID: workspaceID,
            maxClockDiameter: maxClockDiameter
        )
    }

    private var dayColumn: some View {
        C234FocusDayColumn(
            selectedDate: $selectedDate,
            selectedTaskID: $selectedTaskID,
            focusedField: $focusedField,
            workspaceID: workspaceID
        )
    }

    private func resolveInitialTaskIfNeeded() {
        guard !resolvedInitialTask else { return }
        resolvedInitialTask = true
        selectedTaskID = model.activeTimer?.taskID ?? model.selectedTask?.id
    }
}

private struct C234FocusControlColumn: View {
    @Environment(AppModel.self) private var model: AppModel

    @Binding var selectedTaskID: UUID?
    @Binding var completedEntryID: UUID?
    @FocusState.Binding private var focusedField: C234FocusField?

    let mode: TimerMode
    let workspaceID: UUID
    let maxClockDiameter: CGFloat

    init(
        selectedTaskID: Binding<UUID?>,
        completedEntryID: Binding<UUID?>,
        focusedField: FocusState<C234FocusField?>.Binding,
        mode: TimerMode,
        workspaceID: UUID,
        maxClockDiameter: CGFloat
    ) {
        _selectedTaskID = selectedTaskID
        _completedEntryID = completedEntryID
        _focusedField = focusedField
        self.mode = mode
        self.workspaceID = workspaceID
        self.maxClockDiameter = maxClockDiameter
    }

    private var selectedTask: GTDTask? {
        if let activeTaskID = model.activeTimer?.taskID {
            return model.task(withID: activeTaskID)
        }
        guard model.activeTimer == nil else { return nil }
        return selectedTaskID.flatMap(model.task(withID:))
    }

    private var completedEntry: TimeEntry? {
        completedEntryID.flatMap(model.timeEntry(withID:))
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            FocusClockPanel(
                mode: mode,
                selectedTask: selectedTask,
                completedEntry: completedEntry,
                maxClockDiameter: maxClockDiameter,
                onCompleted: { completedEntryID = $0.id },
                onStarted: { completedEntryID = nil },
                onInteraction: { focusedField = nil }
            )
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("C234 专注执行工作区")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("专注执行")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                    .tracking(-0.3)

                Text("留一点时间，只做这一件事")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ModernPalette.railInk)
            }
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            FocusCurrentTaskCard(
                task: selectedTask,
                workspaceID: workspaceID,
                isLocked: model.activeTimer != nil,
                onClear: {
                    focusedField = nil
                    selectedTaskID = nil
                }
            )
            .padding(.top, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}

private struct FocusModeSegment: View {
    @Environment(AppModel.self) private var model: AppModel

    let mode: TimerMode
    let onInteraction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            segmentButton(.stopwatch, title: "正计时")
            segmentButton(.pomodoro, title: "番茄钟")
        }
        .padding(2)
        .frame(width: 248, height: 36)
        .background(ModernPalette.subtle.opacity(0.72), in: Capsule())
        .overlay {
            Capsule()
                .stroke(ModernPalette.line.opacity(0.48), lineWidth: 0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("计时模式")
    }

    private func segmentButton(_ target: TimerMode, title: String) -> some View {
        let selected = mode == target
        let tint = target == .stopwatch ? ModernPalette.blue : ModernPalette.red

        return Button {
            onInteraction()
            guard model.activeTimer == nil else { return }
            model.selection.focusMode = target
        } label: {
            Text(title)
                .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? tint : ModernPalette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(selected ? ModernPalette.panel : .clear, in: Capsule())
                .overlay {
                    if selected {
                        Capsule()
                            .stroke(tint.opacity(0.18), lineWidth: 0.75)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(model.activeTimer != nil && !selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(title)
    }
}

private struct FocusCurrentTaskCard: View {
    @Environment(AppModel.self) private var model: AppModel

    let task: GTDTask?
    let workspaceID: UUID
    let isLocked: Bool
    let onClear: () -> Void

    private var project: Project? {
        task.flatMap(model.project(for:))
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(task.map { Color(hex: model.project(for: $0)?.colorHex ?? model.currentWorkspace.colorHex) } ?? ModernPalette.muted.opacity(0.55))
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("当前任务：")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(ModernPalette.ink)

                    Text(task?.title ?? "未关联任务")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(ModernPalette.railInk)
                        .lineLimit(1)
                }

                Text(task == nil ? "右侧搜索任务，或直接记录无任务专注" : (project?.name ?? "无项目"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isLocked {
                Label("已锁定", systemImage: "lock.fill")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)
            } else if task != nil {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.muted)
                .help("改为无任务专注")
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 38)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(task.map { "当前专注任务，\($0.title)" } ?? "未关联任务")
    }
}

private struct FocusClockPanel: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draftPomodoroSeconds: TimeInterval = 25 * 60

    let mode: TimerMode
    let selectedTask: GTDTask?
    let completedEntry: TimeEntry?
    let maxClockDiameter: CGFloat
    let onCompleted: (TimeEntry) -> Void
    let onStarted: () -> Void
    let onInteraction: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let timer = model.activeTimer {
                SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                    FocusClockFace(
                        mode: timer.mode,
                        elapsed: model.timerElapsed(at: context.date),
                        target: timer.targetSeconds,
                        paused: timer.pausedAt != nil,
                        completed: false,
                        now: context.date,
                        reduceMotion: reduceMotion,
                        maxClockDiameter: maxClockDiameter,
                        durationEditable: false,
                        onDurationChange: nil,
                        onInteraction: onInteraction
                    )
                }
            } else {
                FocusClockFace(
                    mode: mode,
                    elapsed: completedEntry?.duration ?? 0,
                    target: mode == .pomodoro ? draftPomodoroSeconds : nil,
                    paused: false,
                    completed: completedEntry != nil,
                    now: .now,
                    reduceMotion: reduceMotion,
                    maxClockDiameter: maxClockDiameter,
                    durationEditable: mode == .pomodoro && completedEntry == nil,
                    onDurationChange: { draftPomodoroSeconds = $0 },
                    onInteraction: onInteraction
                )
            }

            actionArea
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        // The dial owns a zero-distance drag while a Pomodoro is prepared.
        // A simultaneous tap keeps the surrounding C234 focus boundary alive
        // without stealing the dial's direct-manipulation gesture.
        .simultaneousGesture(TapGesture().onEnded { onInteraction() })
        .onChange(of: mode) { _, newMode in
            guard model.activeTimer == nil, newMode == .pomodoro else { return }
            draftPomodoroSeconds = 25 * 60
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        if let timer = model.activeTimer {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button {
                        onInteraction()
                        if timer.pausedAt == nil {
                            model.pauseTimer()
                        } else {
                            model.resumeTimer()
                        }
                    } label: {
                        Label(
                            timer.pausedAt == nil ? "暂停" : "继续",
                            systemImage: timer.pausedAt == nil ? "pause.fill" : "play.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FocusPrimaryButtonStyle(tint: timer.pausedAt == nil ? ModernPalette.red : ModernPalette.blue))
                    .frame(width: 230)
                    .keyboardShortcut(.return, modifiers: [.command])

                    Button {
                        onInteraction()
                        if let entry = model.stopTimer() {
                            onCompleted(entry)
                        }
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(FocusCircleActionButtonStyle(tint: ModernPalette.muted))
                    .help("停止并记录")
                }

                Text("结束后才会生成实际专注记录")
                    .font(.system(size: 11.5))
                    .foregroundStyle(ModernPalette.muted)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("当前专注操作")
            .accessibilityHint("番茄钟归零后仍会继续计时，停止后才生成实际专注记录")
        } else if completedEntry != nil {
            HStack(spacing: 12) {
                Button {
                    startTimer()
                } label: {
                    Label(
                        mode == .pomodoro ? "开始新的番茄钟" : "开始新的正计时",
                        systemImage: "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(FocusPrimaryButtonStyle(tint: ModernPalette.blue))
                .frame(width: 230)

                Button {
                    // A completed session has no pauseable timer. Keep this
                    // affordance reserved for the running state so the action
                    // row stays spatially stable without suggesting a fake
                    // state change.
                } label: {
                    Image(systemName: "pause.fill")
                }
                .buttonStyle(FocusCircleActionButtonStyle(tint: ModernPalette.muted))
                .disabled(true)
                .opacity(0.68)
            }

            Button("返回任务") {
                onInteraction()
                model.selection.focusMode = nil
                model.selection.plannerView = .list
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ModernPalette.muted)
        } else {
            HStack(spacing: 12) {
                Button {
                    startTimer()
                } label: {
                    Label(
                        mode == .pomodoro ? "开始番茄钟" : "开始正计时",
                        systemImage: "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(FocusPrimaryButtonStyle(tint: mode == .pomodoro ? ModernPalette.red : ModernPalette.blue))
                .frame(width: 230)
                .keyboardShortcut(.return, modifiers: [.command])

                Button {
                    // There is no running timer to pause before start.
                } label: {
                    Image(systemName: "pause.fill")
                }
                .buttonStyle(FocusCircleActionButtonStyle(tint: ModernPalette.muted))
                .disabled(true)
                .opacity(0.68)
            }

            Text(selectedTask == nil ? "将记录为无任务专注" : "⌘↩ 开始")
                .font(.system(size: 11.5))
                .foregroundStyle(ModernPalette.muted)
        }
    }

    private func startTimer() {
        onInteraction()
        onStarted()
        if mode == .pomodoro {
            model.startPomodoro(for: selectedTask, duration: draftPomodoroSeconds)
        } else {
            model.startStopwatch(for: selectedTask)
        }
    }
}

private struct FocusClockFace: View {
    let mode: TimerMode
    let elapsed: TimeInterval
    let target: TimeInterval?
    let paused: Bool
    let completed: Bool
    let now: Date
    let reduceMotion: Bool
    let maxClockDiameter: CGFloat
    let durationEditable: Bool
    let onDurationChange: ((TimeInterval) -> Void)?
    let onInteraction: () -> Void

    @State private var durationDragActive = false
    @State private var lastDialAngle: Double?
    @State private var dragDegrees: Double = 0

    private var tint: Color {
        mode == .pomodoro ? ModernPalette.red : ModernPalette.blue
    }

    private var displaySeconds: TimeInterval {
        if completed { return 0 }
        if mode == .pomodoro {
            return max(0, (target ?? 25 * 60) - elapsed)
        }
        return max(0, elapsed)
    }

    private var hasTimedOut: Bool {
        guard mode == .pomodoro, let target else { return false }
        return !completed && elapsed >= target
    }

    private var pomodoroTargetSeconds: TimeInterval {
        min(
            AppModel.maximumPomodoroSeconds,
            max(AppModel.minimumPomodoroSeconds, target ?? 25 * 60)
        )
    }

    /// Both modes use the same 60-minute dial. A duration longer than one
    /// hour is represented by completed turns and the current turn's arc;
    /// the exact value remains in the center, so no time is hidden.
    private var dialSeconds: TimeInterval {
        if completed { return 0 }
        if mode == .pomodoro {
            guard !hasTimedOut else { return 0 }
            return max(0, pomodoroTargetSeconds - elapsed)
        }
        return elapsed
    }

    private var dialProgress: Double {
        let remainder = dialSeconds.truncatingRemainder(dividingBy: 60 * 60)
        if dialSeconds > 0, remainder == 0 { return 1 }
        return min(1, max(0, remainder / (60 * 60)))
    }

    private var displayText: String {
        if hasTimedOut {
            return "+\(focusFormatDuration(elapsed - pomodoroTargetSeconds))"
        }
        return focusFormatDuration(displaySeconds)
    }

    private var statusText: String {
        if completed { return "本次专注已完成并记录" }
        if hasTimedOut { return "番茄钟 · 超时专注" }
        if paused { return mode == .pomodoro ? "番茄钟 · 已暂停" : "正计时 · 已暂停" }
        if elapsed > 0 { return mode == .pomodoro ? "番茄钟 · 专注中" : "正计时 · 专注中" }
        return mode == .pomodoro ? "番茄钟 · 准备开始" : "正计时 · 准备开始"
    }

    private var detailText: String? {
        guard mode == .pomodoro else { return nil }

        if durationEditable {
            return "\(Int(pomodoroTargetSeconds / 60)) 分钟 · 拖动圆点调整（每分钟）"
        }

        if !completed, elapsed == 0 {
            let end = now.addingTimeInterval(pomodoroTargetSeconds)
            return "目标 \(Int(pomodoroTargetSeconds / 60)) 分钟 · 预计 \(end.formatted(date: .omitted, time: .shortened)) 结束"
        }
        return "目标 \(Int(pomodoroTargetSeconds / 60)) 分钟 · 一圈 60 分钟"
    }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let radius = diameter / 2
            let ringWidth = max(8, diameter * 0.032)

            clockBody(diameter: diameter, radius: radius, ringWidth: ringWidth)
                .frame(width: diameter, height: diameter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(statusText)
                .accessibilityValue(displayText)
                .accessibilityHint(durationEditable ? "拖动圆点按分钟调整番茄钟时长" : "一圈代表 60 分钟")
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: maxClockDiameter, maxHeight: maxClockDiameter)
    }

    @ViewBuilder
    private func clockBody(diameter: CGFloat, radius: CGFloat, ringWidth: CGFloat) -> some View {
        let content = ZStack {
            ForEach(0..<60, id: \.self) { tick in
                Capsule()
                    .fill(ModernPalette.muted.opacity(tick.isMultiple(of: 5) ? 0.48 : 0.24))
                    .frame(
                        width: tick.isMultiple(of: 5) ? 1.5 : 0.8,
                        height: tick.isMultiple(of: 5) ? 9 : 5
                    )
                    .offset(y: -(radius - 7))
                    .rotationEffect(.degrees(Double(tick) * 6))
            }

            ForEach([0, 15, 30, 45], id: \.self) { minute in
                Text(String(format: "%02d", minute))
                    .font(.system(size: max(9, diameter * 0.032), weight: .semibold, design: .monospaced))
                    .foregroundStyle(ModernPalette.muted.opacity(0.78))
                    .position(
                        dialPoint(
                            angle: Double(minute) * 6,
                            radius: radius - 34,
                            center: CGPoint(x: radius, y: radius)
                        )
                    )
            }

            Circle()
                .stroke(ModernPalette.line.opacity(0.32), lineWidth: ringWidth)
                .padding(18)

            if !completed {
                Circle()
                    .trim(from: 0, to: max(0.001, dialProgress))
                    .stroke(
                        tint.opacity(paused ? 0.34 : 0.92),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(18)

                durationHandle(diameter: diameter, radius: radius)
            }

            VStack(spacing: 8) {
                if completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(ModernPalette.blue)
                        .frame(width: 58, height: 58)
                        .background(ModernPalette.blue.opacity(0.08), in: Circle())
                }

                Text(displayText)
                    .font(.system(size: max(42, diameter * 0.15), weight: .medium, design: .monospaced))
                    .foregroundStyle(ModernPalette.ink)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())

                FocusModeSegment(
                    mode: mode,
                    onInteraction: {}
                )

                Text(statusText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)

                if let detailText {
                    Text(detailText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tint.opacity(0.84))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: diameter * 0.72)
        }

        // The gesture belongs to the dial's coordinate space, not the small
        // handle view. The start-point guard below still limits activation to
        // the handle hit area, while the drag location now maps to the dial
        // center correctly.
        if durationEditable {
            content
                .contentShape(Circle())
                .gesture(durationDragGesture(diameter: diameter))
                .simultaneousGesture(TapGesture().onEnded { onInteraction() })
        } else {
            content.simultaneousGesture(TapGesture().onEnded { onInteraction() })
        }
    }

    private func durationHandle(diameter: CGFloat, radius: CGFloat) -> some View {
        Circle()
            .fill(tint.opacity(paused ? 0.42 : 1))
            .frame(width: durationEditable ? 22 : 16, height: durationEditable ? 22 : 16)
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.94), lineWidth: 3)
            }
            .shadow(color: tint.opacity(0.24), radius: 5)
            .offset(y: -(radius - 18))
            .rotationEffect(.degrees(dialProgress * 360))
            // A prepared Pomodoro handle is directly manipulated, so it must
            // stay 1:1 with the pointer. Only a running timer gets the gentle
            // linear handoff between one-second TimelineView updates.
            .animation(
                reduceMotion || durationEditable || durationDragActive
                    ? nil
                    : .linear(duration: 0.9),
                value: dialProgress
            )
    }

    private func durationDragGesture(diameter: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // The dial's zero-distance drag receives the pointer-down
                // before a tap can be recognized. Clear any task-search
                // focus at that first direct-manipulation frame, then keep
                // the existing handle guard for duration editing.
                onInteraction()

                let center = CGPoint(x: diameter / 2, y: diameter / 2)

                if !durationDragActive {
                    let handle = dialPoint(
                        angle: dialProgress * 360,
                        radius: diameter / 2 - 18,
                        center: center
                    )
                    let distance = hypot(
                        value.startLocation.x - handle.x,
                        value.startLocation.y - handle.y
                    )
                    guard distance <= max(28, diameter * 0.10) else { return }
                    durationDragActive = true
                    lastDialAngle = dialAngle(for: value.startLocation, center: center)
                    dragDegrees = pomodoroTargetSeconds / (60 * 60) * 360
                }

                guard durationDragActive else { return }
                let currentAngle = dialAngle(for: value.location, center: center)
                if let lastDialAngle {
                    dragDegrees += shortestAngleDelta(from: lastDialAngle, to: currentAngle)
                }
                self.lastDialAngle = currentAngle

                let minutes = min(180, max(1, Int((dragDegrees / 6).rounded())))
                onDurationChange?(TimeInterval(minutes * 60))
            }
            .onEnded { _ in
                durationDragActive = false
                lastDialAngle = nil
            }
    }

    private func dialAngle(for point: CGPoint, center: CGPoint) -> Double {
        var angle = atan2(
            Double(point.x - center.x),
            -Double(point.y - center.y)
        ) * 180 / .pi
        if angle < 0 { angle += 360 }
        return angle
    }

    private func dialPoint(angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(sin(radians)) * radius,
            y: center.y - CGFloat(cos(radians)) * radius
        )
    }

    private func shortestAngleDelta(from previous: Double, to current: Double) -> Double {
        var delta = current - previous
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

private struct FocusPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(tint.opacity(configuration.isPressed ? 0.78 : 0.94), in: Capsule())
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.985 : 1))
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

private struct FocusCircleActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(
                configuration.isPressed ? ModernPalette.subtle : ModernPalette.panel,
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(ModernPalette.line.opacity(0.62), lineWidth: 0.75)
            }
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.95 : 1))
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

private struct C234FocusDayColumn: View {
    @Environment(AppModel.self) private var model: AppModel

    @Binding var selectedDate: Date
    @Binding var selectedTaskID: UUID?
    @FocusState.Binding private var focusedField: C234FocusField?

    let workspaceID: UUID

    init(
        selectedDate: Binding<Date>,
        selectedTaskID: Binding<UUID?>,
        focusedField: FocusState<C234FocusField?>.Binding,
        workspaceID: UUID
    ) {
        _selectedDate = selectedDate
        _selectedTaskID = selectedTaskID
        _focusedField = focusedField
        self.workspaceID = workspaceID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayHeader

            FocusWeekStrip(
                selectedDate: $selectedDate,
                onSelect: { focusedField = nil }
            )
            .padding(.top, 18)

            FocusDayMetrics(day: selectedDate, workspaceID: workspaceID)
                .padding(.top, 18)

            FocusTaskPicker(
                selectedTaskID: $selectedTaskID,
                focusedField: $focusedField,
                workspaceID: workspaceID,
                locked: model.activeTimer != nil
            )
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
    }

    private var dayHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(focusDayHeader(selectedDate))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(ModernPalette.ink)

            Text("以今天为中心查看最近七天的计划与实际专注")
                .font(.system(size: 11.5))
                .foregroundStyle(ModernPalette.muted)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
    }
}

private struct FocusTaskPicker: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var selectedTaskID: UUID?
    @FocusState.Binding private var focusedField: C234FocusField?

    @State private var query = ""

    let workspaceID: UUID
    let locked: Bool

    init(
        selectedTaskID: Binding<UUID?>,
        focusedField: FocusState<C234FocusField?>.Binding,
        workspaceID: UUID,
        locked: Bool
    ) {
        _selectedTaskID = selectedTaskID
        _focusedField = focusedField
        self.workspaceID = workspaceID
        self.locked = locked
    }

    private var searchFocused: Bool {
        focusedField == .taskSearch
    }

    private var candidates: [GTDTask] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let tasks = model.focusTasks(in: workspaceID)
        guard !normalized.isEmpty else { return Array(tasks.prefix(7)) }

        return Array(
            tasks.filter { task in
                let projectName = model.project(for: task)?.name ?? ""
                let searchable = [task.title, projectName, task.tags.joined(separator: " ")]
                    .joined(separator: " ")
                    .localizedLowercase
                return searchable.contains(normalized)
            }
            .prefix(7)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择任务")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(ModernPalette.muted)

            if locked, let timer = model.activeTimer {
                lockedActivityRow(timer)
            } else {
                searchField

                if searchFocused {
                    suggestionPanel
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.18),
            value: searchFocused
        )
        .onChange(of: locked) { _, isLocked in
            if isLocked {
                focusedField = nil
            }
        }
        .onExitCommand {
            focusedField = nil
        }
    }

    private func lockedActivityRow(_ timer: ActiveTimer) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(timer.mode == .pomodoro ? ModernPalette.red : ModernPalette.blue)
                .frame(width: 8, height: 8)

            Text(timer.taskID == nil ? "无任务专注" : timer.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(ModernPalette.ink)
                .lineLimit(1)

            Spacer(minLength: 10)

            Label(
                timer.pausedAt == nil ? "计时中" : "已暂停",
                systemImage: timer.pausedAt == nil ? "circle.fill" : "pause.fill"
            )
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(ModernPalette.muted)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(ModernPalette.subtle.opacity(0.48), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(ModernPalette.line.opacity(0.55), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前实际专注，\(timer.title)")
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(ModernPalette.muted)

            TextField("搜索任务，或留空记录无任务专注", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focusedField, equals: .taskSearch)
                .onSubmit {
                    if let first = candidates.first {
                        choose(first.id)
                    }
                }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.muted)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 44)
        .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    searchFocused
                        ? ModernPalette.blue.opacity(0.46)
                        : ModernPalette.line.opacity(0.62),
                    lineWidth: searchFocused ? 1 : 0.75
                )
        }
        .accessibilityLabel("搜索任务")
        .accessibilityHint("聚焦后显示最近建议；点击其他区域会收起候选框")
    }

    private var suggestionPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(query.isEmpty ? "最近建议" : "匹配任务")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted)
                Spacer()
                Text("仅显示未完成任务")
                    .font(.system(size: 10))
                    .foregroundStyle(ModernPalette.muted.opacity(0.85))
            }
            .padding(.horizontal, 12)
            .frame(height: 30)

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Button {
                        selectedTaskID = nil
                        focusedField = nil
                    } label: {
                        taskCandidateRow(
                            title: "不关联任务",
                            subtitle: "记录为无任务专注活动",
                            color: ModernPalette.muted.opacity(0.72),
                            selected: selectedTaskID == nil
                        )
                    }
                    .buttonStyle(.plain)

                    if !candidates.isEmpty {
                        Divider()
                    }

                    ForEach(candidates) { task in
                        Button {
                            choose(task.id)
                        } label: {
                            taskCandidateRow(
                                title: task.title,
                                subtitle: model.project(for: task)?.name ?? "无项目",
                                color: Color(hex: model.project(for: task)?.colorHex ?? model.currentWorkspace.colorHex),
                                selected: task.id == selectedTaskID
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if candidates.isEmpty, !query.isEmpty {
                        Text("没有匹配的未完成任务")
                            .font(.system(size: 11.5))
                            .foregroundStyle(ModernPalette.muted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                }
            }
            .frame(maxHeight: 176)
        }
        .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(ModernPalette.line.opacity(0.68), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.09), radius: 14, y: 5)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }

    private func taskCandidateRow(
        title: String,
        subtitle: String,
        color: Color,
        selected: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(ModernPalette.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ModernPalette.blue)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ModernPalette.muted.opacity(0.75))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(selected ? ModernPalette.blue.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .padding(.horizontal, 4)
    }

    private func choose(_ taskID: UUID) {
        selectedTaskID = taskID
        query = ""
        focusedField = nil
    }
}

private struct FocusDayMetrics: View {
    @Environment(AppModel.self) private var model: AppModel

    let day: Date
    let workspaceID: UUID

    private var plannedDuration: TimeInterval {
        model.focusPlannedTasks(on: day, workspaceID: workspaceID).reduce(0) { total, task in
            guard let start = task.plannedStart, let end = task.plannedEnd, end > start else {
                return total
            }
            return total + end.timeIntervalSince(start)
        }
    }

    private var actualDuration: TimeInterval {
        model.focusTimeEntries(on: day, workspaceID: workspaceID)
            .reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        HStack(spacing: 0) {
            metric(title: "计划专注", value: focusFormatCompactDuration(plannedDuration), color: FocusTimelineColors.planned)

            Rectangle()
                .fill(ModernPalette.line.opacity(0.62))
                .frame(width: 0.75, height: 24)

            metric(title: "实际专注", value: focusFormatCompactDuration(actualDuration), color: FocusTimelineColors.actual)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ModernPalette.line.opacity(0.56), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("计划 \(focusFormatCompactDuration(plannedDuration))，实际专注 \(focusFormatCompactDuration(actualDuration))")
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ModernPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ModernPalette.ink)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FocusWeekStrip: View {
    @Binding var selectedDate: Date

    let onSelect: () -> Void

    private let calendar = Calendar.current

    private var dates: [Date] {
        let today = calendar.startOfDay(for: .now)
        return (-3...3).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(dates, id: \.self) { date in
                let selected = calendar.isDate(date, inSameDayAs: selectedDate)

                Button {
                    selectedDate = date
                    onSelect()
                } label: {
                    VStack(spacing: 4) {
                        Text(focusWeekday(date))
                            .font(.system(size: 10, weight: selected ? .semibold : .medium))
                            .lineLimit(1)
                        Text("\(date.formatted(.dateTime.day()))日")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(selected ? ModernPalette.blue : ModernPalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(selected ? ModernPalette.blue.opacity(0.055) : ModernPalette.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                selected ? ModernPalette.blue.opacity(0.64) : ModernPalette.line.opacity(0.55),
                                lineWidth: selected ? 1.1 : 0.75
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(focusLongDate(date))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

private enum FocusTimelineColors {
    static let planned = Color(red: 0.04, green: 0.63, blue: 0.47)
    static let actual = Color(red: 0.16, green: 0.25, blue: 0.37)
    static let actualSurface = Color(red: 0.91, green: 0.95, blue: 1.0)
    static let backfill = Color(red: 0.96, green: 0.31, blue: 0.28)
}

/// The horizontal geometry is kept as a value type so drag math can be
/// tested without launching the view. One visible hour always maps to the
/// same pixel width for both lanes.
struct FocusLinearTimelineGeometry {
    let dayStart: Date
    let visibleStart: Date
    let visibleEnd: Date
    let contentWidth: CGFloat
    let calendar: Calendar

    static let startHour = 9
    static let endHour = 19
    static let minutesPerSnap = 1

    init(day: Date, contentWidth: CGFloat, calendar: Calendar = .current) {
        let startOfDay = calendar.startOfDay(for: day)
        self.dayStart = startOfDay
        self.visibleStart = calendar.date(bySettingHour: Self.startHour, minute: 0, second: 0, of: startOfDay) ?? startOfDay
        self.visibleEnd = calendar.date(bySettingHour: Self.endHour, minute: 0, second: 0, of: startOfDay) ?? startOfDay.addingTimeInterval(10 * 3_600)
        self.contentWidth = max(1, contentWidth)
        self.calendar = calendar
    }

    var visibleDuration: TimeInterval {
        visibleEnd.timeIntervalSince(visibleStart)
    }

    func x(for date: Date) -> CGFloat {
        let ratio = date.timeIntervalSince(visibleStart) / visibleDuration
        return min(contentWidth, max(0, CGFloat(ratio) * contentWidth))
    }

    func date(atX x: CGFloat) -> Date {
        let clampedX = min(contentWidth, max(0, x))
        let raw = visibleStart.addingTimeInterval(Double(clampedX / contentWidth) * visibleDuration)
        let seconds = raw.timeIntervalSince(visibleStart)
        let snapped = (seconds / 60).rounded() * 60
        return visibleStart.addingTimeInterval(snapped)
    }

    func width(from start: Date, to end: Date) -> CGFloat {
        max(0, x(for: end) - x(for: start))
    }

    func clipped(start: Date, end: Date) -> (start: Date, end: Date)? {
        let clippedStart = max(visibleStart, start)
        let clippedEnd = min(visibleEnd, end)
        guard clippedEnd > clippedStart else { return nil }
        return (clippedStart, clippedEnd)
    }

    func minuteDelta(for pixels: CGFloat) -> TimeInterval {
        let minutes = (pixels / contentWidth * visibleDuration / 60).rounded()
        return minutes * 60
    }
}

private struct FocusBackfillRange: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date

    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

private struct FocusLinearTimeline: View {
    @Environment(AppModel.self) private var model: AppModel

    let day: Date
    let workspaceID: UUID
    let onEditEntry: (TimeEntry) -> Void
    let onDeleteEntry: (TimeEntry) -> Void
    let onInteraction: () -> Void

    @State private var dragStart: Date?
    @State private var dragEnd: Date?
    @State private var backfillSelection: FocusBackfillRange?

    // The label rail is deliberately wide enough to keep both lane names
    // readable. The time grid then fills all remaining width edge-to-edge.
    private let axisWidth: CGFloat = 150
    let axisHeight: CGFloat
    let laneHeight: CGFloat

    init(
        day: Date,
        workspaceID: UUID,
        axisHeight: CGFloat,
        laneHeight: CGFloat,
        onEditEntry: @escaping (TimeEntry) -> Void,
        onDeleteEntry: @escaping (TimeEntry) -> Void,
        onInteraction: @escaping () -> Void
    ) {
        self.day = day
        self.workspaceID = workspaceID
        self.axisHeight = axisHeight
        self.laneHeight = laneHeight
        self.onEditEntry = onEditEntry
        self.onDeleteEntry = onDeleteEntry
        self.onInteraction = onInteraction
    }

    var body: some View {
        let plannedTasks = model.focusPlannedTasks(on: day, workspaceID: workspaceID)
        let entries = model.focusTimeEntries(on: day, workspaceID: workspaceID)
        let activeTimer = model.activeTimer

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("当天时间轴")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                Spacer()
                Text("拖动实际专注轨道补录 · 每分钟吸附")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ModernPalette.muted)
            }

            GeometryReader { proxy in
                let contentWidth = max(180, proxy.size.width - axisWidth)
                let geometry = FocusLinearTimelineGeometry(day: day, contentWidth: contentWidth)

                ZStack(alignment: .topLeading) {
                    timelineCanvas(
                        proxy: proxy,
                        geometry: geometry,
                        plannedTasks: plannedTasks,
                        entries: entries
                    )

                    // Only the current-time line and the active session need
                    // one-second updates. The static grid and saved records
                    // stay outside TimelineView.
                    FocusLinearTimelineLiveLayer(
                        day: day,
                        workspaceID: workspaceID,
                        activeTimer: activeTimer,
                        geometry: geometry,
                        axisWidth: axisWidth,
                        axisHeight: axisHeight,
                        laneHeight: laneHeight
                    )
                }
            }
            .frame(height: axisHeight + laneHeight * 2)
            .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(ModernPalette.line.opacity(0.62), lineWidth: 0.75)
            }
            .contentShape(Rectangle())
            .onTapGesture { onInteraction() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当天计划时间与实际专注时间轴")
    }

    @ViewBuilder
    private func timelineCanvas(
        proxy: GeometryProxy,
        geometry: FocusLinearTimelineGeometry,
        plannedTasks: [GTDTask],
        entries: [TimeEntry]
    ) -> some View {
        ZStack(alignment: .topLeading) {
            timelineGrid(proxy: proxy, geometry: geometry)

            // Keep the empty-lane gesture behind saved records. Otherwise a
            // transparent hit target would swallow the record's tap, context
            // menu, and resize handles.
            actualLaneDragTarget(geometry: geometry)

            ForEach(plannedTasks) { task in
                plannedBlock(task, geometry: geometry)
            }

            ForEach(entries) { entry in
                FocusLinearActualBlock(
                    entry: entry,
                    geometry: geometry,
                    axisWidth: axisWidth,
                    laneY: axisHeight + laneHeight + 14,
                    laneHeight: laneHeight,
                    onEdit: onEditEntry,
                    onDelete: onDeleteEntry,
                    onInteraction: onInteraction,
                    onCommit: { _ = model.updateTimeEntry($0) }
                )
            }

            if let dragRange = currentDragRange {
                backfillOverlay(range: dragRange, geometry: geometry)
            }
        }
        .frame(width: proxy.size.width, height: axisHeight + laneHeight * 2)
    }

    private var currentDragRange: FocusBackfillRange? {
        guard let start = dragStart, let end = dragEnd, end > start else {
            return backfillSelection
        }
        return FocusBackfillRange(start: start, end: end)
    }

    private func timelineGrid(
        proxy: GeometryProxy,
        geometry: FocusLinearTimelineGeometry
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(ModernPalette.panel)
                .frame(width: proxy.size.width, height: axisHeight + laneHeight * 2)

            Rectangle()
                .fill(ModernPalette.subtle.opacity(0.32))
                .frame(width: geometry.contentWidth, height: laneHeight)
                .offset(x: axisWidth, y: axisHeight)

            Rectangle()
                .fill(ModernPalette.panel)
                .frame(width: geometry.contentWidth, height: laneHeight)
                .offset(x: axisWidth, y: axisHeight + laneHeight)

            ForEach(0...20, id: \.self) { step in
                let isMajor = step.isMultiple(of: 2)
                let x = axisWidth + CGFloat(step) / 20 * geometry.contentWidth

                Rectangle()
                    .fill(ModernPalette.line.opacity(isMajor ? 0.62 : 0.28))
                    .frame(width: isMajor ? 0.75 : 0.55, height: laneHeight * 2)
                    .offset(x: x, y: axisHeight)

                if isMajor {
                    Text(String(format: "%02d:00", FocusLinearTimelineGeometry.startHour + step / 2))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(ModernPalette.muted)
                        .frame(width: 52, alignment: step == 20 ? .trailing : .leading)
                        .offset(x: x - (step == 20 ? 52 : 0), y: 12)
                }
            }

            Rectangle()
                .fill(ModernPalette.line.opacity(0.62))
                .frame(width: proxy.size.width, height: 0.75)
                .offset(y: axisHeight)

            Rectangle()
                .fill(ModernPalette.line.opacity(0.62))
                .frame(width: proxy.size.width, height: 0.75)
                .offset(y: axisHeight + laneHeight)

            Text("时间")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(ModernPalette.muted)
                .padding(.leading, 12)
                .offset(y: 11)

            laneLabel("计划时间", color: ModernPalette.blue, y: axisHeight)
            laneLabel("实际专注时间", color: FocusTimelineColors.actual, y: axisHeight + laneHeight)
        }
    }

    private func laneLabel(_ title: String, color: Color, y: CGFloat) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ModernPalette.ink)
                .lineLimit(1)
        }
        .frame(width: axisWidth - 10, alignment: .leading)
        .offset(x: 12, y: y + laneHeight / 2 - 9)
    }

    @ViewBuilder
    private func plannedBlock(
        _ task: GTDTask,
        geometry: FocusLinearTimelineGeometry
    ) -> some View {
        if let start = task.plannedStart {
            let end = task.plannedEnd ?? start.addingTimeInterval(60)
            let projectColor = Color(hex: model.project(for: task)?.colorHex ?? model.currentWorkspace.colorHex)

            if let clipped = geometry.clipped(start: start, end: end) {
                let width = max(6, geometry.width(from: clipped.start, to: clipped.end))
                FocusLinearPlanBlock(
                    title: task.title,
                    timeText: task.plannedEnd.map { focusTimeRange(start: start, end: $0) } ?? start.formatted(date: .omitted, time: .shortened),
                    color: projectColor,
                    compact: width < 116,
                    point: task.plannedEnd == nil
                )
                .frame(width: width, height: laneHeight - 24)
                .offset(x: axisWidth + geometry.x(for: clipped.start), y: axisHeight + 12)
            }
        }
    }

    private func actualLaneDragTarget(geometry: FocusLinearTimelineGeometry) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: geometry.contentWidth, height: laneHeight)
            .offset(x: axisWidth, y: axisHeight + laneHeight)
            .gesture(backfillGesture(geometry: geometry))
            .accessibilityLabel("实际专注时间轴补录区域")
            .accessibilityHint("拖动选择开始和结束时间，松开后选择已有任务")
    }

    private func backfillOverlay(
        range: FocusBackfillRange,
        geometry: FocusLinearTimelineGeometry
    ) -> some View {
        let x = axisWidth + geometry.x(for: range.start)
        let width = max(6, geometry.width(from: range.start, to: range.end))

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(FocusTimelineColors.backfill.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(FocusTimelineColors.backfill.opacity(0.86), lineWidth: 1.25)
                }
                .frame(width: width, height: laneHeight - 24)

            Circle()
                .fill(ModernPalette.panel)
                .overlay {
                    Circle()
                        .stroke(FocusTimelineColors.backfill.opacity(0.95), lineWidth: 1.5)
                }
                .frame(width: 17, height: 17)
                .offset(x: -8.5)

            Circle()
                .fill(ModernPalette.panel)
                .overlay {
                    Circle()
                        .stroke(FocusTimelineColors.backfill.opacity(0.95), lineWidth: 1.5)
                }
                .frame(width: 17, height: 17)
                .offset(x: width - 8.5)

            Text(focusTimeRange(start: range.start, end: range.end))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(FocusTimelineColors.backfill)
                .frame(width: width, alignment: .center)
        }
        .frame(width: width, height: laneHeight - 24)
        .offset(x: x, y: axisHeight + laneHeight + 12)
        .zIndex(20)
        .popover(item: $backfillSelection, attachmentAnchor: .rect(.bounds), arrowEdge: .top) { selection in
            FocusBackfillPopover(
                range: selection,
                workspaceID: workspaceID,
                onCancel: { backfillSelection = nil },
                onSave: { taskID, note in
                    _ = model.addTimeEntry(
                        workspaceID: workspaceID,
                        taskID: taskID,
                        startedAt: selection.start,
                        endedAt: selection.end,
                        source: .stopwatch,
                        note: note
                    )
                    backfillSelection = nil
                }
            )
            .environment(model)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("补录时间，\(focusTimeRange(start: range.start, end: range.end))")
    }

    private func backfillGesture(geometry: FocusLinearTimelineGeometry) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let start = geometry.date(atX: value.startLocation.x)
                let current = geometry.date(atX: value.location.x)
                let rangeStart = min(start, current)
                let rangeEnd = max(start, current)
                dragStart = rangeStart
                dragEnd = rangeEnd > rangeStart ? rangeEnd : rangeStart.addingTimeInterval(60)
            }
            .onEnded { _ in
                defer {
                    dragStart = nil
                    dragEnd = nil
                }
                guard let start = dragStart, let end = dragEnd, end > start else { return }
                backfillSelection = FocusBackfillRange(start: start, end: end)
            }
    }

}

/// A deliberately small dynamic layer for C234. `TimelineView` invalidates
/// only this view once per second; the static timeline keeps its own identity
/// and receives no per-tick model queries.
private struct FocusLinearTimelineLiveLayer: View {
    let day: Date
    let workspaceID: UUID
    let activeTimer: ActiveTimer?
    let geometry: FocusLinearTimelineGeometry
    let axisWidth: CGFloat
    let axisHeight: CGFloat
    let laneHeight: CGFloat

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack(alignment: .topLeading) {
                if let activeTimer,
                   (activeTimer.workspaceID ?? workspaceID) == workspaceID,
                   let activeInterval = activeInterval(activeTimer, now: context.date),
                   let clipped = geometry.clipped(start: activeInterval.start, end: activeInterval.end) {
                    activeBlock(activeTimer, interval: clipped)
                }

                if let currentTimeX = currentTimeX(now: context.date) {
                    currentTimeLine(x: currentTimeX, now: context.date)
                }
            }
            .frame(
                width: axisWidth + geometry.contentWidth,
                height: axisHeight + laneHeight * 2,
                alignment: .topLeading
            )
        }
        .allowsHitTesting(false)
        // The running session's accessible status is already exposed by the
        // clock face; hiding this per-second decorative layer avoids creating
        // an accessibility update on every tick.
        .accessibilityHidden(true)
    }

    private func activeInterval(_ timer: ActiveTimer, now: Date) -> DateInterval? {
        let end = timer.pausedAt ?? now
        guard end > timer.sessionStartedAt else { return nil }
        return DateInterval(start: timer.sessionStartedAt, end: end)
    }

    private func activeBlock(
        _ timer: ActiveTimer,
        interval: (start: Date, end: Date)
    ) -> some View {
        let width = max(8, geometry.width(from: interval.start, to: interval.end))
        let title = timer.taskID == nil ? "无任务专注" : timer.title
        let elapsedText = focusFormatCompactDuration(interval.end.timeIntervalSince(interval.start))
        let text = timer.pausedAt == nil ? "进行中 · \(elapsedText)" : "已暂停 · \(elapsedText)"

        return HStack(spacing: 7) {
            Circle()
                .fill(ModernPalette.blue)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(ModernPalette.blue)
        .padding(.horizontal, 9)
        .frame(width: width, height: laneHeight - 24, alignment: .leading)
        .background(ModernPalette.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(ModernPalette.blue.opacity(0.68), lineWidth: 1)
        }
        .offset(x: axisWidth + geometry.x(for: interval.start), y: axisHeight + laneHeight + 12)
    }

    private func currentTimeX(now: Date) -> CGFloat? {
        guard Calendar.current.isDateInToday(day),
              now >= geometry.visibleStart,
              now <= geometry.visibleEnd else { return nil }
        return geometry.x(for: now)
    }

    private func currentTimeLine(x: CGFloat, now: Date) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(ModernPalette.red.opacity(0.9))
                .frame(width: 1.5, height: laneHeight * 2)
                .offset(y: axisHeight)

            Text(now.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .frame(height: 19)
                .background(ModernPalette.red, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .frame(width: 1.5, height: axisHeight + laneHeight * 2, alignment: .top)
        .offset(x: axisWidth + x - 0.75)
        .zIndex(30)
    }
}

private struct FocusLinearPlanBlock: View {
    let title: String
    let timeText: String
    let color: Color
    let compact: Bool
    let point: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(.white.opacity(0.92))
                .frame(width: 7, height: 7)

            if compact {
                Text(point ? timeText : title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(title)
                        .font(.system(size: 10.5, weight: .medium))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(color.opacity(0.91), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(color.opacity(0.98), lineWidth: 0.75)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("计划时间，\(timeText)，\(title)")
    }
}

private enum FocusResizeEdge {
    case leading
    case trailing
}

private struct FocusLinearActualBlock: View {
    let entry: TimeEntry
    let geometry: FocusLinearTimelineGeometry
    let axisWidth: CGFloat
    let laneY: CGFloat
    let laneHeight: CGFloat
    let onEdit: (TimeEntry) -> Void
    let onDelete: (TimeEntry) -> Void
    let onInteraction: () -> Void
    let onCommit: (TimeEntry) -> Void

    @State private var draftStart: Date?
    @State private var draftEnd: Date?
    @State private var moveOriginStart: Date?
    @State private var moveOriginEnd: Date?
    @State private var resizeOriginStart: Date?
    @State private var resizeOriginEnd: Date?
    @State private var hovering = false

    private var displayedStart: Date { draftStart ?? entry.startedAt }
    private var displayedEnd: Date { draftEnd ?? entry.endedAt }
    private var clipped: (start: Date, end: Date)? {
        geometry.clipped(start: displayedStart, end: displayedEnd)
    }

    var body: some View {
        if let clipped {
            let width = max(8, geometry.width(from: clipped.start, to: clipped.end))
            ZStack {
                HStack(spacing: 7) {
                    Image(systemName: entry.source == .pomodoro ? "timer" : "stopwatch")
                        .font(.system(size: 10, weight: .semibold))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(focusTimeRange(start: clipped.start, end: clipped.end))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text(entry.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .foregroundStyle(FocusTimelineColors.actual)
                .padding(.horizontal, 9)
                .frame(width: width, height: laneHeight - 24, alignment: .leading)
                .background(FocusTimelineColors.actualSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(FocusTimelineColors.actual.opacity(0.55), lineWidth: 0.9)
                }

                HStack {
                    resizeHandle(.leading)
                    Spacer(minLength: 0)
                    resizeHandle(.trailing)
                }
                .frame(width: width, height: laneHeight - 24)
            }
            .frame(width: width, height: laneHeight - 24)
            .offset(x: axisWidth + geometry.x(for: clipped.start), y: laneY)
            .contentShape(Rectangle())
            .gesture(moveGesture)
            .onTapGesture {
                onInteraction()
                onEdit(entry)
            }
            .contextMenu {
                Button {
                    onEdit(entry)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDelete(entry)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
            .onHover { hovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "实际专注，\(entry.title)，\(focusTimeRange(start: clipped.start, end: clipped.end))，实际时长 \(focusFormatCompactDuration(entry.duration))"
            )
            .accessibilityHint("点击编辑；拖动主体移动时间，拖动左右边缘调整时长；右键打开菜单")
        }
    }

    private func resizeHandle(_ edge: FocusResizeEdge) -> some View {
        Capsule()
            .fill(FocusTimelineColors.actual.opacity(hovering ? 0.86 : 0.32))
            .frame(width: 5, height: 30)
            .frame(width: 14, height: laneHeight - 30)
            .contentShape(Rectangle())
            .gesture(resizeGesture(edge))
            .accessibilityLabel(edge == .leading ? "调整实际专注开始时间" : "调整实际专注结束时间")
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if moveOriginStart == nil {
                    moveOriginStart = entry.startedAt
                    moveOriginEnd = entry.endedAt
                }
                guard let originStart = moveOriginStart, let originEnd = moveOriginEnd else { return }

                let duration = max(60, originEnd.timeIntervalSince(originStart))
                let delta = geometry.minuteDelta(for: value.translation.width)
                let latestStart = min(
                    max(originStart.addingTimeInterval(delta), geometry.visibleStart),
                    max(geometry.visibleStart, geometry.visibleEnd.addingTimeInterval(-duration))
                )
                draftStart = latestStart
                draftEnd = latestStart.addingTimeInterval(duration)
            }
            .onEnded { _ in
                commitDraft()
                moveOriginStart = nil
                moveOriginEnd = nil
            }
    }

    private func resizeGesture(_ edge: FocusResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if resizeOriginStart == nil {
                    resizeOriginStart = entry.startedAt
                    resizeOriginEnd = entry.endedAt
                }
                guard let originStart = resizeOriginStart, let originEnd = resizeOriginEnd else { return }

                let delta = geometry.minuteDelta(for: value.translation.width)
                switch edge {
                case .leading:
                    let latestStart = min(
                        max(originStart.addingTimeInterval(delta), geometry.visibleStart),
                        originEnd.addingTimeInterval(-60)
                    )
                    draftStart = latestStart
                    draftEnd = originEnd
                case .trailing:
                    let latestEnd = max(
                        min(originEnd.addingTimeInterval(delta), geometry.visibleEnd),
                        originStart.addingTimeInterval(60)
                    )
                    draftStart = originStart
                    draftEnd = latestEnd
                }
            }
            .onEnded { _ in
                commitDraft()
                resizeOriginStart = nil
                resizeOriginEnd = nil
            }
    }

    private func commitDraft() {
        guard let start = draftStart, let end = draftEnd, end > start else {
            draftStart = nil
            draftEnd = nil
            return
        }
        if start != entry.startedAt || end != entry.endedAt {
            var updated = entry
            updated.startedAt = start
            updated.endedAt = end
            updated.activeSeconds = end.timeIntervalSince(start)
            onCommit(updated)
        }
        draftStart = nil
        draftEnd = nil
    }
}

private struct FocusBackfillPopover: View {
    @Environment(AppModel.self) private var model: AppModel

    let range: FocusBackfillRange
    let workspaceID: UUID
    let onCancel: () -> Void
    let onSave: (UUID?, String) -> Void

    @State private var query = ""
    @State private var selectedTaskID: UUID?
    @State private var note = ""

    private var tasks: [GTDTask] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let candidates = model.focusTaskCandidates(in: workspaceID)
        guard !normalized.isEmpty else { return Array(candidates.prefix(7)) }
        return Array(
            candidates.filter { task in
                let projectName = model.project(for: task)?.name ?? ""
                return [task.title, projectName].joined(separator: " ").localizedLowercase.contains(normalized)
            }
            .prefix(7)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("补录实际专注")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ModernPalette.ink)
                Text(
                    focusTimeRange(start: range.start, end: range.end)
                        + " · "
                        + focusFormatCompactDuration(range.duration)
                )
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(ModernPalette.muted)
            }

            TextField("搜索已有任务", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    taskButton(
                        title: "不关联任务",
                        subtitle: "记录为无任务专注",
                        color: ModernPalette.muted.opacity(0.72),
                        taskID: nil
                    )

                    ForEach(tasks) { task in
                        taskButton(
                            title: task.title,
                            subtitle: model.project(for: task)?.name ?? "无项目",
                            color: Color(hex: model.project(for: task)?.colorHex ?? model.currentWorkspace.colorHex),
                            taskID: task.id
                        )
                    }
                }
            }
            .frame(maxHeight: 170)

            TextField("备注（可选）", text: $note)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            HStack(spacing: 10) {
                Button("取消") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(ModernPalette.muted)
                Spacer()
                Button("保存补录") {
                    onSave(selectedTaskID, note)
                }
                .buttonStyle(FocusPrimaryButtonStyle(tint: FocusTimelineColors.backfill))
                .frame(width: 112)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(ModernPalette.canvas)
    }

    private func taskButton(
        title: String,
        subtitle: String,
        color: Color,
        taskID: UUID?
    ) -> some View {
        let selected = taskID == selectedTaskID

        return Button {
            selectedTaskID = taskID
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(ModernPalette.ink)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(ModernPalette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 5)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(ModernPalette.blue)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(selected ? ModernPalette.blue.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FocusEntryEditorSheet: View {
    @Environment(AppModel.self) private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let entry: TimeEntry?
    let workspaceID: UUID
    let defaultDate: Date

    @State private var taskID: UUID?
    @State private var entryDate: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var source: TimerMode
    @State private var note: String
    @State private var validationMessage: String?

    private let calendar = Calendar.current

    init(entry: TimeEntry?, workspaceID: UUID, defaultDate: Date) {
        self.entry = entry
        self.workspaceID = workspaceID
        self.defaultDate = defaultDate

        let calendar = Calendar.current
        let baseDate = calendar.startOfDay(for: entry?.startedAt ?? defaultDate)
        let fallbackStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: baseDate) ?? baseDate
        let fallbackEnd = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: baseDate) ?? baseDate.addingTimeInterval(3_600)
        _taskID = State(initialValue: entry?.taskID)
        _entryDate = State(initialValue: baseDate)
        _startTime = State(initialValue: entry?.startedAt ?? fallbackStart)
        _endTime = State(initialValue: entry?.endedAt ?? fallbackEnd)
        _source = State(initialValue: entry?.source ?? .stopwatch)
        _note = State(initialValue: entry?.note ?? "")
    }

    private var availableTasks: [GTDTask] {
        model.focusTaskCandidates(in: workspaceID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry == nil ? "补录实际专注" : "编辑实际专注")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ModernPalette.ink)
                    Text("实际记录独立于计划时间和截止时间")
                        .font(.system(size: 11.5))
                        .foregroundStyle(ModernPalette.muted)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ModernPalette.muted)
                .help("关闭")
            }
            .padding(.bottom, 18)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    editorField("任务") {
                        Picker("任务", selection: $taskID) {
                            Text("不关联任务").tag(nil as UUID?)
                            ForEach(availableTasks) { task in
                                Text(task.title).tag(Optional(task.id))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    editorField("日期") {
                        DatePicker("日期", selection: $entryDate, displayedComponents: [.date])
                            .labelsHidden()
                    }

                    HStack(spacing: 16) {
                        editorField("开始") {
                            DatePicker("开始", selection: $startTime, displayedComponents: [.hourAndMinute])
                                .labelsHidden()
                        }
                        editorField("结束") {
                            DatePicker("结束", selection: $endTime, displayedComponents: [.hourAndMinute])
                                .labelsHidden()
                        }
                    }

                    editorField("来源") {
                        Picker("来源", selection: $source) {
                            Text("正计时").tag(TimerMode.stopwatch)
                            Text("番茄钟").tag(TimerMode.pomodoro)
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("备注")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(ModernPalette.muted)
                        TextEditor(text: $note)
                            .font(.system(size: 12.5))
                            .foregroundStyle(ModernPalette.ink)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 76)
                            .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(ModernPalette.line.opacity(0.58), lineWidth: 0.75)
                            }
                    }

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(ModernPalette.red)
                    }
                }
            }

            HStack(spacing: 12) {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(ModernPalette.muted)
                Button(entry == nil ? "补录" : "保存") {
                    save()
                }
                .buttonStyle(FocusPrimaryButtonStyle(tint: ModernPalette.blue))
                .frame(width: 112)
            }
            .padding(.top, 18)
        }
        .padding(24)
        .background(ModernPalette.canvas)
    }

    private func editorField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(ModernPalette.muted)
            content()
                .font(.system(size: 12.5))
                .foregroundStyle(ModernPalette.ink)
                .padding(.horizontal, 9)
                .frame(height: 32, alignment: .leading)
                .background(ModernPalette.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(ModernPalette.line.opacity(0.58), lineWidth: 0.75)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func combinedDate(from time: Date) -> Date {
        let day = calendar.dateComponents([.year, .month, .day], from: entryDate)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var components = day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = 0
        return calendar.date(from: components) ?? time
    }

    private func save() {
        let start = combinedDate(from: startTime)
        let end = combinedDate(from: endTime)
        guard end > start else {
            validationMessage = "结束时间必须晚于开始时间"
            return
        }

        let title = taskID.flatMap(model.task(withID:))?.title ?? "无任务专注"
        if var entry {
            entry.taskID = taskID
            entry.title = title
            entry.startedAt = start
            entry.endedAt = end
            entry.source = source
            entry.pomodoroPhase = source == .pomodoro ? (entry.pomodoroPhase ?? .focus) : nil
            entry.note = note
            entry.activeSeconds = end.timeIntervalSince(start)
            guard model.updateTimeEntry(entry) else {
                validationMessage = "这条实际专注记录已经不存在"
                return
            }
        } else {
            guard model.addTimeEntry(
                workspaceID: workspaceID,
                taskID: taskID,
                startedAt: start,
                endedAt: end,
                source: source,
                note: note
            ) != nil else {
                validationMessage = "无法保存这条实际专注记录"
                return
            }
        }
        dismiss()
    }
}

private func focusFormatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    let hours = total / 3_600
    let minutes = (total % 3_600) / 60
    let remainingSeconds = total % 60
    if hours > 0 {
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }
    return String(format: "%02d:%02d", minutes, remainingSeconds)
}

private func focusFormatCompactDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    return minutes < 1 ? "不足1分钟" : "\(minutes)分钟"
}

private func focusTimeRange(start: Date, end: Date) -> String {
    "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
}

private func focusLongDate(_ date: Date) -> String {
    date.formatted(
        .dateTime
            .year()
            .month(.defaultDigits)
            .day()
            .weekday(.wide)
            .locale(Locale(identifier: "zh_CN"))
    )
}

private func focusDayHeader(_ date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    let dateText = "\(components.year ?? 0)年\(components.month ?? 0)月\(components.day ?? 0)日"
    let prefix = Calendar.current.isDateInToday(date) ? "今天 · " : ""
    return "\(prefix)\(dateText) \(focusWeekday(date))"
}

private func focusWeekday(_ date: Date) -> String {
    let symbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    let index = max(1, min(7, Calendar.current.component(.weekday, from: date))) - 1
    return symbols[index]
}
