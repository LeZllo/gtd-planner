import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case inbox
    case open
    case inProgress = "in-progress"
    case waiting
    case someday
    case done
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "收集箱"
        case .open: "未开始"
        case .inProgress: "进行中"
        case .waiting: "等待中"
        case .someday: "某天/也许"
        case .done: "已完成"
        case .cancelled: "已取消"
        }
    }

    var icon: String {
        switch self {
        case .inbox: "tray"
        case .open: "circle"
        case .inProgress: "play.circle"
        case .waiting: "hourglass"
        case .someday: "lightbulb"
        case .done: "checkmark.circle"
        case .cancelled: "minus.circle"
        }
    }

    var isFinished: Bool { self == .done || self == .cancelled }
}

enum Priority: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "无"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }

    var color: String {
        switch self {
        case .none: "#9AA5AE"
        case .low: "#4D9DE0"
        case .medium: "#E7B63B"
        case .high: "#E85C55"
        }
    }
}

/// A task's next-action lane is independent from lifecycle status. A task can
/// be active and waiting, or completed after having been a next action; keeping
/// this as its own field preserves both meanings for filtering and reporting.
enum ActionList: String, Codable, CaseIterable, Identifiable, Sendable {
    case nextAction = "next-action"
    case waiting
    case somedayMaybe = "someday-maybe"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nextAction: "下一步行动"
        case .waiting: "等待中"
        case .somedayMaybe: "将来/也许"
        }
    }

    var icon: String {
        switch self {
        case .nextAction: "arrow.right.circle"
        case .waiting: "hourglass"
        case .somedayMaybe: "lightbulb"
        }
    }
}

enum DeadlinePrecision: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case date
    case minute

    var id: String { rawValue }
}

/// Describes why a task owns a multi-day planned range. The range itself stays
/// in `plannedStart` / `plannedEnd`; this value prevents UI-05 from guessing
/// intent from the number of calendar days.
enum TaskPlanRangeIntent: String, Codable, CaseIterable, Identifiable, Sendable {
    case progress
    case completeWithin = "complete-within"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .progress: "跨日推进"
        case .completeWithin: "区间内完成"
        }
    }

    var explanation: String {
        switch self {
        case .progress: "在计划区间内持续推进，任务最终只完成一次"
        case .completeWithin: "在计划区间内任选一天完成一次"
        }
    }

    var icon: String {
        switch self {
        case .progress: "arrow.forward"
        case .completeWithin: "calendar.badge.checkmark"
        }
    }
}

/// A concrete execution slot is a daily time-box, not a replacement for the
/// task's planned range and not an actual focus record.
struct TaskExecutionSlot: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var start: Date
    var end: Date
}

enum TimerMode: String, Codable, Sendable {
    case stopwatch
    case pomodoro
}

/// Describes how a completed actual-focus record was created. This is kept
/// separate from `TimerMode`: a manual backfill is an actual record source,
/// never a running timer mode.
enum TimeEntrySource: String, Codable, CaseIterable, Hashable, Sendable {
    case stopwatch
    case pomodoro
    case manual

    init(timerMode: TimerMode) {
        switch timerMode {
        case .stopwatch:
            self = .stopwatch
        case .pomodoro:
            self = .pomodoro
        }
    }

    var title: String {
        switch self {
        case .stopwatch: "正计时"
        case .pomodoro: "番茄钟"
        case .manual: "手动补录"
        }
    }

    var icon: String {
        switch self {
        case .stopwatch: "stopwatch"
        case .pomodoro: "timer"
        case .manual: "clock.arrow.circlepath"
        }
    }
}

enum PomodoroPhase: String, Codable, Sendable {
    case focus
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .focus: "专注"
        case .shortBreak: "短休息"
        case .longBreak: "长休息"
        }
    }
}

