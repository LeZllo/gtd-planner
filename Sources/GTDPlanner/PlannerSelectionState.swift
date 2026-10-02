import Foundation
import Observation

enum TodayViewMode: String, CaseIterable, Identifiable, Sendable {
    case list
    case schedule

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "清单"
        case .schedule: "日程"
        }
    }
}

/// Navigation state is intentionally separate from the database snapshot.
///
/// SwiftUI views can observe this object without observing every mutation made
/// to tasks, projects, or persistence metadata. Views read this object
/// directly for selection-driven updates; persistence and query caches remain
/// outside the navigation state.
@MainActor
@Observable
final class PlannerSelectionState {
    var selectedWorkspaceID: UUID
    var selectedOrganization: OrganizationItem? = .projects
    var selectedSmartList: SmartList = .all
    var selectedArchive: ArchiveItem?
    var plannerView: PlannerView = .list
    var todayViewMode: TodayViewMode = .schedule
    /// A draft destination in future planning, never persisted as task data.
    var planningDay: Date?
    var calendarDay: Date?
    /// When non-nil, C2 + C3 + C4 are replaced by the C234 focus workspace.
    /// This is navigation state, not timer state: leaving C234 never stops an
    /// active timer, and an active timer remains the persistence source of truth.
    var focusMode: TimerMode?
    var selectedProjectID: UUID?
    var selectedTag: TagSelection?
    private(set) var taskSelection: TaskSelection?

    init(selectedWorkspaceID: UUID) {
        self.selectedWorkspaceID = selectedWorkspaceID
    }

    func selectTask(_ taskSelection: TaskSelection) {
        self.taskSelection = taskSelection
    }

    func clearSelectedTask() {
        taskSelection = nil
    }
}
