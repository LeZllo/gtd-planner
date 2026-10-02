import AppKit
import UniformTypeIdentifiers

enum DatabaseReplacementError: LocalizedError {
    case activeTimer
    var errorDescription: String? { "请先停止并保存当前计时，再替换全部数据" }
}

extension AppModel {
    func saveNow() {
        saveTask?.cancel()
        let generation = storage.advanceWriteGeneration()
        do { try storage.save(database, expectedGeneration: generation) }
        catch { notice = "保存失败：\(error.localizedDescription)" }
    }

    func exportDatabase() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "gtd-planner-backup.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try storage.exportData(database, to: url); notice = "已导出备份" }
        catch { notice = "导出失败：\(error.localizedDescription)" }
    }

    func importDatabase() {
        guard activeTimer == nil else { notice = DatabaseReplacementError.activeTimer.localizedDescription; return }
        let panel = NSOpenPanel()
        panel.title = "选择要恢复的 JSON 备份（将替换全部数据）"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try storage.importData(from: url)
            guard confirmDatabaseReplacement(source: "JSON 备份", taskCount: imported.tasks.count) else { return }
            let backupURL = automaticReplacementBackupURL()
            try replaceDatabase(with: imported, backupURL: backupURL)
            notice = "备份已恢复；替换前数据保存在 Backups/\(backupURL.lastPathComponent)"
        } catch { notice = "恢复失败，未替换当前数据：\(error.localizedDescription)" }
    }

    func importObsidianVault() {
        guard activeTimer == nil else { notice = DatabaseReplacementError.activeTimer.localizedDescription; return }
        do {
            let imported = try ObsidianImporter().chooseAndImport()
            guard confirmDatabaseReplacement(source: "Obsidian 资料库", taskCount: imported.tasks.count) else { return }
            let backupURL = automaticReplacementBackupURL()
            try replaceDatabase(with: imported, backupURL: backupURL)
            notice = "已迁移 \(database.tasks.count) 个任务；旧数据保存在 Backups/\(backupURL.lastPathComponent)"
        } catch ObsidianImporter.ImportError.noVaultSelected {
            // Closing a chooser is cancellation, not a failed import.
        } catch { notice = "迁移失败，未替换当前数据：\(error.localizedDescription)" }
    }

    /// The UI confirms this replacement first. Back up the current snapshot
    /// and persist the replacement before publishing it to any open window.
    /// A failed backup or store write leaves the in-memory database untouched.
    func replaceDatabase(with source: GTDDatabase, backupURL: URL) throws {
        guard activeTimer == nil else { throw DatabaseReplacementError.activeTimer }
        var normalized = source.workspaces.isEmpty ? .fresh() : source
        normalized.ensureWorkspaceMetadata()
        normalized.ensureProjectCategories()
        normalized.ensureProjectOrders()
        normalized.ensureProjectSections()
        normalized.ensureTagDefinitions()
        normalized.schemaVersion = max(normalized.schemaVersion, 11)

        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try storage.exportData(database, to: backupURL)
        saveTask?.cancel()
        // Saves queued before replacement cannot overwrite the restored store.
        let generation = storage.advanceWriteGeneration()
        try storage.save(normalized, expectedGeneration: generation)
        database = normalized
        selection.selectedWorkspaceID = normalized.pinnedWorkspaceIDs[0]
        selection.selectedOrganization = .projects
        selection.selectedSmartList = .all
        selection.selectedArchive = nil
        selection.selectedProjectID = nil
        selection.selectedTag = nil
        selection.plannerView = .list
        selection.planningDay = nil
        selection.calendarDay = nil
        selection.focusMode = normalized.activeTimer?.mode
        pendingDeletion = nil
        showNewTask = false
        query = ""
        invalidateQueryIndex()
        clearSelectedTask()
    }

    private func automaticReplacementBackupURL() -> URL {
        let timestamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        return storage.storeURL.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("before-replace-\(timestamp)-\(UUID().uuidString.prefix(8)).json")
    }

    private func confirmDatabaseReplacement(source: String, taskCount: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "用\(source)替换全部本地数据？"
        alert.informativeText = "当前所有工作区、项目、任务、实际记录、日志和垃圾箱将被替换，不是合并。将载入 \(taskCount) 项任务及文件中的计时状态（如有）。\n\n继续前会自动把当前数据导出到数据目录的 Backups 文件夹；备份或写入失败时不会替换。应用外观等本机偏好不受影响。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "备份并替换全部数据")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func scheduleSave(invalidateIndex: Bool = true, domain: ProjectionDomain = .all) {
        if invalidateIndex { invalidateQueryIndex(domain) }
        saveTask?.cancel()
        let snapshot = database
        let storage = storage
        let generation = storage.advanceWriteGeneration()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            do {
                try await Task.detached(priority: .utility) {
                    try storage.save(snapshot, expectedGeneration: generation)
                }.value
            } catch {
                self?.notice = "保存失败：\(error.localizedDescription)"
            }
        }
    }
}
