import Foundation

/// Pure data mutations used by the workspace shelf and workspace manager.
/// The service does not save or change selection state; the caller decides
/// when a completed mutation should be persisted and rendered.
enum WorkspaceReorderService {
    static func move(
        in database: inout GTDDatabase,
        from source: IndexSet,
        to destination: Int
    ) {
        database.workspaceOrder.move(fromOffsets: source, toOffset: destination)
    }

    static func move(
        in database: inout GTDDatabase,
        workspaceID: UUID,
        before targetID: UUID?
    ) -> Bool {
        guard targetID != workspaceID,
              database.workspaceOrder.contains(workspaceID) else { return false }
        let originalOrder = database.workspaceOrder
        var order = database.workspaceOrder
        order.removeAll { $0 == workspaceID }
        let insertionIndex: Int
        if let targetID {
            guard let targetIndex = order.firstIndex(of: targetID) else { return false }
            insertionIndex = targetIndex
        } else {
            insertionIndex = order.endIndex
        }
        order.insert(workspaceID, at: insertionIndex)
        guard order != originalOrder else { return false }
        database.workspaceOrder = order
        return true
    }
}

/// Project ordering is deliberately independent from project editing and
/// from SwiftUI's drag state. This keeps a drag frame from writing to the
/// database on every pointer update.
enum ProjectReorderService {
    @discardableResult
    static func move(
        in database: inout GTDDatabase,
        projectID: UUID,
        workspaceID: UUID,
        toCategory category: String,
        beforeProjectID: UUID? = nil
    ) -> Bool {
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanCategory.isEmpty,
              database.projectCategories.contains(where: {
                  $0.workspaceID == workspaceID &&
                  $0.name.localizedCaseInsensitiveCompare(cleanCategory) == .orderedSame
              }),
              let projectIndex = database.projects.firstIndex(where: {
                  $0.id == projectID && $0.workspaceID == workspaceID
              }) else {
            return false
        }

        let movingProject = database.projects[projectIndex]
        let sourceCategory = movingProject.category
        let isSameCategory = sourceCategory.localizedCaseInsensitiveCompare(cleanCategory) == .orderedSame
        if isSameCategory, beforeProjectID == projectID { return false }

        let sourceKey = sourceCategory.localizedLowercase
        let destinationKey = cleanCategory.localizedLowercase
        let affectedKeys = sourceKey == destinationKey ? [sourceKey] : [sourceKey, destinationKey]

        for key in affectedKeys {
            var projectsInCategory = database.projects
                .filter {
                    $0.workspaceID == workspaceID &&
                    $0.category.localizedLowercase == key &&
                    $0.id != projectID
                }
                .sorted(by: projectOrdering)

            if key == destinationKey {
                var moved = movingProject
                moved.category = cleanCategory
                let insertionIndex = beforeProjectID.flatMap { targetID in
                    projectsInCategory.firstIndex { $0.id == targetID }
                } ?? projectsInCategory.count
                projectsInCategory.insert(moved, at: min(insertionIndex, projectsInCategory.count))
            }

            for (order, project) in projectsInCategory.enumerated() {
                guard let index = database.projects.firstIndex(where: { $0.id == project.id }) else { continue }
                database.projects[index].category = project.category
                database.projects[index].order = order
            }
        }
        return true
    }

    private static func projectOrdering(_ lhs: Project, _ rhs: Project) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

/// Project categories form their own ordering domain. Reordering a category
/// only changes category.order; projects retain their existing category name
/// and therefore never move between groups as a side effect of the drag.
enum ProjectCategoryReorderService {
    @discardableResult
    static func move(
        in database: inout GTDDatabase,
        categoryID: UUID,
        workspaceID: UUID,
        beforeCategoryID: UUID? = nil
    ) -> Bool {
        guard let moving = database.projectCategories.first(where: {
            $0.id == categoryID && $0.workspaceID == workspaceID
        }), beforeCategoryID != categoryID else { return false }

        var categories = database.projectCategories
            .filter { $0.workspaceID == workspaceID && $0.id != categoryID }
            .sorted(by: categoryOrdering)
        let insertionIndex: Int
        if let beforeCategoryID {
            guard let targetIndex = categories.firstIndex(where: { $0.id == beforeCategoryID }) else {
                return false
            }
            insertionIndex = targetIndex
        } else {
            insertionIndex = categories.count
        }
        categories.insert(moving, at: min(insertionIndex, categories.count))

        let original = database.projectCategories
        for (order, category) in categories.enumerated() {
            guard let index = database.projectCategories.firstIndex(where: { $0.id == category.id }) else { continue }
            database.projectCategories[index].order = order
        }
        return database.projectCategories != original
    }