enum SmartList: String, CaseIterable, Identifiable, Sendable {
    case all
    case inbox
    case today
    case tomorrow
    case recent
    case fourSquares
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .inbox: "收集箱"
        case .today: "今天"
        case .tomorrow: "明天"
        case .recent: "最近七天"
        case .fourSquares: "四象限"
        case .calendar: "日历"
        }
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .inbox: "tray"
        case .today: "calendar.badge.checkmark"
        case .tomorrow: "calendar.badge.clock"
        case .recent: "calendar.badge.checkmark"
        case .fourSquares: "square.grid.2x2"
        case .calendar: "calendar"
        }
    }
}

enum OrganizationItem: String, CaseIterable, Identifiable, Sendable {
    case inbox
    case projects
    case tags
    case filters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "收集箱"
        case .projects: "项目"
        case .tags: "标签"
        case .filters: "过滤器"
        }
    }

    var icon: String {
        switch self {
        case .inbox: "tray"
        case .projects: "folder"
        case .tags: "tag"
        case .filters: "line.3.horizontal.decrease"
        }
    }
}

enum ArchiveItem: String, CaseIterable, Identifiable, Sendable {
    case logs
    case trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .logs: "日志"
        case .trash: "垃圾箱"
        }
    }

    var icon: String {
        switch self {
        case .logs: "clock.arrow.circlepath"
        case .trash: "trash"
        }
    }
}

enum PlannerView: String, CaseIterable, Identifiable, Sendable {
    case list
    case calendar
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "列表"
        case .calendar: "日历"
        case .timeline: "甘特图"
        }
    }

    var icon: String {
        switch self {
        case .list: "list.bullet"
        case .calendar: "calendar"
        case .timeline: "clock.arrow.circlepath"
        }
    }
}

struct Workspace: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var symbolName: String
    var colorHex: String
}

enum WorkspaceSortMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case name
    case recent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: "手动排序"
        case .name: "按名称"
        case .recent: "最近使用"
        }
    }
}

struct Project: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var workspaceID: UUID
    var category: String
    var name: String
    var symbolName: String
    var colorHex: String
    var note: String = ""
    /// Stable position within a workspace/category. Older databases may not
    /// contain this field; the custom decoder below keeps those files readable.
    var order: Int = 0

    private enum CodingKeys: String, CodingKey {
        case id, workspaceID, category, name, symbolName, colorHex, note, order
    }

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        category: String,
        name: String,
        colorHex: String,
        symbolName: String = "folder",
        note: String = "",
        order: Int = 0
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.category = category
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.note = note
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        workspaceID = try container.decode(UUID.self, forKey: .workspaceID)
        category = try container.decode(String.self, forKey: .category)
        name = try container.decode(String.self, forKey: .name)
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? "folder"
        colorHex = try container.decode(String.self, forKey: .colorHex)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }
}

struct ProjectCategory: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var workspaceID: UUID
    var name: String
    var colorHex: String
    var order: Int = 0

    private enum CodingKeys: String, CodingKey {
        case id, workspaceID, name, colorHex, order
    }

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        name: String,
        colorHex: String? = nil,
        order: Int = 0
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.name = name
        self.colorHex = colorHex ?? ProjectCategory.defaultColorHex(for: name)
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        workspaceID = try container.decode(UUID.self, forKey: .workspaceID)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
            ?? ProjectCategory.defaultColorHex(for: name)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }

    static func defaultColorHex(for name: String) -> String {
        let palette = ["#64748B", "#2F6FD0", "#0AA58F", "#C47A16", "#8256D0", "#C65374"]
        let hash = name.unicodeScalars.reduce(into: 0) { partial, scalar in
            partial = (partial &* 31) &+ Int(scalar.value)
        }
        return palette[abs(hash) % palette.count]
    }
}

