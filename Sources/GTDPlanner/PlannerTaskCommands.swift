import AppKit
import SwiftUI

private struct PlannerTaskModelKey: FocusedValueKey {
    typealias Value = AppModel
}
private struct PlannerNewTaskActionKey: FocusedValueKey {
    typealias Value = @MainActor () -> Void
}
extension FocusedValues {
    var plannerTaskModel: AppModel? {
        get { self[PlannerTaskModelKey.self] }
        set { self[PlannerTaskModelKey.self] = newValue }
    }
    var plannerNewTaskAction: (@MainActor () -> Void)? {
        get { self[PlannerNewTaskActionKey.self] }
        set { self[PlannerNewTaskActionKey.self] = newValue }
    }
}

@MainActor
struct PlannerTaskCommands: Commands {
    let model: AppModel
    @FocusedValue(\.plannerTaskModel) private var focusedModel
    @FocusedValue(\.plannerNewTaskAction) private var newTaskAction

    private var selectedTaskID: UUID? {
        guard focusedModel === model,
              !(NSApp.keyWindow?.firstResponder is NSTextView),
              model.selection.focusMode == nil, model.selection.selectedArchive == nil,
              let selection = model.selection.taskSelection,
              selection.context == model.currentTaskSelectionContext,
              model.taskActionTask(taskID: selection.taskID) != nil else { return nil }
        return selection.taskID
    }

    private var scope: TaskActionScope {
        guard model.selection.selectedOrganization == nil else { return .task }
        switch model.selection.selectedSmartList {
        case .today: return .day(Calendar.current.startOfDay(for: .now))
        case .tomorrow, .recent, .calendar:
            return .day(model.defaultTaskPlanningDay() ?? .now)
        default: return .task
        }
    }

    private var completion: TaskActionCompletion {
        selectedTaskID.map { model.taskActionCompletion(taskID: $0, scope: scope) } ?? .unavailable
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新建任务") { newTaskAction?() }
                .keyboardShortcut("n", modifiers: [.command])
                .disabled(newTaskAction == nil)
        }
        CommandMenu("任务") {
            Button(completion.title) { performCompletion() }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(selectedTaskID == nil || !completion.isEnabled)
            Button("复制选中任务") {
                if let id = selectedTaskID { _ = model.duplicateTask(taskID: id) }
            }
            .keyboardShortcut("d", modifiers: [.command])
            .disabled(selectedTaskID == nil)
            Divider()
            Button("将选中任务移入垃圾箱…") {
                if let id = selectedTaskID { _ = model.requestTaskActionDeletion(taskID: id) }
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(selectedTaskID == nil)
        }
    }

    private func performCompletion() {
        guard let id = selectedTaskID else { return }
        let actionScope = scope
        let action = model.taskActionCompletion(taskID: id, scope: actionScope)
        guard action.isEnabled else { return }
        if action.requiresConfirmation {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "完成整个重复任务？"
            alert.informativeText = "这会完成整个重复任务及其子任务，之后不再显示每天的待办。只完成今天，请到今天视图完成当天实例。"
            alert.addButton(withTitle: "取消")
            alert.addButton(withTitle: "完成整个任务")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        _ = model.performTaskCompletionAction(taskID: id, scope: actionScope, confirmRecurringTask: action.requiresConfirmation)
    }
}
