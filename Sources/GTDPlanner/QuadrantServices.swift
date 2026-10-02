import Foundation

/// Importance is explicit priority, while urgency is a deadline boundary.
/// Planned dates and execution slots never silently change either axis.
enum TaskQuadrant: String, CaseIterable, Identifiable, Sendable {
    case importantUrgent
    case importantNotUrgent
    case notImportantUrgent
    case notImportantNotUrgent

    var id: String { rawValue }

    var isImportant: Bool {
        self == .importantUrgent || self == .importantNotUrgent
    }

    var isUrgent: Bool {
        self == .importantUrgent || self == .notImportantUrgent
    }

    var title: String {
        switch self {
        case .importantUrgent: "重要且紧急"
        case .importantNotUrgent: "重要不紧急"
        case .notImportantUrgent: "紧急不重要"
        case .notImportantNotUrgent: "不重要不紧急"
        }
    }

    var subtitle: String {
        switch self {
        case .importantUrgent: "高优先级 · 今天截止或已逾期"
        case .importantNotUrgent: "高优先级 · 未来截止或无截止"
        case .notImportantUrgent: "非高优先级 · 今天截止或已逾期"
        case .notImportantNotUrgent: "非高优先级 · 未来截止或无截止"
        }
    }

    var symbol: String {
        switch self {
        case .importantUrgent: "exclamationmark.circle"
        case .importantNotUrgent: "flag"
        case .notImportantUrgent: "clock"
        case .notImportantNotUrgent: "square.grid.2x2"
        }
    }
}

struct QuadrantBucket: Identifiable, Equatable, Sendable {
    let quadrant: TaskQuadrant
    let tasks: [GTDTask]
    var id: TaskQuadrant { quadrant }
    var count: Int { tasks.count }
}

struct QuadrantSnapshot: Equatable, Sendable {
    let day: Date
    let buckets: [QuadrantBucket]
    var tasks: [GTDTask] { buckets.flatMap(\.tasks) }
    var totalCount: Int { buckets.reduce(0) { $0 + $1.count } }
    var importantCount: Int { buckets.filter { $0.quadrant.isImportant }.reduce(0) { $0 + $1.count } }
    var urgentCount: Int { buckets.filter { $0.quadrant.isUrgent }.reduce(0) { $0 + $1.count } }

    func tasks(in quadrant: TaskQuadrant) -> [GTDTask] {
        buckets.first { $0.quadrant == quadrant }?.tasks ?? []
    }
}

enum QuadrantProjection {
    static func quadrant(for task: GTDTask, now: Date = .now, calendar: Calendar = .current) -> TaskQuadrant {
        let important = task.priority == .high
        // A deadline at precisely tomorrow's local midnight belongs to tomorrow.
        let urgent = task.deadline.map { deadline in
            calendar.dateInterval(of: .day, for: now).map { deadline < $0.end } ?? false
        } ?? false
        switch (important, urgent) {
        case (true, true): return .importantUrgent
        case (true, false): return .importantNotUrgent
        case (false, true): return .notImportantUrgent
        case (false, false): return .notImportantNotUrgent
        }
    }

    static func make(
        tasks: [GTDTask], workspaceID: UUID,
        now: Date = .now, calendar: Calendar = .current
    ) -> QuadrantSnapshot {
        let activeTasks = tasks.filter { $0.workspaceID == workspaceID && !$0.status.isFinished }
        let grouped = Dictionary(grouping: activeTasks) { quadrant(for: $0, now: now, calendar: calendar) }
        return QuadrantSnapshot(
            day: calendar.startOfDay(for: now),
            buckets: TaskQuadrant.allCases.map { quadrant in
                QuadrantBucket(quadrant: quadrant, tasks: (grouped[quadrant] ?? []).sorted(by: ordering))
            }
        )
    }

    static func matchesSearch(_ task: GTDTask, query: String, projectName: String = "") -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty || [task.title, task.note, projectName, task.tags.joined(separator: " "), task.contexts.joined(separator: " ")]
            .joined(separator: " ").localizedCaseInsensitiveContains(needle)
    }

    private static func ordering(_ lhs: GTDTask, _ rhs: GTDTask) -> Bool {
        switch (lhs.deadline, rhs.deadline) {
        case let (left?, right?) where left != right: return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        default: break
        }
        if TaskDisplayOrdering.flatList(lhs, rhs) { return true }
        if TaskDisplayOrdering.flatList(rhs, lhs) { return false }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// These are only creation defaults, always disclosed before submitting.
struct QuadrantTaskDefaults: Equatable, Sendable {
    let priority: Priority
    let deadline: Date?
    let deadlinePrecision: DeadlinePrecision

    init(quadrant: TaskQuadrant, now: Date = .now, calendar: Calendar = .current) {
        priority = quadrant.isImportant ? .high : .none
        deadline = quadrant.isUrgent
            ? TaskDateNormalizer.normalizedDeadline(now, precision: .date, calendar: calendar) : nil
        deadlinePrecision = deadline == nil ? .none : .date
    }
}

/// No "move quadrant" mutation: changing importance and changing a deadline
/// are separate, explicitly labelled actions and preserve unrelated fields.
enum QuadrantTaskAction: Equatable, Sendable {
    case setPriority(Priority)
    case setDeadline(Date, precision: DeadlinePrecision)
    case clearDeadline

    func applying(to task: GTDTask, calendar: Calendar = .current) -> GTDTask {
        var updated = task
        switch self {
        case .setPriority(let priority):
            updated.priority = priority
        case .setDeadline(let date, let precision):
            updated.deadline = TaskDateNormalizer.normalizedDeadline(date, precision: precision, calendar: calendar)
            updated.deadlinePrecision = updated.deadline == nil ? .none : precision
        case .clearDeadline:
            updated.deadline = nil
            updated.deadlinePrecision = .none
        }
        return updated
    }
}

extension AppModel {
    func quadrantSnapshot(now: Date = .now, calendar: Calendar = .current) -> QuadrantSnapshot {
        _ = taskRevision
        return QuadrantProjection.make(tasks: database.tasks, workspaceID: selection.selectedWorkspaceID, now: now, calendar: calendar)
    }

    @discardableResult
    func applyQuadrantAction(_ action: QuadrantTaskAction, taskID: UUID, calendar: Calendar = .current) -> Bool {
        guard let task = task(withID: taskID), task.workspaceID == selection.selectedWorkspaceID,
              !task.status.isFinished else { return false }
        let updated = action.applying(to: task, calendar: calendar)
        guard updated != task else { return false }
        updateTask(updated)
        return true
    }

    /// This undated board completes the canonical task, as the inspector does.
    /// The UI confirms this for daily recurrence; it never edits an inferred
    /// future instance. Repeated clicks do not reopen a completed task.
    @discardableResult
    func completeQuadrantTask(taskID: UUID) -> Bool {
        guard let task = task(withID: taskID), task.workspaceID == selection.selectedWorkspaceID,
              !task.status.isFinished else { return false }
        setTaskStatus(taskID, to: .done)
        return true
    }
}
