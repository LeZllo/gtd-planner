import Foundation

extension AppModel {
    func selectWorkspace(_ id: UUID) {
        guard database.workspaces.contains(where: { $0.id == id }) else { return }
        selection.selectedWorkspaceID = id
        selection.planningDay = nil
        selection.calendarDay = nil
        selection.selectedArchive = nil
        selection.selectedProjectID = nil
        selection.selectedTag = nil
        clearSelectedTask()
        if selection.selectedOrganization == .tags {
            selection.selectedTag = currentTagDefinitions.first.map { .tag($0.id) } ?? .untagged
        }
        database.workspaceLastOpenedAt[id.uuidString] = .now
        scheduleSave(invalidateIndex: false)
    }

    @discardableResult
    func addWorkspace(name: String, symbolName: String, colorHex: String = "#0A84FF") -> Workspace? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        let workspace = Workspace(
            name: cleanName,
            symbolName: symbolName,
            colorHex: colorHex
        )
        database.workspaces.append(workspace)
        database.workspaceOrder.append(workspace.id)
        scheduleSave(domain: .all)
        return workspace
    }

    func updateWorkspace(_ id: UUID, name: String, symbolName: String, colorHex: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              let index = database.workspaces.firstIndex(where: { $0.id == id }) else { return }
        database.workspaces[index].name = cleanName
        database.workspaces[index].symbolName = symbolName
        database.workspaces[index].colorHex = colorHex
        scheduleSave(domain: .workspace)
    }

    func setWorkspaceSortMode(_ mode: WorkspaceSortMode) {
        database.workspaceSortMode = mode
        scheduleSave(domain: .workspace)
    }

    func setDefaultWorkspace(_ id: UUID) {
        guard database.workspaces.contains(where: { $0.id == id }), defaultWorkspaceID != id else { return }
        database.pinnedWorkspaceIDs = [id]
        scheduleSave(domain: .workspace)
    }

    /// Compatibility shim for inactive legacy PIN controls.
    func togglePinnedWorkspace(_ id: UUID) {
        setDefaultWorkspace(id)
    }

    func moveWorkspaces(from source: IndexSet, to destination: Int) {
        if database.workspaceSortMode != .manual {
            // Begin the manual order from exactly what the user is looking at;
            // switching modes must not make the rows jump before the drag is
            // applied or require a second drag.
            database.workspaceOrder = orderedWorkspaces.map(\.id)
            database.workspaceSortMode = .manual
        }
        WorkspaceReorderService.move(in: &database, from: source, to: destination)
        scheduleSave(domain: .workspace)
    }

    func moveWorkspace(_ id: UUID, before targetID: UUID?) {
        guard id != targetID else { return }
        if database.workspaceSortMode != .manual {
            database.workspaceOrder = orderedWorkspaces.map(\.id)
            database.workspaceSortMode = .manual
        }
        guard WorkspaceReorderService.move(in: &database, workspaceID: id, before: targetID) else { return }
        scheduleSave(domain: .workspace)
    }
}
