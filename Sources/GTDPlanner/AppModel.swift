import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    /// The snapshot is writable only inside this module's AppModel domain
    /// extensions. Keeping the setter internal lets the split files perform
    /// atomic domain mutations without exposing storage to views or clients.
    internal var database: GTDDatabase
    let selection: PlannerSelectionState

    /// Each projection has its own observation boundary. A task mutation does
    /// not invalidate the workspace shelf or project browser.
    private(set) var workspaceRevision: UInt = 0
    private(set) var projectRevision: UInt = 0
    private(set) var taskRevision: UInt = 0
    private(set) var timerRevision: UInt = 0
    private(set) var archiveRevision: UInt = 0

    var query: String = ""
    var showNewTask = false
    var showNewProject = false
    /// Legacy presentation flag retained while decoding older view state. The
    /// redesigned UI creates workspaces only inside the workspace popover.
    var showNewWorkspace = false
    var showingSettings = false
    var notice: String?
    var pendingDeletion: DeletionRequest?

    let storage: LocalDatabase
    @ObservationIgnored var saveTask: Task<Void, Never>?
    @ObservationIgnored var workspaceQueryIndex: QueryIndex?
    @ObservationIgnored var projectQueryIndex: QueryIndex?
    @ObservationIgnored var taskQueryIndex: QueryIndex?
    @ObservationIgnored var filteredTaskCache: [FilteredTaskCacheKey: [GTDTask]] = [:]

    enum QueryIndexScope {
        case workspace
        case project
        case task
    }

    struct QueryIndex {
        var workspaceByID: [UUID: Workspace] = [:]
        var projectByID: [UUID: Project] = [:]
        var projectsByWorkspace: [UUID: [Project]] = [:]
        var categoriesByWorkspace: [UUID: [ProjectCategory]] = [:]
        var sectionsByProject: [UUID: [ProjectSection]] = [:]
        var taskByID: [UUID: GTDTask] = [:]
        var tasksByWorkspace: [UUID: [GTDTask]] = [:]
        var tasksByProject: [UUID: [GTDTask]] = [:]
        var childrenByTask: [UUID: [GTDTask]] = [:]
        var entriesByTask: [UUID: [TimeEntry]] = [:]

        init(database: GTDDatabase, scope: QueryIndexScope) {
            switch scope {
            case .workspace:
                for workspace in database.workspaces {
                    workspaceByID[workspace.id] = workspace
                }
            case .project:
                for project in database.projects {
                    projectByID[project.id] = project
                    projectsByWorkspace[project.workspaceID, default: []].append(project)
                }
                for category in database.projectCategories {
                    categoriesByWorkspace[category.workspaceID, default: []].append(category)
                }
                for section in database.projectSections {
                    sectionsByProject[section.projectID, default: []].append(section)
                }
                for key in categoriesByWorkspace.keys {
                    categoriesByWorkspace[key]?.sort(by: Self.categoryOrdering)
                }
                for key in sectionsByProject.keys {
                    sectionsByProject[key]?.sort(by: Self.sectionOrdering)
                }
            case .task:
                for project in database.projects {
                    projectByID[project.id] = project
                }
                for task in database.tasks {
                    taskByID[task.id] = task
                    tasksByWorkspace[task.workspaceID, default: []].append(task)
                    if let projectID = task.projectID {
                        tasksByProject[projectID, default: []].append(task)
                    }
                    if let parentID = task.parentID {
                        childrenByTask[parentID, default: []].append(task)
                    }
                }
                for entry in database.timeEntries {
                    if let taskID = entry.taskID {
                        entriesByTask[taskID, default: []].append(entry)
                    }
                }
                for key in childrenByTask.keys {
                    childrenByTask[key]?.sort(by: Self.taskOrdering)
                }
                for key in entriesByTask.keys {
                    entriesByTask[key]?.sort { $0.startedAt > $1.startedAt }
                }
            }
        }

        private static func categoryOrdering(_ lhs: ProjectCategory, _ rhs: ProjectCategory) -> Bool {
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        private static func sectionOrdering(_ lhs: ProjectSection, _ rhs: ProjectSection) -> Bool {
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        private static func taskOrdering(_ lhs: GTDTask, _ rhs: GTDTask) -> Bool {
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    struct FilteredTaskCacheKey: Hashable {
        let workspaceID: UUID
        let projectID: UUID?
        let smartListRawValue: String
        let query: String
        let includeSearch: Bool
        let timeToken: Date?
    }

    init(storage: LocalDatabase = LocalDatabase()) {
        self.storage = storage
        let loaded = storage.load()
        var normalized = loaded.workspaces.isEmpty ? .fresh() : loaded
        normalized.ensureWorkspaceMetadata()
        normalized.ensureProjectCategories()
        normalized.ensureProjectOrders()
        normalized.ensureProjectSections()
        normalized.ensureTagDefinitions()
        normalized.schemaVersion = max(normalized.schemaVersion, 11)
        self.database = normalized
        self.selection = PlannerSelectionState(selectedWorkspaceID: normalized.pinnedWorkspaceIDs[0])
        self.selection.focusMode = normalized.activeTimer?.mode
    }

    /// Deterministic construction for tests and previews. Production still
    /// loads through the persistence-backed initializer above.
    init(database source: GTDDatabase, storage: LocalDatabase) {
        self.storage = storage
        var normalized = source.workspaces.isEmpty ? .fresh() : source
        normalized.ensureWorkspaceMetadata()
        normalized.ensureProjectCategories()
        normalized.ensureProjectOrders()
        normalized.ensureProjectSections()
        normalized.ensureTagDefinitions()
        normalized.schemaVersion = max(normalized.schemaVersion, 11)
        self.database = normalized
        self.selection = PlannerSelectionState(selectedWorkspaceID: normalized.pinnedWorkspaceIDs[0])
        self.selection.focusMode = normalized.activeTimer?.mode
    }

    var workspaceIndex: QueryIndex {
        _ = workspaceRevision
        if let workspaceQueryIndex { return workspaceQueryIndex }
        let rebuilt = QueryIndex(database: database, scope: .workspace)
        workspaceQueryIndex = rebuilt
        return rebuilt
    }

    var projectIndex: QueryIndex {
        _ = projectRevision
        if let projectQueryIndex { return projectQueryIndex }
        let rebuilt = QueryIndex(database: database, scope: .project)
        projectQueryIndex = rebuilt
        return rebuilt
    }

    var taskIndex: QueryIndex {
        _ = taskRevision
        if let taskQueryIndex { return taskQueryIndex }
        let rebuilt = QueryIndex(database: database, scope: .task)
        taskQueryIndex = rebuilt
        return rebuilt
    }

    enum ProjectionDomain {
        case workspace
        case project
        case task
        case projectAndTask
        case timer
        case archive
        case all
    }

    func invalidateQueryIndex(_ domain: ProjectionDomain = .all) {
        switch domain {
        case .workspace:
            workspaceQueryIndex = nil
            workspaceRevision &+= 1
        case .project:
            projectQueryIndex = nil
            projectRevision &+= 1
        case .task:
            taskQueryIndex = nil
            filteredTaskCache.removeAll(keepingCapacity: true)
            taskRevision &+= 1
        case .projectAndTask:
            projectQueryIndex = nil
            taskQueryIndex = nil
            filteredTaskCache.removeAll(keepingCapacity: true)
            projectRevision &+= 1
            taskRevision &+= 1
        case .timer:
            timerRevision &+= 1
        case .archive:
            archiveRevision &+= 1
        case .all:
            workspaceQueryIndex = nil
            projectQueryIndex = nil
            taskQueryIndex = nil
            filteredTaskCache.removeAll(keepingCapacity: true)
            workspaceRevision &+= 1
            projectRevision &+= 1
            taskRevision &+= 1
            timerRevision &+= 1
            archiveRevision &+= 1
        }
    }

    var currentWorkspace: Workspace {
        workspaceIndex.workspaceByID[selection.selectedWorkspaceID] ?? database.workspaces[0]
    }

    var orderedWorkspaces: [Workspace] {
        let manual = manuallyOrderedWorkspaces
        switch database.workspaceSortMode {
        case .manual:
            return manual
        case .name:
            return manual.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recent:
            return manual.sorted {
                let lhs = database.workspaceLastOpenedAt[$0.id.uuidString] ?? .distantPast
                let rhs = database.workspaceLastOpenedAt[$1.id.uuidString] ?? .distantPast
                if lhs != rhs { return lhs > rhs }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    var manuallyOrderedWorkspaces: [Workspace] {
        database.workspaceOrder.compactMap { workspaceIndex.workspaceByID[$0] }
    }

    var defaultWorkspaceID: UUID {
        database.pinnedWorkspaceIDs.first ?? database.workspaceOrder[0]
    }

    var defaultWorkspace: Workspace {
        workspaceIndex.workspaceByID[defaultWorkspaceID] ?? database.workspaces[0]
    }

    /// Compatibility projection for inactive legacy workspace views.
    var quickWorkspaceItems: [Workspace] { [defaultWorkspace] }

    func isDefaultWorkspace(_ id: UUID) -> Bool {
        defaultWorkspaceID == id
    }

    func isWorkspacePinned(_ id: UUID) -> Bool {
        isDefaultWorkspace(id)
    }

    var currentTasks: [GTDTask] {
        taskIndex.tasksByWorkspace[selection.selectedWorkspaceID] ?? []
    }

    var currentProjects: [Project] {
        projectIndex.projectsByWorkspace[selection.selectedWorkspaceID] ?? []
    }

    func projects(in workspaceID: UUID) -> [Project] {
        projectIndex.projectsByWorkspace[workspaceID] ?? []
    }

    func workspace(withID id: UUID) -> Workspace? {
        workspaceIndex.workspaceByID[id]
    }

    var currentProjectCategories: [ProjectCategory] {
        projectIndex.categoriesByWorkspace[selection.selectedWorkspaceID] ?? []
    }

    func projectSections(for projectID: UUID) -> [ProjectSection] {
        projectIndex.sectionsByProject[projectID] ?? []
    }

    var selectedProjectSections: [ProjectSection] {
        guard let projectID = selection.selectedProjectID else { return [] }
        return projectSections(for: projectID)
    }

    var selectedTask: GTDTask? {
        guard let taskID = selection.taskSelection?.taskID else { return nil }
        return task(withID: taskID)
    }

    /// Returns the latest task value from the canonical task projection.
    /// Views should keep task IDs as identity and resolve the value here when
    /// they render or mutate, rather than treating an older row snapshot as
    /// the source of truth.
    func task(withID id: UUID) -> GTDTask? {
        taskIndex.taskByID[id]
    }

    var selectedProject: Project? {
        guard let projectID = selection.selectedProjectID else { return nil }
        return projectIndex.projectByID[projectID]
    }

    var activeTimer: ActiveTimer? {
        _ = timerRevision
        return database.activeTimer
    }

    var trashItems: [TrashItem] {
        _ = archiveRevision
        return database.trashItems.sorted { $0.deletedAt > $1.deletedAt }
    }

    var activityLog: [ActivityLogEntry] {
        _ = archiveRevision
        return database.activityLog.sorted { $0.timestamp > $1.timestamp }
    }

    func count(for list: SmartList) -> Int {
        let now = Date()
        let calendar = Calendar.current
        var candidates = taskIndex.tasksByWorkspace[selection.selectedWorkspaceID] ?? []
        if let projectID = selection.selectedProjectID {
            candidates.removeAll { $0.projectID != projectID }
        }
        if list == .calendar {
            return candidates.reduce(into: 0) { count, task in
                if task.plannedStart != nil { count += 1 }
            }
        }
        return candidates.reduce(into: 0) { count, task in
            if matchesSmartList(task, target: list, now: now, calendar: calendar) { count += 1 }
        }
    }

    func filteredTasks(for list: SmartList? = nil, includeSearch: Bool = true) -> [GTDTask] {
        // Keep the projection observable even when this call is served by the
        // ignored cache. Without this read, a cache hit can drop SwiftUI's
        // dependency on taskRevision, leaving successful creates/reorders
        // invisible until another selection change rebuilds the view.
        _ = taskRevision
        let target = list ?? selection.selectedSmartList
        let now = Date()
        let calendar = Calendar.current
        let normalizedQuery = includeSearch
            ? query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
            : ""
        let timeToken: Date? = switch target {
        case .today, .tomorrow, .recent:
            calendar.dateInterval(of: .minute, for: now)?.start
        default:
            nil
        }
        let cacheKey = FilteredTaskCacheKey(
            workspaceID: selection.selectedWorkspaceID,
            projectID: selection.selectedProjectID,
            smartListRawValue: target.rawValue,
            query: normalizedQuery,
            includeSearch: includeSearch,
            timeToken: timeToken
        )
        if let cached = filteredTaskCache[cacheKey] { return cached }

        var result = taskIndex.tasksByWorkspace[selection.selectedWorkspaceID] ?? []
        if let projectID = selection.selectedProjectID {
            result = result.filter { $0.projectID == projectID }
        }
        result = result.filter { matchesSmartList($0, target: target, now: now, calendar: calendar) }

        if includeSearch, !normalizedQuery.isEmpty {
            result = result.filter { task in
                let project = project(for: task)?.name ?? ""
                let haystack = [task.title, task.note, project, task.tags.joined(separator: " "), task.contexts.joined(separator: " ")]
                    .joined(separator: " ").localizedLowercase
                return haystack.contains(normalizedQuery)
            }
        }

        let sortedResult = result.sorted(by: TaskDisplayOrdering.flatList)
        filteredTaskCache[cacheKey] = sortedResult
        return sortedResult
    }

    private func matchesSmartList(_ task: GTDTask, target: SmartList, now: Date, calendar: Calendar) -> Bool {
        switch target {
        case .all, .calendar:
            return true
        case .inbox:
            return task.status == .inbox
        case .today:
            guard !task.status.isFinished,
                  !TodayExecutionProjection.isCompleted(task, on: now, calendar: calendar) else { return false }
            return TodayExecutionProjection.isRelevant(task, on: now, now: now, calendar: calendar)
        case .tomorrow:
            guard !task.status.isFinished else { return false }
            if let start = task.plannedStart, calendar.isDateInTomorrow(start) { return true }
            return task.deadline.map { calendar.isDateInTomorrow($0) } ?? false
        case .recent:
            guard !task.status.isFinished else { return false }
            let startOfToday = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? now
            return [task.plannedStart, task.deadline].compactMap { $0 }.contains { $0 >= startOfToday && $0 < end }
        case .fourSquares:
            return task.priority == .high && !task.status.isFinished
        }
    }

    func hierarchyRows(for tasks: [GTDTask]) -> [(task: GTDTask, depth: Int)] {
        let ids = Set(tasks.map(\.id))
        let children = Dictionary(grouping: tasks.filter { $0.parentID != nil }, by: { $0.parentID! })
        let roots = tasks.filter { $0.parentID == nil || !ids.contains($0.parentID!) }
        var result: [(GTDTask, Int)] = []
        func append(_ task: GTDTask, depth: Int) {
            result.append((task, depth))
            for child in (children[task.id] ?? []).sorted(by: { $0.order < $1.order }) {
                append(child, depth: min(depth + 1, 4))
            }
        }
        for root in roots { append(root, depth: 0) }
        return result
    }

    func project(for task: GTDTask) -> Project? {
        guard let projectID = task.projectID else { return nil }
        return projectIndex.projectByID[projectID]
    }

    func children(of task: GTDTask) -> [GTDTask] { taskIndex.childrenByTask[task.id] ?? [] }

    func descendants(of task: GTDTask) -> [GTDTask] {
        let index = taskIndex
        var visited: Set<UUID> = [task.id]
        var pending = Array((index.childrenByTask[task.id] ?? []).reversed())
        var result: [GTDTask] = []

        while let descendant = pending.popLast() {
            guard visited.insert(descendant.id).inserted else { continue }
            result.append(descendant)
            pending.append(contentsOf: (index.childrenByTask[descendant.id] ?? []).reversed())
        }
        return result
    }

    func entries(for task: GTDTask) -> [TimeEntry] { taskIndex.entriesByTask[task.id] ?? [] }
    func tasks(for projectID: UUID) -> [GTDTask] { taskIndex.tasksByProject[projectID] ?? [] }

    func focusTasks(in workspaceID: UUID) -> [GTDTask] {
        _ = taskRevision
        return (taskIndex.tasksByWorkspace[workspaceID] ?? [])
            .filter { !$0.status.isFinished }
            .sorted(by: TaskDisplayOrdering.flatList)
    }

    func focusTimeEntries(on day: Date, workspaceID: UUID, calendar: Calendar = .current) -> [TimeEntry] {
        _ = taskRevision
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return database.timeEntries
            .filter { entry in
                entry.workspaceID == workspaceID
                    && entry.endedAt > interval.start
                    && entry.startedAt < interval.end
            }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func focusPlannedTasks(on day: Date, workspaceID: UUID, calendar: Calendar = .current) -> [GTDTask] {
        _ = taskRevision
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return (taskIndex.tasksByWorkspace[workspaceID] ?? [])
            .filter { task in
                guard task.plannedPrecision == .minute,
                      let start = task.plannedStart else { return false }
                let end = task.plannedEnd ?? start
                return end >= interval.start && start < interval.end
            }
            .sorted {
                if $0.plannedStart != $1.plannedStart {
                    return ($0.plannedStart ?? .distantFuture) < ($1.plannedStart ?? .distantFuture)
                }
                return TaskDisplayOrdering.flatList($0, $1)
            }
    }

    func timeEntry(withID id: UUID) -> TimeEntry? {
        _ = taskRevision
        return database.timeEntries.first { $0.id == id }
    }

    func taskCount(for projectID: UUID, includeFinished: Bool = true) -> Int {
        let tasks = taskIndex.tasksByProject[projectID] ?? []
        return includeFinished ? tasks.count : tasks.reduce(into: 0) { count, task in
            if !task.status.isFinished { count += 1 }
        }
    }

    func projectCount(for workspaceID: UUID) -> Int {
        projectIndex.projectsByWorkspace[workspaceID]?.count ?? 0
    }

    var currentTagCount: Int {
        currentTagDefinitions.count
    }
}
