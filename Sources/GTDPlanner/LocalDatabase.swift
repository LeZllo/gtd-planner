import Foundation
import SwiftData

enum LocalDatabaseError: LocalizedError {
    case swiftDataUnavailable(Error?)

    var errorDescription: String? {
        switch self {
        case .swiftDataUnavailable(let error):
            return error.map { "SwiftData 不可用：\($0.localizedDescription)" } ?? "SwiftData 不可用"
        }
    }
}

/// SwiftData-backed persistence with a value-type snapshot boundary.
///
/// SwiftUI never observes SwiftData objects directly. AppModel keeps its
/// existing query index and sends a debounced value snapshot here, while each
/// save creates its own ModelContext on the utility thread. The sync is by
/// stable UUID: unchanged rows remain in SQLite and stale rows are deleted.
/// JSON remains available as a human-readable import/export format and as the
/// one-time migration source for the former database.json file.
final class LocalDatabase: @unchecked Sendable {
    private static let settingsID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var writeGeneration: UInt64 = 0
    private let encoder: JSONEncoder
    private let exportEncoder: JSONEncoder
    private let decoder: JSONDecoder
    private let container: ModelContainer?
    private let containerError: Error?
    let url: URL
    let storeURL: URL

    init(url: URL? = nil, inMemory: Bool = false) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("GTD Planner", isDirectory: true)
        self.url = url ?? appSupport.appendingPathComponent("database.json")
        self.storeURL = appSupport.appendingPathComponent("GTD Planner.store")
        self.encoder = JSONEncoder()
        self.exportEncoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        exportEncoder.dateEncodingStrategy = .iso8601
        exportEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        do {
            let schema = Schema([
                SDWorkspace.self,
                SDProjectCategory.self,
                SDProject.self,
                SDProjectSection.self,
                SDTask.self,
                SDTimeEntry.self,
                SDTrashItem.self,
                SDActivityLogEntry.self,
                SDStoreSettings.self
            ])
            let configuration: ModelConfiguration
            if inMemory {
                configuration = ModelConfiguration(
                    "GTDPlannerTests",
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
            } else {
                configuration = ModelConfiguration(
                    "GTDPlanner",
                    schema: schema,
                    url: storeURL,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
            }
            self.container = try ModelContainer(for: schema, configurations: [configuration])
            self.containerError = nil
        } catch {
            self.container = nil
            self.containerError = error
        }
    }

    func load() -> GTDDatabase {
        lock.lock()
        defer { lock.unlock() }

        guard let container else {
            return normalized(legacyDatabase())
        }

        do {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let workspaces = try context.fetch(FetchDescriptor<SDWorkspace>())
            guard !workspaces.isEmpty else {
                let seed = normalized(legacyDatabase())
                try persist(seed, into: context)
                try context.save()
                return seed
            }
            return normalized(try decodeDatabase(from: context, workspaces: workspaces))
        } catch {
            // Keep the old JSON untouched. It is the recovery path if a store
            // is interrupted during its first creation or becomes unreadable.
            return normalized(legacyDatabase())
        }
    }

    func advanceWriteGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        writeGeneration &+= 1
        return writeGeneration
    }

    func save(_ database: GTDDatabase, expectedGeneration: UInt64? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        if let expectedGeneration, expectedGeneration != writeGeneration { return }
        guard let container else {
            throw LocalDatabaseError.swiftDataUnavailable(containerError)
        }

        let context = ModelContext(container)
        context.autosaveEnabled = false
        try persist(normalized(database), into: context)
        try context.save()
    }

    func exportData(_ database: GTDDatabase, to destination: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        let data = try exportEncoder.encode(database)
        try data.write(to: destination, options: .atomic)
    }

    func importData(from source: URL) throws -> GTDDatabase {
        lock.lock()
        defer { lock.unlock() }
        let data = try Data(contentsOf: source)
        return try decoder.decode(GTDDatabase.self, from: data)
    }