/// A workspace-scoped category used only to organize labels in UI-03.
/// Removing a category never removes its labels; they become uncategorized.
struct TagCategory: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var workspaceID: UUID
    var name: String
    var colorHex: String
    var order: Int = 0
    var createdAt: Date = .now
    var updatedAt: Date = .now

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        name: String,
        colorHex: String? = nil,
        order: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.name = name
        self.colorHex = colorHex ?? ProjectCategory.defaultColorHex(for: name)
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Labels remain attached to tasks by name for backward compatibility, while
/// this independent entity owns the metadata required by the UI-03 manager.
struct TaskTagDefinition: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var workspaceID: UUID
    var categoryID: UUID?
    var name: String
    var colorHex: String
    var note: String = ""
    var order: Int = 0
    var createdAt: Date = .now
    var updatedAt: Date = .now

    init(
        id: UUID = UUID(),
        workspaceID: UUID,
        categoryID: UUID? = nil,
        name: String,
        colorHex: String? = nil,
        note: String = "",
        order: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.categoryID = categoryID
        self.name = name
        self.colorHex = colorHex ?? Self.defaultColorHex(for: name)
        self.note = note
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func defaultColorHex(for name: String) -> String {
        ProjectCategory.defaultColorHex(for: name)
    }
}

struct ProjectSection: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var projectID: UUID
    var name: String
    /// Section titles follow the restrained blue accent used by the reference
    /// workflow while keeping the color available for future customization.
    var colorHex: String = "#2F6FD0"
    var order: Int = 0
}

struct GTDTask: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var title: String
    var workspaceID: UUID
    var projectID: UUID?
    var sectionID: UUID? = nil
    var parentID: UUID?
    var status: TaskStatus
    var priority: Priority = .none
    var actionList: ActionList = .nextAction
    var tags: [String] = []
    var contexts: [String] = []
    var plannedStart: Date?
    var plannedEnd: Date?
    /// Precision is explicit because a date-only plan and a midnight minute-
    /// precise plan are different user choices. A missing end represents a
    /// planned point; `.none` is used only when the task has no planned start.
    var plannedPrecision: DeadlinePrecision = .none
    /// Used only when a planned range crosses calendar days. Single-day plans
    /// retain this value without changing their behavior.
    var planRangeIntent: TaskPlanRangeIntent = .progress
    /// Specific daily time-boxes. These are planned time; timer-generated
    /// `TimeEntry` values remain the source of truth for actual focus.
    var executionSlots: [TaskExecutionSlot] = []
    var deadline: Date?
    var deadlinePrecision: DeadlinePrecision = .none
    var recurrence: String = ""
    var note: String = ""
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var completedAt: Date?
    var order: Int = 0
    var completedInstances: [String] = []
    var skippedInstances: [String] = []
}

extension GTDTask {
    private enum CodingKeys: String, CodingKey {
        case id, title, workspaceID, projectID, sectionID, parentID
        case status, priority, actionList, tags, contexts
        case plannedStart, plannedEnd, plannedPrecision, planRangeIntent, executionSlots
        case deadline, deadlinePrecision, recurrence, note
        case createdAt, updatedAt, completedAt, order
        case completedInstances, skippedInstances
    }

    /// Keeps pre-SwiftData JSON backups readable. Older snapshots did not
    /// contain `plannedPrecision`; any stored planned start in those files was
    /// created by a date-time picker, so minute precision is the faithful migration.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        workspaceID = try container.decode(UUID.self, forKey: .workspaceID)
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        sectionID = try container.decodeIfPresent(UUID.self, forKey: .sectionID)
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
        status = try container.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .inbox
        priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .none
        actionList = try container.decodeIfPresent(ActionList.self, forKey: .actionList)
            ?? {
                switch status {
                case .waiting: .waiting
                case .someday: .somedayMaybe
                default: .nextAction
                }
            }()
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        contexts = try container.decodeIfPresent([String].self, forKey: .contexts) ?? []
        plannedStart = try container.decodeIfPresent(Date.self, forKey: .plannedStart)
        plannedEnd = try container.decodeIfPresent(Date.self, forKey: .plannedEnd)
        let decodedPlannedPrecision = try container.decodeIfPresent(DeadlinePrecision.self, forKey: .plannedPrecision)
            ?? (plannedStart != nil ? .minute : .none)
        plannedPrecision = if plannedStart == nil {
            .none
        } else if decodedPlannedPrecision == .none {
            .minute
        } else {
            decodedPlannedPrecision
        }
        planRangeIntent = try container.decodeIfPresent(TaskPlanRangeIntent.self, forKey: .planRangeIntent) ?? .progress
        executionSlots = try container.decodeIfPresent([TaskExecutionSlot].self, forKey: .executionSlots) ?? []
        deadline = try container.decodeIfPresent(Date.self, forKey: .deadline)
        deadlinePrecision = try container.decodeIfPresent(DeadlinePrecision.self, forKey: .deadlinePrecision) ?? .none
        recurrence = try container.decodeIfPresent(String.self, forKey: .recurrence) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        completedInstances = try container.decodeIfPresent([String].self, forKey: .completedInstances) ?? []
        skippedInstances = try container.decodeIfPresent([String].self, forKey: .skippedInstances) ?? []
    }
}