    private static func categoryOrdering(_ lhs: ProjectCategory, _ rhs: ProjectCategory) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

/// Project sections have their own ordering domain. A section drag should not
/// need to know anything about task rows.
enum ProjectSectionService {
    @discardableResult
    static func moveSection(
        in database: inout GTDDatabase,
        sectionID: UUID,
        workspaceID: UUID,
        beforeSectionID: UUID? = nil
    ) -> Bool {
        guard let section = database.projectSections.first(where: { $0.id == sectionID }),
              let project = database.projects.first(where: {
                  $0.id == section.projectID && $0.workspaceID == workspaceID
              }) else {
            return false
        }

        var sections = database.projectSections
            .filter { $0.projectID == project.id && $0.id != sectionID }
            .sorted(by: sectionOrdering)
        let insertionIndex = beforeSectionID.flatMap { targetID in
            sections.firstIndex { $0.id == targetID }
        } ?? sections.count
        var moved = section
        moved.order = insertionIndex
        sections.insert(moved, at: min(insertionIndex, sections.count))

        for (order, section) in sections.enumerated() {
            guard let index = database.projectSections.firstIndex(where: { $0.id == section.id }) else { continue }
            database.projectSections[index].order = order
        }
        return true
    }

    private static func sectionOrdering(_ lhs: ProjectSection, _ rhs: ProjectSection) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

enum TaskRowClickIntent: Sendable {
    case primary
    case titleDoubleClick
    case disclosure
}

enum TaskRowClickAction: Equatable, Sendable {
    case select
    case scheduleExpansionToggle
    case beginRename
    case toggleExpansionImmediately
    case none
}

/// Keeps task-row click semantics independent from SwiftUI gesture timing.
/// The view is responsible only for delaying a scheduled expansion until the
/// system double-click interval has elapsed.
enum TaskRowClickPolicy {
    static func resolve(
        intent: TaskRowClickIntent,
        isSelected: Bool,
        hasChildren: Bool,
        isRenaming: Bool
    ) -> TaskRowClickAction {
        switch intent {
        case .primary:
            guard !isRenaming else { return .none }
            if !isSelected { return .select }
            return hasChildren ? .scheduleExpansionToggle : .none

        case .titleDoubleClick:
            return isRenaming ? .none : .beginRename

        case .disclosure:
            return hasChildren ? .toggleExpansionImmediately : .none
        }
    }
}

/// Task ordering is the only data mutation performed by a task drag. It is
/// intentionally separate from the drag coordinator below, which only maps
/// pointer geometry to a drop target.
enum TaskReorderService {
    @discardableResult
    static func moveTask(
        in database: inout GTDDatabase,
        taskID: UUID,
        workspaceID: UUID,
        toSectionID sectionID: UUID?,
        toParentID parentID: UUID? = nil,
        beforeTaskID: UUID? = nil
    ) -> Bool {
        guard taskID != beforeTaskID,
              let taskIndex = database.tasks.firstIndex(where: { $0.id == taskID }),
              let projectID = database.tasks[taskIndex].projectID,
              let project = database.projects.first(where: {
                  $0.id == projectID && $0.workspaceID == workspaceID
              }) else {
            return false
        }
        if let sectionID, !database.projectSections.contains(where: {
            $0.id == sectionID && $0.projectID == project.id
        }) {
            return false
        }

        let descendantIDs = descendantTaskIDs(in: database, of: taskID)
        if let parentID, descendantIDs.contains(parentID) { return false }

        if let parentID {
            guard database.tasks.contains(where: {
                $0.id == parentID &&
                    $0.workspaceID == workspaceID &&
                    $0.projectID == project.id &&
                    $0.sectionID == sectionID
            }) else { return false }
        }

        func orderedPeerIndices(sectionID targetSectionID: UUID?, parentID targetParentID: UUID?) -> [Int] {
            database.tasks.indices
                .filter {
                    let task = database.tasks[$0]
                    return task.projectID == project.id &&
                        task.sectionID == targetSectionID &&
                        task.parentID == targetParentID &&
                        task.id != taskID
                }
                .sorted { lhs, rhs in
                    taskOrdering(database.tasks[lhs], database.tasks[rhs])
                }
        }

        let sourceSectionID = database.tasks[taskIndex].sectionID
        let sourceParentID = database.tasks[taskIndex].parentID
        let sourcePeerIndices = orderedPeerIndices(sectionID: sourceSectionID, parentID: sourceParentID)
        var destinationIndices = orderedPeerIndices(sectionID: sectionID, parentID: parentID)
        let insertionIndex: Int
        if let beforeTaskID {
            guard let index = destinationIndices.firstIndex(where: { database.tasks[$0].id == beforeTaskID }) else {
                return false
            }
            insertionIndex = index
        } else {
            insertionIndex = destinationIndices.count
        }

        destinationIndices.insert(taskIndex, at: min(insertionIndex, destinationIndices.count))
        if sourceSectionID == sectionID, sourceParentID == parentID {
            let currentIndices = (destinationIndices + [taskIndex])
                .uniqued()
                .sorted { lhs, rhs in taskOrdering(database.tasks[lhs], database.tasks[rhs]) }
            if currentIndices.map({ database.tasks[$0].id }) == destinationIndices.map({ database.tasks[$0].id }) {
                return false
            }
        }

        let now = Date.now
        for (order, index) in destinationIndices.enumerated() {
            database.tasks[index].sectionID = sectionID
            if index == taskIndex {
                database.tasks[index].parentID = parentID
                database.tasks[index].updatedAt = now
            }
            database.tasks[index].order = order
        }

        if sourceSectionID != sectionID || sourceParentID != parentID {
            for (order, index) in sourcePeerIndices.enumerated() {
                database.tasks[index].order = order
            }
        }

        if sourceSectionID != sectionID {
            for index in database.tasks.indices where descendantIDs.contains(database.tasks[index].id) {
                database.tasks[index].sectionID = sectionID
                database.tasks[index].updatedAt = now
            }
        }
        return true
    }

