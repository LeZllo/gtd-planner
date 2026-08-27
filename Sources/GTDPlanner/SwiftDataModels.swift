import Foundation
import SwiftData

// SwiftData entities deliberately keep foreign keys as UUIDs instead of
// SwiftData relationships. The app already owns a fast in-memory query index,
// and UUID foreign keys make JSON import/export and trash restoration stable.

@Model
final class SDWorkspace {
    @Attribute(.unique) var id: UUID
    var name: String
    var symbolName: String
    var colorHex: String

    init(id: UUID, name: String, symbolName: String, colorHex: String) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
    }
}

@Model
final class SDProjectCategory {
    @Attribute(.unique) var id: UUID
    var workspaceID: UUID
    var name: String
    // Keep a model-level default so lightweight migration can materialize the
    // new field for categories written before custom category colors existed.
    var colorHex: String = "#64748B"
    var order: Int

    init(id: UUID, workspaceID: UUID, name: String, colorHex: String = "#64748B", order: Int) {
        self.id = id
        self.workspaceID = workspaceID
        self.name = name
        self.colorHex = colorHex
        self.order = order
    }
}

@Model
final class SDProject {
    @Attribute(.unique) var id: UUID
    var workspaceID: UUID
    var category: String
    var name: String
    var symbolName: String
    var colorHex: String
    var note: String
    var order: Int

    init(id: UUID, workspaceID: UUID, category: String, name: String, symbolName: String,
         colorHex: String, note: String, order: Int) {
        self.id = id
        self.workspaceID = workspaceID
        self.category = category
        self.name = name
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.note = note
        self.order = order
    }
}

@Model
final class SDProjectSection {
    @Attribute(.unique) var id: UUID
    var projectID: UUID
    var name: String
    var colorHex: String
    var order: Int

    init(id: UUID, projectID: UUID, name: String, colorHex: String, order: Int) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.colorHex = colorHex
        self.order = order
    }
}

@Model
final class SDTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var workspaceID: UUID
    var projectID: UUID?
    var sectionID: UUID?
    var parentID: UUID?
    var statusRaw: String
    var priorityRaw: String
    // Default keeps existing SwiftData stores lightweight-migratable; legacy
    // status-to-action mapping is applied once when the store schema advances.
    var actionListRaw: String = ActionList.nextAction.rawValue
    var tagsJSON: String
    var contextsJSON: String
    var plannedStart: Date?
    var plannedEnd: Date?
    var plannedPrecisionRaw: String = DeadlinePrecision.minute.rawValue
    var deadline: Date?
    var deadlinePrecisionRaw: String
    var recurrence: String
    var note: String
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var order: Int
    var completedInstancesJSON: String
    var skippedInstancesJSON: String

    init(id: UUID, title: String, workspaceID: UUID, projectID: UUID?, sectionID: UUID?, parentID: UUID?,
         statusRaw: String, priorityRaw: String, actionListRaw: String = ActionList.nextAction.rawValue,
         tagsJSON: String, contextsJSON: String,
         plannedStart: Date?, plannedEnd: Date?, plannedPrecisionRaw: String, deadline: Date?, deadlinePrecisionRaw: String,
         recurrence: String, note: String, createdAt: Date, updatedAt: Date, completedAt: Date?,
         order: Int, completedInstancesJSON: String, skippedInstancesJSON: String) {
        self.id = id
        self.title = title
        self.workspaceID = workspaceID
        self.projectID = projectID
        self.sectionID = sectionID
        self.parentID = parentID
        self.statusRaw = statusRaw
        self.priorityRaw = priorityRaw
        self.actionListRaw = actionListRaw
        self.tagsJSON = tagsJSON
        self.contextsJSON = contextsJSON
        self.plannedStart = plannedStart
        self.plannedEnd = plannedEnd
        self.plannedPrecisionRaw = plannedPrecisionRaw
        self.deadline = deadline
        self.deadlinePrecisionRaw = deadlinePrecisionRaw
        self.recurrence = recurrence
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.order = order
        self.completedInstancesJSON = completedInstancesJSON
        self.skippedInstancesJSON = skippedInstancesJSON
    }
}

@Model
final class SDTimeEntry {
    @Attribute(.unique) var id: UUID
    var workspaceID: UUID
    var taskID: UUID?
    var title: String
    var startedAt: Date
    var endedAt: Date
    var sourceRaw: String
    var pomodoroPhaseRaw: String?
    var note: String
    /// Optional so existing SwiftData stores can lightweight-migrate; old
    /// entries fall back to their wall-clock duration at the value layer.
    var activeSeconds: Double? = nil

    init(id: UUID, workspaceID: UUID, taskID: UUID?, title: String, startedAt: Date, endedAt: Date,
         sourceRaw: String, pomodoroPhaseRaw: String?, note: String, activeSeconds: Double? = nil) {
        self.id = id
        self.workspaceID = workspaceID
        self.taskID = taskID
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sourceRaw = sourceRaw
        self.pomodoroPhaseRaw = pomodoroPhaseRaw
        self.note = note
        self.activeSeconds = activeSeconds
    }
}

@Model
final class SDTrashItem {
    @Attribute(.unique) var id: UUID
    var deletedAt: Date
    // Trash records contain a complete, self-contained restore payload. This
    // keeps deletion/restoration transactional without duplicating live rows.
    var payloadJSON: String

    init(id: UUID, deletedAt: Date, payloadJSON: String) {
        self.id = id
        self.deletedAt = deletedAt
        self.payloadJSON = payloadJSON
    }
}

@Model
final class SDActivityLogEntry {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var action: String
    var target: String
    var detail: String

    init(id: UUID, timestamp: Date, action: String, target: String, detail: String) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.target = target
        self.detail = detail
    }
}

@Model
final class SDStoreSettings {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int
    var workspaceOrderJSON: String
    var pinnedWorkspaceIDsJSON: String
    var workspaceShortcutsConfigured: Bool
    var workspaceSortModeRaw: String
    var workspaceLastOpenedAtJSON: String
    var activeTimerJSON: String?
    /// Optional JSON keeps existing stores eligible for lightweight migration.
    var tagCategoriesJSON: String?
    var tagDefinitionsJSON: String?

    init(id: UUID, schemaVersion: Int, workspaceOrderJSON: String, pinnedWorkspaceIDsJSON: String,
         workspaceShortcutsConfigured: Bool, workspaceSortModeRaw: String,
         workspaceLastOpenedAtJSON: String, activeTimerJSON: String?,
         tagCategoriesJSON: String? = nil, tagDefinitionsJSON: String? = nil) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.workspaceOrderJSON = workspaceOrderJSON
        self.pinnedWorkspaceIDsJSON = pinnedWorkspaceIDsJSON
        self.workspaceShortcutsConfigured = workspaceShortcutsConfigured
        self.workspaceSortModeRaw = workspaceSortModeRaw
        self.workspaceLastOpenedAtJSON = workspaceLastOpenedAtJSON
        self.activeTimerJSON = activeTimerJSON
        self.tagCategoriesJSON = tagCategoriesJSON
        self.tagDefinitionsJSON = tagDefinitionsJSON
    }
}