struct TimeEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var workspaceID: UUID
    var taskID: UUID?
    var title: String
    var startedAt: Date
    var endedAt: Date
    var source: TimeEntrySource
    var pomodoroPhase: PomodoroPhase?
    var note: String = ""
    /// Actual running time, excluding pauses. Older records do not have this
    /// field and fall back to their wall-clock interval for compatibility.
    var activeSeconds: TimeInterval? = nil

    var duration: TimeInterval {
        max(0, activeSeconds ?? endedAt.timeIntervalSince(startedAt))
    }
}

struct ActiveTimer: Codable, Hashable, Sendable {
    var mode: TimerMode
    /// Optional for backward-compatible decoding of timers persisted before
    /// C234 existed. New timers always retain the workspace where they began.
    var workspaceID: UUID?
    var taskID: UUID?
    var title: String
    /// The beginning of the complete focus session. `startedAt` is the
    /// beginning of the currently running segment and changes after resume.
    var sessionStartedAt: Date
    var startedAt: Date
    var pausedAt: Date?
    var accumulatedSeconds: TimeInterval
    var targetSeconds: TimeInterval?
    var phase: PomodoroPhase?
    var focusCount: Int = 0

    private enum CodingKeys: String, CodingKey {
        case mode
        case workspaceID
        case taskID
        case title
        case sessionStartedAt
        case startedAt
        case pausedAt
        case accumulatedSeconds
        case targetSeconds
        case phase
        case focusCount
    }

    init(mode: TimerMode,
         workspaceID: UUID?,
         taskID: UUID?,
         title: String,
         sessionStartedAt: Date,
         startedAt: Date,
         pausedAt: Date?,
         accumulatedSeconds: TimeInterval,
         targetSeconds: TimeInterval?,
         phase: PomodoroPhase?,
         focusCount: Int = 0) {
        self.mode = mode
        self.workspaceID = workspaceID
        self.taskID = taskID
        self.title = title
        self.sessionStartedAt = sessionStartedAt
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.accumulatedSeconds = accumulatedSeconds
        self.targetSeconds = targetSeconds
        self.phase = phase
        self.focusCount = focusCount
    }

    /// Decode timers written before `sessionStartedAt` was introduced. Those
    /// timers used `startedAt` as their only anchor, so it is the safest
    /// backward-compatible value available for an in-flight session.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(TimerMode.self, forKey: .mode)
        workspaceID = try container.decodeIfPresent(UUID.self, forKey: .workspaceID)
        taskID = try container.decodeIfPresent(UUID.self, forKey: .taskID)
        title = try container.decode(String.self, forKey: .title)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        sessionStartedAt = try container.decodeIfPresent(Date.self, forKey: .sessionStartedAt) ?? startedAt
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        accumulatedSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .accumulatedSeconds) ?? 0
        targetSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .targetSeconds)
        phase = try container.decodeIfPresent(PomodoroPhase.self, forKey: .phase)
        focusCount = try container.decodeIfPresent(Int.self, forKey: .focusCount) ?? 0
    }
}

enum TrashItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case workspace
    case project
    case task

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: "工作区"
        case .project: "项目"
        case .task: "任务"
        }
    }

    var icon: String {
        switch self {
        case .workspace: "square.grid.2x2"
        case .project: "folder"
        case .task: "checklist"
        }
    }
}