    static func descendantTaskIDs(in database: GTDDatabase, of taskID: UUID) -> Set<UUID> {
        let childrenByParent = Dictionary(grouping: database.tasks.compactMap { task -> (UUID, UUID)? in
            guard let parentID = task.parentID else { return nil }
            return (parentID, task.id)
        }, by: \.0)
        var result: Set<UUID> = [taskID]
        var pending = [taskID]
        while let parentID = pending.popLast() {
            for (_, childID) in childrenByParent[parentID] ?? [] where result.insert(childID).inserted {
                pending.append(childID)
            }
        }
        return result
    }

    private static func taskOrdering(_ lhs: GTDTask, _ rhs: GTDTask) -> Bool {
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

/// The display order used by C3's task projection and the C34 Gantt outline.
///
/// A flat projection uses the task's lifecycle state first so completed work
/// naturally settles below active work. Manual order remains the primary
/// ordering inside each state, with planning time and title providing stable
/// secondary keys. Children retain C3's hierarchy behavior: unfinished
/// children come first, while completed children are grouped at the bottom
/// and newest completions are shown first.
enum TaskDisplayOrdering {
    static func flatList(_ lhs: GTDTask, _ rhs: GTDTask) -> Bool {
        if lhs.status.isFinished != rhs.status.isFinished {
            return !lhs.status.isFinished
        }
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        switch (lhs.plannedStart, rhs.plannedStart) {
        case let (left?, right?):
            if left != right { return left < right }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    static func hierarchyChild(_ lhs: GTDTask, _ rhs: GTDTask) -> Bool {
        if lhs.status.isFinished != rhs.status.isFinished {
            return !lhs.status.isFinished
        }
        if lhs.status.isFinished {
            switch (lhs.completedAt, rhs.completedAt) {
            case let (left?, right?) where left != right:
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
        }
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct TaskOutlineRow: Identifiable, Equatable {
    let task: GTDTask
    let depth: Int
    let hasChildren: Bool

    var id: UUID { task.id }
}

enum TaskOutlineBuilder {
    static func rows(for tasks: [GTDTask], expandedTaskIDs: Set<UUID>) -> [TaskOutlineRow] {
        let visibleIDs = Set(tasks.map(\.id))
        let children = Dictionary(grouping: tasks.filter { task in
            guard let parentID = task.parentID else { return false }
            return visibleIDs.contains(parentID)
        }, by: { $0.parentID! })
        let roots = tasks.filter { task in
            guard let parentID = task.parentID else { return true }
            return !visibleIDs.contains(parentID)
        }.sorted(by: TaskDisplayOrdering.flatList)

        var result: [TaskOutlineRow] = []
        var visited: Set<UUID> = []
        func append(_ task: GTDTask, depth: Int) {
            guard visited.insert(task.id).inserted else { return }
            let childTasks = (children[task.id] ?? []).sorted(by: TaskDisplayOrdering.hierarchyChild)
            result.append(TaskOutlineRow(task: task, depth: depth, hasChildren: !childTasks.isEmpty))
            guard expandedTaskIDs.contains(task.id) else { return }
            for child in childTasks {
                append(child, depth: depth + 1)
            }
        }

        for root in roots {
            append(root, depth: 0)
        }
        return result
    }

}

/// Pure hit-testing for the task drag interaction. It never mutates the
/// database and can therefore run for every pointer update without invoking
/// SwiftData or the save scheduler.
enum TaskDragCoordinator {
    static func resolveTarget(
        location: CGPoint,
        movingTaskID: UUID,
        sourceSectionID: UUID?,
        sectionDisplays: [TaskSectionDisplay],
        taskFrames: [UUID: CGRect],
        sectionFrames: [String: CGRect],
        sourceParentID: UUID? = nil,
        sourceIsFinished: Bool = false,
        horizontalTranslation: CGFloat = 0,
        invalidParentIDs: Set<UUID> = []
    ) -> TaskDropTarget {
        if abs(horizontalTranslation) < 24,
           let sourceFrame = taskFrames[movingTaskID],
           sourceFrame.contains(location) {
            return TaskDropTarget(sectionID: sourceSectionID, parentID: sourceParentID, beforeTaskID: movingTaskID)
        }

        // Resolve the section before its rows. A global row scan makes every
        // point above the next task look like an insertion into that task's
        // section, so an empty section can never receive a drop when another
        // section below it contains rows.
        guard let destination = nearestSectionDisplay(
            to: location.y,
            sectionDisplays: sectionDisplays,
            taskFrames: taskFrames,
            sectionFrames: sectionFrames
        ) else {
            return TaskDropTarget(sectionID: sourceSectionID, parentID: sourceParentID, beforeTaskID: movingTaskID)
        }

        // Geometry is the source of truth for the visible order. The task
        // array may change groups after completion, while frames always match
        // what the user is currently pointing at.
        let visibleRows = destination.tasks.compactMap { task -> (GTDTask, CGRect)? in
            guard task.id != movingTaskID, let frame = taskFrames[task.id] else { return nil }
            return (task, frame)
        }
        .sorted { lhs, rhs in
            if lhs.1.minY != rhs.1.minY { return lhs.1.minY < rhs.1.minY }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }

        let destinationSectionID = destination.section?.id
        if horizontalTranslation >= 24,
           let hovered = visibleRows.min(by: { verticalDistance(from: location.y, to: $0.1) < verticalDistance(from: location.y, to: $1.1) }),
           !invalidParentIDs.contains(hovered.0.id) {
            return TaskDropTarget(sectionID: destinationSectionID, parentID: hovered.0.id, beforeTaskID: nil)
        }

        let destinationParentID = horizontalTranslation <= -24
            ? nil
            : (destinationSectionID == sourceSectionID ? sourceParentID : nil)
        let visiblePeers = visibleRows.filter {
            $0.0.parentID == destinationParentID && $0.0.status.isFinished == sourceIsFinished
        }
        for (task, frame) in visiblePeers where location.y < frame.midY {
            return TaskDropTarget(sectionID: destinationSectionID, parentID: destinationParentID, beforeTaskID: task.id)
        }

        return TaskDropTarget(sectionID: destinationSectionID, parentID: destinationParentID, beforeTaskID: nil)
    }

    private static func verticalDistance(from y: CGFloat, to frame: CGRect) -> CGFloat {
        if frame.contains(CGPoint(x: frame.midX, y: y)) { return 0 }
        return min(abs(y - frame.minY), abs(y - frame.maxY))
    }

    private static func nearestSectionDisplay(
        to y: CGFloat,
        sectionDisplays: [TaskSectionDisplay],
        taskFrames: [UUID: CGRect],
        sectionFrames: [String: CGRect]
    ) -> TaskSectionDisplay? {
        var best: (distance: CGFloat, display: TaskSectionDisplay)?
        for display in sectionDisplays {
            let key = display.section?.id.uuidString ?? "__unassigned__"
            var measuredFrames = display.tasks.compactMap { taskFrames[$0.id] }
            if let sectionFrame = sectionFrames[key] {
                measuredFrames.append(sectionFrame)
            }
            guard let firstFrame = measuredFrames.first else { continue }
            let bounds = measuredFrames.dropFirst().reduce(firstFrame) { partial, frame in
                partial.union(frame)
            }
            let distance: CGFloat
            if y < bounds.minY { distance = bounds.minY - y }
            else if y > bounds.maxY { distance = y - bounds.maxY }
            else { distance = 0 }
            if best == nil || distance < best!.distance {
                best = (distance, display)
            }
        }
        return best?.display
    }
}