    private func legacyDatabase() -> GTDDatabase {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(GTDDatabase.self, from: data)
        } catch {
            return .fresh()
        }
    }

    private func normalized(_ source: GTDDatabase) -> GTDDatabase {
        var result = source.workspaces.isEmpty ? .fresh() : source
        result.ensureWorkspaceMetadata()
        result.ensureProjectCategories()
        result.ensureProjectOrders()
        result.ensureProjectSections()
        result.ensureTagDefinitions()
        result.schemaVersion = max(result.schemaVersion, 11)
        return result
    }

    private func persist(_ database: GTDDatabase, into context: ModelContext) throws {
        let workspaceRows = try context.fetch(FetchDescriptor<SDWorkspace>())
        let workspaceIDs = Set(database.workspaces.map(\.id))
        for row in workspaceRows where !workspaceIDs.contains(row.id) { context.delete(row) }
        let workspaceByID = Dictionary(uniqueKeysWithValues: workspaceRows.map { ($0.id, $0) })
        for value in database.workspaces {
            if let row = workspaceByID[value.id] {
                row.name = value.name
                row.symbolName = value.symbolName
                row.colorHex = value.colorHex
            } else {
                context.insert(SDWorkspace(id: value.id, name: value.name, symbolName: value.symbolName, colorHex: value.colorHex))
            }
        }

        let categoryRows = try context.fetch(FetchDescriptor<SDProjectCategory>())
        let categoryIDs = Set(database.projectCategories.map(\.id))
        for row in categoryRows where !categoryIDs.contains(row.id) { context.delete(row) }
        let categoryByID = Dictionary(uniqueKeysWithValues: categoryRows.map { ($0.id, $0) })
        for value in database.projectCategories {
            if let row = categoryByID[value.id] {
                row.workspaceID = value.workspaceID
                row.name = value.name
                row.colorHex = value.colorHex
                row.order = value.order
            } else {
                context.insert(SDProjectCategory(
                    id: value.id,
                    workspaceID: value.workspaceID,
                    name: value.name,
                    colorHex: value.colorHex,
                    order: value.order
                ))
            }
        }

        let projectRows = try context.fetch(FetchDescriptor<SDProject>())
        let projectIDs = Set(database.projects.map(\.id))
        for row in projectRows where !projectIDs.contains(row.id) { context.delete(row) }
        let projectByID = Dictionary(uniqueKeysWithValues: projectRows.map { ($0.id, $0) })
        for value in database.projects {
            if let row = projectByID[value.id] {
                row.workspaceID = value.workspaceID
                row.category = value.category
                row.name = value.name
                row.symbolName = value.symbolName
                row.colorHex = value.colorHex
                row.note = value.note
                row.order = value.order
            } else {
                context.insert(SDProject(id: value.id, workspaceID: value.workspaceID, category: value.category,
                                         name: value.name, symbolName: value.symbolName, colorHex: value.colorHex,
                                         note: value.note, order: value.order))
            }
        }

        let sectionRows = try context.fetch(FetchDescriptor<SDProjectSection>())
        let sectionIDs = Set(database.projectSections.map(\.id))
        for row in sectionRows where !sectionIDs.contains(row.id) { context.delete(row) }
        let sectionByID = Dictionary(uniqueKeysWithValues: sectionRows.map { ($0.id, $0) })
        for value in database.projectSections {
            if let row = sectionByID[value.id] {
                row.projectID = value.projectID
                row.name = value.name
                row.colorHex = value.colorHex
                row.order = value.order
            } else {
                context.insert(SDProjectSection(id: value.id, projectID: value.projectID, name: value.name,
                                                colorHex: value.colorHex, order: value.order))
            }
        }

        let taskRows = try context.fetch(FetchDescriptor<SDTask>())
        let taskIDs = Set(database.tasks.map(\.id))
        for row in taskRows where !taskIDs.contains(row.id) { context.delete(row) }
        let taskByID = Dictionary(uniqueKeysWithValues: taskRows.map { ($0.id, $0) })
        for value in database.tasks {
            let tagsJSON = try encodeJSON(value.tags)
            let contextsJSON = try encodeJSON(value.contexts)
            let executionSlotsJSON = try encodeJSON(value.executionSlots)
            let completedInstancesJSON = try encodeJSON(value.completedInstances)
            let skippedInstancesJSON = try encodeJSON(value.skippedInstances)
            if let row = taskByID[value.id] {
                row.title = value.title
                row.workspaceID = value.workspaceID
                row.projectID = value.projectID
                row.sectionID = value.sectionID
                row.parentID = value.parentID
                row.statusRaw = value.status.rawValue
                row.priorityRaw = value.priority.rawValue
                row.actionListRaw = value.actionList.rawValue
                row.tagsJSON = tagsJSON
                row.contextsJSON = contextsJSON
                row.plannedStart = value.plannedStart
                row.plannedEnd = value.plannedEnd
                row.plannedPrecisionRaw = value.plannedPrecision.rawValue
                row.planRangeIntentRaw = value.planRangeIntent.rawValue
                row.executionSlotsJSON = executionSlotsJSON
                row.deadline = value.deadline
                row.deadlinePrecisionRaw = value.deadlinePrecision.rawValue
                row.recurrence = value.recurrence
                row.note = value.note
                row.createdAt = value.createdAt
                row.updatedAt = value.updatedAt
                row.completedAt = value.completedAt
                row.order = value.order
                row.completedInstancesJSON = completedInstancesJSON
                row.skippedInstancesJSON = skippedInstancesJSON
            } else {
                context.insert(SDTask(id: value.id, title: value.title, workspaceID: value.workspaceID,
                                      projectID: value.projectID, sectionID: value.sectionID, parentID: value.parentID,
                                      statusRaw: value.status.rawValue, priorityRaw: value.priority.rawValue,
                                      actionListRaw: value.actionList.rawValue,
                                      tagsJSON: tagsJSON, contextsJSON: contextsJSON, plannedStart: value.plannedStart,
                                      plannedEnd: value.plannedEnd, plannedPrecisionRaw: value.plannedPrecision.rawValue,
                                      planRangeIntentRaw: value.planRangeIntent.rawValue,
                                      executionSlotsJSON: executionSlotsJSON,
                                      deadline: value.deadline,
                                      deadlinePrecisionRaw: value.deadlinePrecision.rawValue, recurrence: value.recurrence,
                                      note: value.note, createdAt: value.createdAt, updatedAt: value.updatedAt,
                                      completedAt: value.completedAt, order: value.order,
                                      completedInstancesJSON: completedInstancesJSON, skippedInstancesJSON: skippedInstancesJSON))
            }
        }

        let timeRows = try context.fetch(FetchDescriptor<SDTimeEntry>())
        let timeIDs = Set(database.timeEntries.map(\.id))
        for row in timeRows where !timeIDs.contains(row.id) { context.delete(row) }
        let timeByID = Dictionary(uniqueKeysWithValues: timeRows.map { ($0.id, $0) })
        for value in database.timeEntries {
            if let row = timeByID[value.id] {
                row.workspaceID = value.workspaceID
                row.taskID = value.taskID
                row.title = value.title
                row.startedAt = value.startedAt
                row.endedAt = value.endedAt
                row.sourceRaw = value.source.rawValue
                row.pomodoroPhaseRaw = value.pomodoroPhase?.rawValue
                row.note = value.note
                row.activeSeconds = value.activeSeconds
            } else {
                context.insert(SDTimeEntry(id: value.id, workspaceID: value.workspaceID, taskID: value.taskID,
                                           title: value.title, startedAt: value.startedAt, endedAt: value.endedAt,
                                           sourceRaw: value.source.rawValue, pomodoroPhaseRaw: value.pomodoroPhase?.rawValue,
                                           note: value.note, activeSeconds: value.activeSeconds))
            }
        }

        let trashRows = try context.fetch(FetchDescriptor<SDTrashItem>())
        let trashIDs = Set(database.trashItems.map(\.id))
        for row in trashRows where !trashIDs.contains(row.id) { context.delete(row) }
        let trashByID = Dictionary(uniqueKeysWithValues: trashRows.map { ($0.id, $0) })
        for value in database.trashItems {
            let payload = try encodeJSON(value)
            if let row = trashByID[value.id] {
                row.deletedAt = value.deletedAt
                row.payloadJSON = payload
            } else {
                context.insert(SDTrashItem(id: value.id, deletedAt: value.deletedAt, payloadJSON: payload))
            }
        }

        let logRows = try context.fetch(FetchDescriptor<SDActivityLogEntry>())
        let logIDs = Set(database.activityLog.map(\.id))
        for row in logRows where !logIDs.contains(row.id) { context.delete(row) }
        let logByID = Dictionary(uniqueKeysWithValues: logRows.map { ($0.id, $0) })
        for value in database.activityLog {
            if let row = logByID[value.id] {
                row.timestamp = value.timestamp
                row.action = value.action
                row.target = value.target
                row.detail = value.detail
            } else {
                context.insert(SDActivityLogEntry(id: value.id, timestamp: value.timestamp,
                                                   action: value.action, target: value.target, detail: value.detail))
            }
        }

        let settingsRows = try context.fetch(FetchDescriptor<SDStoreSettings>())
        let settings: SDStoreSettings
        if let first = settingsRows.first {
            settings = first
            for extra in settingsRows.dropFirst() { context.delete(extra) }
        } else {
            settings = SDStoreSettings(id: Self.settingsID, schemaVersion: database.schemaVersion,
                                       workspaceOrderJSON: "[]", pinnedWorkspaceIDsJSON: "[]",
                                       workspaceShortcutsConfigured: false, workspaceSortModeRaw: WorkspaceSortMode.manual.rawValue,
                                       workspaceLastOpenedAtJSON: "{}", activeTimerJSON: nil)
            context.insert(settings)
        }
        settings.schemaVersion = database.schemaVersion
        settings.workspaceOrderJSON = try encodeJSON(database.workspaceOrder)
        settings.pinnedWorkspaceIDsJSON = try encodeJSON(database.pinnedWorkspaceIDs)
        settings.workspaceShortcutsConfigured = database.workspaceShortcutsConfigured
        settings.workspaceSortModeRaw = database.workspaceSortMode.rawValue
        settings.workspaceLastOpenedAtJSON = try encodeJSON(database.workspaceLastOpenedAt)
        settings.activeTimerJSON = try database.activeTimer.map(encodeJSON)
        settings.tagCategoriesJSON = try encodeJSON(database.tagCategories)
        settings.tagDefinitionsJSON = try encodeJSON(database.tagDefinitions)
    }

    private func decodeDatabase(from context: ModelContext, workspaces: [SDWorkspace]) throws -> GTDDatabase {
        let settings = try context.fetch(FetchDescriptor<SDStoreSettings>()).first
        let categories = try context.fetch(FetchDescriptor<SDProjectCategory>())
        let projects = try context.fetch(FetchDescriptor<SDProject>())
        let sections = try context.fetch(FetchDescriptor<SDProjectSection>())
        let tasks = try context.fetch(FetchDescriptor<SDTask>())
        let timeEntries = try context.fetch(FetchDescriptor<SDTimeEntry>())
        let trashItems = try context.fetch(FetchDescriptor<SDTrashItem>())
        let logs = try context.fetch(FetchDescriptor<SDActivityLogEntry>())

        return GTDDatabase(
            schemaVersion: settings?.schemaVersion ?? 11,
            workspaces: workspaces.map { Workspace(id: $0.id, name: $0.name, symbolName: $0.symbolName, colorHex: $0.colorHex) },
            workspaceOrder: settings.flatMap { decodeJSON([UUID].self, from: $0.workspaceOrderJSON) } ?? [],
            pinnedWorkspaceIDs: settings.flatMap { decodeJSON([UUID].self, from: $0.pinnedWorkspaceIDsJSON) } ?? [],
            workspaceShortcutsConfigured: settings?.workspaceShortcutsConfigured ?? false,
            workspaceSortMode: settings.flatMap { WorkspaceSortMode(rawValue: $0.workspaceSortModeRaw) } ?? .manual,
            workspaceLastOpenedAt: settings.flatMap { decodeJSON([String: Date].self, from: $0.workspaceLastOpenedAtJSON) } ?? [:],
            projects: projects.map { Project(id: $0.id, workspaceID: $0.workspaceID, category: $0.category, name: $0.name,
                                              colorHex: $0.colorHex, symbolName: $0.symbolName, note: $0.note, order: $0.order) },
            projectCategories: categories.map {
                ProjectCategory(
                    id: $0.id,
                    workspaceID: $0.workspaceID,
                    name: $0.name,
                    colorHex: $0.colorHex,
                    order: $0.order
                )
            },
            projectSections: sections.map { ProjectSection(id: $0.id, projectID: $0.projectID, name: $0.name, colorHex: $0.colorHex, order: $0.order) },
            tagCategories: settings.flatMap {
                $0.tagCategoriesJSON.flatMap { decodeJSON([TagCategory].self, from: $0) }
            } ?? [],
            tagDefinitions: settings.flatMap {
                $0.tagDefinitionsJSON.flatMap { decodeJSON([TaskTagDefinition].self, from: $0) }
            } ?? [],
            tasks: tasks.compactMap {
                decodeTask($0, migrateLegacyActionList: (settings?.schemaVersion ?? 0) < 8)
            },
            timeEntries: timeEntries.compactMap(decodeTimeEntry),
            activeTimer: settings.flatMap { $0.activeTimerJSON.flatMap { decodeJSON(ActiveTimer.self, from: $0) } },
            trashItems: trashItems.compactMap { decodeJSON(TrashItem.self, from: $0.payloadJSON) },
            activityLog: logs.map { ActivityLogEntry(id: $0.id, timestamp: $0.timestamp, action: $0.action, target: $0.target, detail: $0.detail) }
        )
    }

    private func decodeTask(_ row: SDTask, migrateLegacyActionList: Bool = false) -> GTDTask? {
        guard let status = TaskStatus(rawValue: row.statusRaw),
              let priority = Priority(rawValue: row.priorityRaw),
              let storedActionList = ActionList(rawValue: row.actionListRaw),
              let plannedPrecision = DeadlinePrecision(rawValue: row.plannedPrecisionRaw),
              let planRangeIntent = TaskPlanRangeIntent(rawValue: row.planRangeIntentRaw),
              let precision = DeadlinePrecision(rawValue: row.deadlinePrecisionRaw),
              let tags = decodeJSON([String].self, from: row.tagsJSON),
              let contexts = decodeJSON([String].self, from: row.contextsJSON),
              let executionSlots = decodeJSON([TaskExecutionSlot].self, from: row.executionSlotsJSON),
              let completedInstances = decodeJSON([String].self, from: row.completedInstancesJSON),
              let skippedInstances = decodeJSON([String].self, from: row.skippedInstancesJSON) else { return nil }
        let actionList: ActionList = if migrateLegacyActionList {
            switch status {
            case .waiting: .waiting
            case .someday: .somedayMaybe
            default: storedActionList
            }
        } else {
            storedActionList
        }
        return GTDTask(id: row.id, title: row.title, workspaceID: row.workspaceID, projectID: row.projectID,
                       sectionID: row.sectionID, parentID: row.parentID, status: status, priority: priority,
                       actionList: actionList,
                       tags: tags, contexts: contexts, plannedStart: row.plannedStart, plannedEnd: row.plannedEnd,
                       plannedPrecision: row.plannedStart == nil ? .none : (plannedPrecision == .none ? .minute : plannedPrecision),
                       planRangeIntent: planRangeIntent, executionSlots: executionSlots,
                       deadline: row.deadline, deadlinePrecision: precision, recurrence: row.recurrence, note: row.note,
                       createdAt: row.createdAt, updatedAt: row.updatedAt, completedAt: row.completedAt,
                       order: row.order, completedInstances: completedInstances, skippedInstances: skippedInstances)
    }

    private func decodeTimeEntry(_ row: SDTimeEntry) -> TimeEntry? {
        guard let source = TimeEntrySource(rawValue: row.sourceRaw) else { return nil }
        return TimeEntry(id: row.id, workspaceID: row.workspaceID, taskID: row.taskID, title: row.title,
                         startedAt: row.startedAt, endedAt: row.endedAt, source: source,
                         pomodoroPhase: row.pomodoroPhaseRaw.flatMap(PomodoroPhase.init(rawValue:)), note: row.note,
                         activeSeconds: row.activeSeconds)
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return string
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
