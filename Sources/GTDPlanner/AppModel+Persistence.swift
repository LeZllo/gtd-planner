import AppKit
import UniformTypeIdentifiers

extension AppModel {
    func saveNow() {
        do { try storage.save(database) }
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
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try storage.importData(from: url)
            var normalized = imported.workspaces.isEmpty ? .fresh() : imported
            normalized.ensureWorkspaceMetadata()
            normalized.ensureProjectCategories()
            normalized.ensureProjectOrders()
            normalized.ensureProjectSections()
            normalized.ensureTagDefinitions()
            normalized.schemaVersion = max(normalized.schemaVersion, 11)
            database = normalized
            selection.selectedWorkspaceID = database.pinnedWorkspaceIDs[0]
            selection.selectedProjectID = nil
            invalidateQueryIndex()
            clearSelectedTask()
            saveNow()
            notice = "已导入本地备份"
        } catch { notice = "导入失败：\(error.localizedDescription)" }
    }

    func importObsidianVault() {
        do {
            var imported = try ObsidianImporter().chooseAndImport()
            imported.ensureProjectCategories()
            imported.ensureProjectOrders()
            imported.ensureProjectSections()
            imported.ensureWorkspaceMetadata()
            imported.ensureTagDefinitions()
            imported.schemaVersion = max(imported.schemaVersion, 11)
            database = imported
            selection.selectedWorkspaceID = database.pinnedWorkspaceIDs[0]
            selection.selectedProjectID = nil
            invalidateQueryIndex()
            clearSelectedTask()
            saveNow()
            notice = "已从 Obsidian 导入 \(database.tasks.count) 个任务"
        } catch { notice = "导入 Obsidian 失败：\(error.localizedDescription)" }
    }

    func scheduleSave(invalidateIndex: Bool = true, domain: ProjectionDomain = .all) {
        if invalidateIndex {
            invalidateQueryIndex(domain)
        }
        saveTask?.cancel()
        let snapshot = database
        let storage = storage
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            do {
                try await Task.detached(priority: .utility) {
                    try storage.save(snapshot)
                }.value
            } catch {
                self?.notice = "保存失败：\(error.localizedDescription)"
            }
        }
    }
}
