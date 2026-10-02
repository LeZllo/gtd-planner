import Foundation
import Testing
@testable import GTDPlanner

@MainActor
struct PersistenceSafetyTests {
    private func database(title: String, workspace: Workspace) -> GTDDatabase {
        GTDDatabase(workspaces: [workspace], workspaceOrder: [workspace.id], pinnedWorkspaceIDs: [workspace.id],
                    tasks: [GTDTask(title: title, workspaceID: workspace.id, parentID: nil, status: .open)])
    }

    @Test("An older queued save cannot overwrite a newer write generation")
    func staleSaveIsIgnored() throws {
        let workspace = Workspace(name: "Generation", symbolName: "folder", colorHex: "#0A84FF")
        let storage = LocalDatabase(inMemory: true)
        let old = database(title: "Old", workspace: workspace)
        let new = database(title: "New", workspace: workspace)
        let oldGeneration = storage.advanceWriteGeneration()
        let newGeneration = storage.advanceWriteGeneration()
        try storage.save(new, expectedGeneration: newGeneration)
        try storage.save(old, expectedGeneration: oldGeneration)
        #expect(storage.load().tasks.map(\.id) == new.tasks.map(\.id))
    }

    @Test("Replacement writes a recoverable backup, saves new data, and clears navigation")
    func replacementBacksUpBeforePublishing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = Workspace(name: "Original", symbolName: "folder", colorHex: "#0A84FF")
        let replacementWorkspace = Workspace(name: "Replacement", symbolName: "calendar", colorHex: "#0A84FF")
        let storage = LocalDatabase(inMemory: true)
        let original = database(title: "Before", workspace: workspace)
        let replacement = database(title: "After", workspace: replacementWorkspace)
        let app = AppModel(database: original, storage: storage)
        app.selectSmartList(.calendar)
        app.selection.calendarDay = .distantPast
        app.query = "old search"
        app.selectTask(original.tasks[0].id)
        let backupURL = directory.appendingPathComponent("before.json")
        try app.replaceDatabase(with: replacement, backupURL: backupURL)
        #expect(try storage.importData(from: backupURL).tasks.map(\.id) == original.tasks.map(\.id))
        #expect(app.database.tasks.map(\.id) == replacement.tasks.map(\.id))
        #expect(storage.load().tasks.map(\.id) == replacement.tasks.map(\.id))
        #expect(app.selection.selectedWorkspaceID == replacementWorkspace.id)
        #expect(app.selection.selectedOrganization == .projects)
        #expect(app.selection.taskSelection == nil)
        #expect(app.selection.calendarDay == nil)
        #expect(app.query.isEmpty)
    }

    @Test("Backup failure leaves the current model and persistent store unchanged")
    func backupFailureDoesNotReplace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = Workspace(name: "Original", symbolName: "folder", colorHex: "#0A84FF")
        let storage = LocalDatabase(inMemory: true)
        let original = database(title: "Before", workspace: workspace)
        let app = AppModel(database: original, storage: storage)
        app.saveNow()
        var didThrow = false
        do {
            // A directory cannot be overwritten as the backup's JSON file.
            try app.replaceDatabase(with: database(title: "After", workspace: workspace), backupURL: directory)
        } catch { didThrow = true }
        #expect(didThrow)
        #expect(app.database.tasks.map(\.id) == original.tasks.map(\.id))
        #expect(storage.load().tasks.map(\.id) == original.tasks.map(\.id))
    }

    @Test("Replacement is refused while a timer is running or paused")
    func timerBlocksReplacement() {
        let workspace = Workspace(name: "Timer", symbolName: "timer", colorHex: "#0A84FF")
        let original = database(title: "Before", workspace: workspace)
        let app = AppModel(database: original, storage: LocalDatabase(inMemory: true))
        let backupURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { app.saveTask?.cancel(); try? FileManager.default.removeItem(at: backupURL) }
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        app.startStopwatch(for: nil, at: now)
        for paused in [false, true] {
            if paused { app.pauseTimer(at: now.addingTimeInterval(60)) }
            var didThrow = false
            do { try app.replaceDatabase(with: database(title: "After", workspace: workspace), backupURL: backupURL) }
            catch { didThrow = true }
            #expect(didThrow)
            #expect(app.database.tasks.map(\.id) == original.tasks.map(\.id))
            #expect(!FileManager.default.fileExists(atPath: backupURL.path))
        }
    }

    @Test("Imported replacement invalidates previously captured save tokens")
    func replacementInvalidatesOldSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = Workspace(name: "Restore", symbolName: "folder", colorHex: "#0A84FF")
        let storage = LocalDatabase(inMemory: true)
        let original = database(title: "Before", workspace: workspace)
        let replacement = database(title: "After", workspace: workspace)
        let app = AppModel(database: original, storage: storage)
        let stale = storage.advanceWriteGeneration()
        try app.replaceDatabase(with: replacement, backupURL: directory.appendingPathComponent("before.json"))
        try storage.save(original, expectedGeneration: stale)
        #expect(storage.load().tasks.map(\.id) == replacement.tasks.map(\.id))
    }

    @Test("Injected preferences affect new Today and Pomodoro sessions without changing active timers")
    func preferencesAreConnectedToExecution() throws {
        let suite = "PlannerSettingsIntegration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PlannerPreferences(defaults: defaults)
        preferences.defaultTodayViewMode = .list
        preferences.defaultPomodoroMinutes = 32
        let workspace = Workspace(name: "Preferences", symbolName: "timer", colorHex: "#0A84FF")
        let app = AppModel(database: database(title: "Task", workspace: workspace), storage: LocalDatabase(inMemory: true), preferences: preferences)
        defer { app.saveTask?.cancel() }
        #expect(app.selection.todayViewMode == .list)
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        app.startPomodoro(for: nil, at: now)
        #expect(app.activeTimer?.targetSeconds == 32 * 60)
        preferences.defaultPomodoroMinutes = 40
        #expect(app.activeTimer?.targetSeconds == 32 * 60)
        _ = app.stopTimer(at: now.addingTimeInterval(60))
        app.startPomodoro(for: nil, at: now.addingTimeInterval(120))
        #expect(app.activeTimer?.targetSeconds == 40 * 60)
    }
}
