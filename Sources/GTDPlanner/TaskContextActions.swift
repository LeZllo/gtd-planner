import SwiftUI

extension View {
    /// Attach to a stable row, not to the transient context-menu contents.
    func plannerTaskActions(
        taskID: UUID,
        scope: TaskActionScope = .task,
        onAddChild: (() -> Void)? = nil
    ) -> some View {
        modifier(PlannerTaskActionsModifier(taskID: taskID, scope: scope, onAddChild: onAddChild))
    }
}

/// Optional visible access to exactly the same actions as a row's context menu.
struct PlannerTaskActionsButton: View {
    let taskID: UUID
    var scope: TaskActionScope = .task

    var body: some View {
        Color.clear
            .modifier(PlannerTaskActionsModifier(taskID: taskID, scope: scope, isMenuButton: true))
    }
}

private enum TaskActionSheet: String, Identifiable {
    case edit
    case schedule
    var id: String { rawValue }
}

private struct PlannerTaskActionsModifier: ViewModifier {
    @Environment(AppModel.self) private var model: AppModel
    let taskID: UUID
    let scope: TaskActionScope
    var onAddChild: (() -> Void)? = nil
    var isMenuButton = false
    @State private var presentedSheet: TaskActionSheet?
    @State private var confirmsRecurringCompletion = false

    private var task: GTDTask? { model.taskActionTask(taskID: taskID) }

    func body(content: Content) -> some View {
        Group {
            if isMenuButton {
                Menu {
                    menu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ModernPalette.accent)
                        .frame(width: 28, height: 26)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("任务操作")
                .accessibilityLabel("任务操作")
                .disabled(task == nil)
            } else {
                content.contextMenu { menu }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            if let task {
                switch sheet {
                case .edit:
                    TaskEditor(task: task)
                case .schedule:
                    TaskActionScheduleSheet(taskID: taskID, scope: scope) {
                        presentedSheet = nil
                    }
                }
            }
        }
        .alert("完成整个重复任务？", isPresented: $confirmsRecurringCompletion) {
            Button("取消", role: .cancel) { }
            Button("完成整个任务") {
                // Resolve again after confirmation; never approve a different
                // task or an action whose scope changed while the alert was up.
                guard model.taskActionCompletion(taskID: taskID, scope: scope).requiresConfirmation else { return }
                model.performTaskCompletionAction(taskID: taskID, scope: scope, confirmRecurringTask: true)
            }
        } message: {
            Text("这会完成整个重复任务及其子任务，之后不再显示每天的待办。若只完成今天，请到“今天”完成当天实例。")
        }
        .onChange(of: model.selection.selectedWorkspaceID) { _, _ in dismissPresentation() }
        .onChange(of: taskID) { _, _ in dismissPresentation() }
        .onChange(of: scope) { _, _ in dismissPresentation() }
        .onChange(of: task == nil) { _, missing in
            if missing { dismissPresentation() }
        }
    }

    /// Three short groups, with just one level of submenus. Keyboard shortcuts
    /// live in app commands, so the same key is not registered once per row.
    @ViewBuilder
    private var menu: some View {
        if let task {
            Button {
                guard model.taskActionTask(taskID: taskID) != nil else { return }
                model.selectTask(taskID)
            } label: {
                Label("查看详情", systemImage: "sidebar.right")
            }
            let completion = model.taskActionCompletion(taskID: taskID, scope: scope)
            if completion.isEnabled {
                Button {
                    let current = model.taskActionCompletion(taskID: taskID, scope: scope)
                    if current.requiresConfirmation {
                        confirmsRecurringCompletion = true
                    } else {
                        model.performTaskCompletionAction(taskID: taskID, scope: scope)
                    }
                } label: {
                    Label(completion.title, systemImage: completion.systemImage)
                }
            }
            if let onAddChild {
                Button {
                    guard model.taskActionTask(taskID: taskID) != nil else { return }
                    onAddChild()
                } label: {
                    Label("添加下级任务", systemImage: "plus")
                }
            }

            Divider()

            if !task.status.isFinished {
                Button {
                    guard model.taskActionTask(taskID: taskID)?.status.isFinished == false else { return }
                    presentedSheet = .schedule
                } label: {
                    Label("安排时段…", systemImage: "calendar.badge.clock")
                }
            }
            Menu {
                ForEach(Priority.allCases) { priority in
                    Button {
                        model.setTaskPriority(taskID: taskID, priority: priority)
                    } label: {
                        if task.priority == priority {
                            Label(priority.title, systemImage: "checkmark")
                        } else {
                            Text(priority.title)
                        }
                    }
                }
            } label: {
                Label("优先级", systemImage: "flag")
            }
            Menu {
                Button("今天截止") { model.setTaskDeadline(taskID: taskID, shortcut: .today) }
                Button("明天截止") { model.setTaskDeadline(taskID: taskID, shortcut: .tomorrow) }
                if task.deadline != nil {
                    Button("清除截止时间") { model.setTaskDeadline(taskID: taskID, shortcut: nil) }
                }
            } label: {
                Label("截止时间", systemImage: "calendar.badge.exclamationmark")
            }
            Button {
                guard model.taskActionTask(taskID: taskID) != nil else { return }
                presentedSheet = .edit
            } label: {
                Label("详细编辑…", systemImage: "square.and.pencil")
            }

            Divider()

            Button {
                model.duplicateTask(taskID: taskID)
            } label: {
                Label("复制任务", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                model.requestTaskActionDeletion(taskID: taskID)
            } label: {
                Label("删除任务…", systemImage: "trash")
            }
        }
    }

    private func dismissPresentation() {
        presentedSheet = nil
        confirmsRecurringCompletion = false
    }
}

private struct TaskActionScheduleSheet: View {
    @Environment(AppModel.self) private var model: AppModel
    let taskID: UUID
    let onDismiss: () -> Void
    @State private var day: Date

    init(taskID: UUID, scope: TaskActionScope, onDismiss: @escaping () -> Void) {
        self.taskID = taskID
        self.onDismiss = onDismiss
        _day = State(initialValue: TaskActionRules.schedulingDay(scope: scope))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DatePicker("安排日期", selection: $day,
                       in: Calendar.current.startOfDay(for: .now)...,
                       displayedComponents: .date)
                .padding([.horizontal, .top], 16)
                .tint(ModernPalette.accent)
            if let task = model.taskActionTask(taskID: taskID) {
                DayScheduleEditor(task: task, day: day, onSaved: onDismiss)
                    // Changing day creates a fresh time draft. Cancel never
                    // writes either the prior date's or this date's draft.
                    .id(Calendar.current.startOfDay(for: day))
            } else {
                Text("任务已删除或移出当前工作区")
                    .padding()
                Button("关闭", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                    .padding()
            }
        }
    }
}