struct TrashItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var kind: TrashItemKind
    var objectID: UUID
    var workspaceID: UUID
    var name: String
    var deletedAt: Date = .now
    var workspace: Workspace?
    var project: Project?
    var projectCategories: [ProjectCategory] = []
    var projectSections: [ProjectSection]? = nil
    var tagCategories: [TagCategory]? = nil
    var tagDefinitions: [TaskTagDefinition]? = nil
    var projects: [Project] = []
    var tasks: [GTDTask] = []
    var timeEntries: [TimeEntry] = []

    var summary: String {
        switch kind {
        case .workspace:
            return "\(projects.count) 个项目 · \(tasks.count) 个任务"
        case .project:
            return "\(tasks.count) 个任务"
        case .task:
            return tasks.count > 1 ? "\(tasks.count) 个任务（含子任务）" : "1 个任务"
        }
    }
}

struct ActivityLogEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var timestamp: Date = .now
    var action: String
    var target: String
    var detail: String = ""
}

enum DeletionRequestTarget: Hashable {
    case workspace(UUID)
    case project(UUID)
    case projectSection(UUID)
    case task(UUID)
    case tagCategory(UUID)
    case tag(UUID)
    case emptyTrash
}

struct DeletionRequest: Identifiable {
    let id = UUID()
    let target: DeletionRequestTarget
    let title: String
    let message: String
    let confirmTitle: String
}

/// The visual context in which a task was selected. A UUID alone is not
/// sufficient because the same task can be rendered by a project, a smart
/// list, or the all-projects view.
struct TaskSelectionContext: Equatable, Sendable {
    let workspaceID: UUID
    let projectID: UUID?
    let smartList: SmartList
    let plannerView: PlannerView
    let organization: OrganizationItem?
    let tagSelection: TagSelection?
}

enum TagSelection: Hashable, Sendable {
    case tag(UUID)
    case untagged
}

struct TaskSelection: Equatable, Sendable {
    let taskID: UUID
    let context: TaskSelectionContext
}

struct GTDDatabase: Codable, Sendable {
    var schemaVersion: Int = 11
    var workspaces: [Workspace] = []
    /// The explicit workspace order is separate from the workspace records so
    /// older databases can keep decoding without adding presentation fields to
    /// the core Workspace value.
    var workspaceOrder: [UUID] = []
    /// Backward-compatible storage for the single default workspace. Older
    /// databases may still contain up to three shortcut IDs; normalization
    /// keeps only the first valid ID as the default.
    var pinnedWorkspaceIDs: [UUID] = []
    /// Retained for decoding older databases that used configurable shortcuts.
    var workspaceShortcutsConfigured: Bool = false
    var workspaceSortMode: WorkspaceSortMode = .manual
    var workspaceLastOpenedAt: [String: Date] = [:]
    var projects: [Project] = []
    var projectCategories: [ProjectCategory] = []
    var projectSections: [ProjectSection] = []
    var tagCategories: [TagCategory] = []
    var tagDefinitions: [TaskTagDefinition] = []
    var tasks: [GTDTask] = []
    var timeEntries: [TimeEntry] = []
    var activeTimer: ActiveTimer?
    var trashItems: [TrashItem] = []
    var activityLog: [ActivityLogEntry] = []

    init(schemaVersion: Int = 11,
         workspaces: [Workspace] = [],
         workspaceOrder: [UUID] = [],
         pinnedWorkspaceIDs: [UUID] = [],
         workspaceShortcutsConfigured: Bool = false,
         workspaceSortMode: WorkspaceSortMode = .manual,
         workspaceLastOpenedAt: [String: Date] = [:],
         projects: [Project] = [],
         projectCategories: [ProjectCategory] = [],
         projectSections: [ProjectSection] = [],
         tagCategories: [TagCategory] = [],
         tagDefinitions: [TaskTagDefinition] = [],
         tasks: [GTDTask] = [],
         timeEntries: [TimeEntry] = [],
         activeTimer: ActiveTimer? = nil,
         trashItems: [TrashItem] = [],
         activityLog: [ActivityLogEntry] = []) {
        self.schemaVersion = schemaVersion
        self.workspaces = workspaces
        self.workspaceOrder = workspaceOrder
        self.pinnedWorkspaceIDs = pinnedWorkspaceIDs
        self.workspaceShortcutsConfigured = workspaceShortcutsConfigured
        self.workspaceSortMode = workspaceSortMode
        self.workspaceLastOpenedAt = workspaceLastOpenedAt
        self.projects = projects
        self.projectCategories = projectCategories
        self.projectSections = projectSections
        self.tagCategories = tagCategories
        self.tagDefinitions = tagDefinitions
        self.tasks = tasks
        self.timeEntries = timeEntries
        self.activeTimer = activeTimer
        self.trashItems = trashItems
        self.activityLog = activityLog
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case workspaces
        case workspaceOrder
        case pinnedWorkspaceIDs
        case workspaceShortcutsConfigured
        case workspaceSortMode
        case workspaceLastOpenedAt
        case projects
        case projectCategories
        case projectSections
        case tagCategories
        case tagDefinitions
        case tasks
        case timeEntries
        case activeTimer
        case trashItems
        case activityLog
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        workspaces = try container.decodeIfPresent([Workspace].self, forKey: .workspaces) ?? []
        workspaceOrder = try container.decodeIfPresent([UUID].self, forKey: .workspaceOrder) ?? []
        pinnedWorkspaceIDs = try container.decodeIfPresent([UUID].self, forKey: .pinnedWorkspaceIDs) ?? []
        workspaceShortcutsConfigured = try container.decodeIfPresent(Bool.self, forKey: .workspaceShortcutsConfigured) ?? false
        workspaceSortMode = try container.decodeIfPresent(WorkspaceSortMode.self, forKey: .workspaceSortMode) ?? .manual
        workspaceLastOpenedAt = try container.decodeIfPresent([String: Date].self, forKey: .workspaceLastOpenedAt) ?? [:]
        projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        // This field was added after the first database format. Missing means
        // an old database; AppModel backfills categories from its projects.
        projectCategories = try container.decodeIfPresent([ProjectCategory].self, forKey: .projectCategories) ?? []
        projectSections = try container.decodeIfPresent([ProjectSection].self, forKey: .projectSections) ?? []
        tagCategories = try container.decodeIfPresent([TagCategory].self, forKey: .tagCategories) ?? []
        tagDefinitions = try container.decodeIfPresent([TaskTagDefinition].self, forKey: .tagDefinitions) ?? []
        tasks = try container.decodeIfPresent([GTDTask].self, forKey: .tasks) ?? []
        timeEntries = try container.decodeIfPresent([TimeEntry].self, forKey: .timeEntries) ?? []
        activeTimer = try container.decodeIfPresent(ActiveTimer.self, forKey: .activeTimer)
        trashItems = try container.decodeIfPresent([TrashItem].self, forKey: .trashItems) ?? []
        activityLog = try container.decodeIfPresent([ActivityLogEntry].self, forKey: .activityLog) ?? []
    }

    mutating func ensureProjectCategories() {
        var known = Set(projectCategories.map { categoryKey(workspaceID: $0.workspaceID, name: $0.name) })
        var nextOrderByWorkspace: [UUID: Int] = [:]
        for category in projectCategories {
            nextOrderByWorkspace[category.workspaceID] = max(nextOrderByWorkspace[category.workspaceID] ?? 0, category.order + 1)
        }

        for project in projects {
            let name = project.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = categoryKey(workspaceID: project.workspaceID, name: name)
            guard !known.contains(key) else { continue }
            projectCategories.append(
                ProjectCategory(
                    workspaceID: project.workspaceID,
                    name: name,
                    order: nextOrderByWorkspace[project.workspaceID] ?? 0
                )
            )
            known.insert(key)
            nextOrderByWorkspace[project.workspaceID, default: 0] += 1
        }
        schemaVersion = max(schemaVersion, 2)
    }

    /// Backfills and normalizes project positions without disturbing the
    /// order in which projects were stored in pre-sort databases.
    mutating func ensureProjectOrders() {
        var groupedIndices: [String: [Int]] = [:]
        for index in projects.indices {
            let project = projects[index]
            let key = "\(project.workspaceID.uuidString)|\(project.category.localizedLowercase)"
            groupedIndices[key, default: []].append(index)
        }

        for indices in groupedIndices.values {
            let sortedIndices = indices.sorted {
                if projects[$0].order != projects[$1].order {
                    return projects[$0].order < projects[$1].order
                }
                return $0 < $1
            }
            for (order, index) in sortedIndices.enumerated() {
                projects[index].order = order
            }
        }
        schemaVersion = max(schemaVersion, 3)
        schemaVersion = max(schemaVersion, 4)
    }

    mutating func ensureProjectSections() {
        let validProjectIDs = Set(projects.map(\.id))
        projectSections = projectSections.filter { validProjectIDs.contains($0.projectID) }

        var groupedIndices: [UUID: [Int]] = [:]
        for index in projectSections.indices {
            groupedIndices[projectSections[index].projectID, default: []].append(index)
        }

        for indices in groupedIndices.values {
            let sortedIndices = indices.sorted {
                if projectSections[$0].order != projectSections[$1].order {
                    return projectSections[$0].order < projectSections[$1].order
                }
                return projectSections[$0].name.localizedStandardCompare(projectSections[$1].name) == .orderedAscending
            }
            for (order, index) in sortedIndices.enumerated() {
                projectSections[index].order = order
            }
        }

        let validSectionIDs = Set(projectSections.map(\.id))
        for index in tasks.indices {
            if let sectionID = tasks[index].sectionID, !validSectionIDs.contains(sectionID) {
                tasks[index].sectionID = nil
            }
        }
        schemaVersion = max(schemaVersion, 8)
    }

    /// Backfills independent label entities from the task-level string arrays
    /// used by earlier databases. The operation is idempotent and preserves the
    /// task representation so existing imports and editors remain compatible.
    mutating func ensureTagDefinitions() {
        let validWorkspaceIDs = Set(workspaces.map(\.id))
        tagCategories = tagCategories.filter { validWorkspaceIDs.contains($0.workspaceID) }

        var categoryIDs = Set(tagCategories.map(\.id))
        var seenCategoryKeys = Set<String>()
        tagCategories = tagCategories.filter { category in
            let cleanName = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else {
                categoryIDs.remove(category.id)
                return false
            }
            let key = tagKey(workspaceID: category.workspaceID, name: cleanName)
            guard seenCategoryKeys.insert(key).inserted else {
                categoryIDs.remove(category.id)
                return false
            }
            return true
        }

        for index in tagCategories.indices {
            tagCategories[index].name = tagCategories[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        normalizeTagCategoryOrders()

        var seenTagKeys = Set<String>()
        tagDefinitions = tagDefinitions.compactMap { definition in
            guard validWorkspaceIDs.contains(definition.workspaceID) else { return nil }
            let cleanName = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { return nil }
            let key = tagKey(workspaceID: definition.workspaceID, name: cleanName)
            guard seenTagKeys.insert(key).inserted else { return nil }
            var normalized = definition
            normalized.name = cleanName
            if let categoryID = normalized.categoryID, !categoryIDs.contains(categoryID) {
                normalized.categoryID = nil
            }
            return normalized
        }

        var canonicalNameByKey = Dictionary(
            uniqueKeysWithValues: tagDefinitions.map {
                (tagKey(workspaceID: $0.workspaceID, name: $0.name), $0.name)
            }
        )
        var nextOrderByWorkspace: [UUID: Int] = [:]
        for definition in tagDefinitions {
            nextOrderByWorkspace[definition.workspaceID] = max(
                nextOrderByWorkspace[definition.workspaceID] ?? 0,
                definition.order + 1
            )
        }

        for taskIndex in tasks.indices {
            let workspaceID = tasks[taskIndex].workspaceID
            var normalizedNames: [String] = []
            var taskKeys = Set<String>()
            for rawName in tasks[taskIndex].tags {
                let cleanName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanName.isEmpty else { continue }
                let key = tagKey(workspaceID: workspaceID, name: cleanName)
                let canonicalName: String
                if let existingName = canonicalNameByKey[key] {
                    canonicalName = existingName
                } else {
                    canonicalName = cleanName
                    tagDefinitions.append(TaskTagDefinition(
                        workspaceID: workspaceID,
                        name: cleanName,
                        order: nextOrderByWorkspace[workspaceID] ?? 0,
                        createdAt: tasks[taskIndex].createdAt,
                        updatedAt: tasks[taskIndex].updatedAt
                    ))
                    nextOrderByWorkspace[workspaceID, default: 0] += 1
                    canonicalNameByKey[key] = canonicalName
                }
                guard taskKeys.insert(key).inserted else { continue }
                normalizedNames.append(canonicalName)
            }
            tasks[taskIndex].tags = normalizedNames
        }

        normalizeTagDefinitionOrders()
        schemaVersion = max(schemaVersion, 11)
    }

    mutating func ensureWorkspaceMetadata() {
        let validIDs = Set(workspaces.map(\.id))
        let existingOrder = workspaceOrder.filter(validIDs.contains)
        let missingIDs = workspaces.map(\.id).filter { !existingOrder.contains($0) }
        workspaceOrder = existingOrder + missingIDs
        let retainedDefaultID = pinnedWorkspaceIDs.first(where: validIDs.contains)
        let defaultID = retainedDefaultID ?? workspaceOrder.first
        pinnedWorkspaceIDs = defaultID.map { [$0] } ?? []
        workspaceShortcutsConfigured = true
        workspaceLastOpenedAt = workspaceLastOpenedAt.filter { key, _ in
            guard let id = UUID(uuidString: key) else { return false }
            return validIDs.contains(id)
        }
        schemaVersion = max(schemaVersion, 8)
    }

    private func categoryKey(workspaceID: UUID, name: String) -> String {
        "\(workspaceID.uuidString)|\(name.localizedLowercase)"
    }

    private func tagKey(workspaceID: UUID, name: String) -> String {
        "\(workspaceID.uuidString)|\(name.localizedLowercase)"
    }

    private mutating func normalizeTagCategoryOrders() {
        let grouped = Dictionary(grouping: tagCategories.indices, by: { tagCategories[$0].workspaceID })
        for indices in grouped.values {
            let ordered = indices.sorted {
                if tagCategories[$0].order != tagCategories[$1].order {
                    return tagCategories[$0].order < tagCategories[$1].order
                }
                return tagCategories[$0].name.localizedStandardCompare(tagCategories[$1].name) == .orderedAscending
            }
            for (order, index) in ordered.enumerated() { tagCategories[index].order = order }
        }
    }

    private mutating func normalizeTagDefinitionOrders() {
        let grouped = Dictionary(grouping: tagDefinitions.indices) { index in
            let definition = tagDefinitions[index]
            return "\(definition.workspaceID.uuidString)|\(definition.categoryID?.uuidString ?? "uncategorized")"
        }
        for indices in grouped.values {
            let ordered = indices.sorted {
                if tagDefinitions[$0].order != tagDefinitions[$1].order {
                    return tagDefinitions[$0].order < tagDefinitions[$1].order
                }
                return tagDefinitions[$0].name.localizedStandardCompare(tagDefinitions[$1].name) == .orderedAscending
            }
            for (order, index) in ordered.enumerated() { tagDefinitions[index].order = order }
        }
    }

    static func fresh() -> GTDDatabase {
        let workspace = Workspace(name: "默认工作区", symbolName: "square.grid.2x2", colorHex: "#0AA58F")
        return GTDDatabase(workspaces: [workspace], workspaceOrder: [workspace.id])
    }
}
