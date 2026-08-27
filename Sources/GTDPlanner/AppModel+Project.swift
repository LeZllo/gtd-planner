import Foundation

extension AppModel {
    func addProject(name: String, category: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "未分组"
            : category.trimmingCharacters(in: .whitespacesAndNewlines)
        ensureProjectCategory(named: cleanCategory)
        let nextOrder = currentProjects
            .filter { $0.category.localizedCaseInsensitiveCompare(cleanCategory) == .orderedSame }
            .map(\.order)
            .max()
            .map { $0 + 1 } ?? 0
        let project = Project(
            workspaceID: selection.selectedWorkspaceID,
            category: cleanCategory,
            name: cleanName,
            colorHex: "#0AA58F",
            order: nextOrder
        )
        database.projects.append(project)
        selection.selectedProjectID = project.id
        scheduleSave(domain: .project)
    }

    func addProjectCategory(name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        guard !currentProjectCategories.contains(where: {
            $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame
        }) else {
            notice = "已存在同名项目分类"
            return
        }

        let nextOrder = (currentProjectCategories.map(\.order).max() ?? -1) + 1
        database.projectCategories.append(
            ProjectCategory(workspaceID: selection.selectedWorkspaceID, name: cleanName, order: nextOrder)
        )
        selection.selectedOrganization = .projects
        selection.selectedSmartList = .all
        selection.selectedProjectID = nil
        clearSelectedTask()
        selection.plannerView = .list
        scheduleSave(domain: .project)
    }

    func updateProjectCategoryColor(_ categoryID: UUID, colorHex: String) {
        guard let index = database.projectCategories.firstIndex(where: {
            $0.id == categoryID && $0.workspaceID == selection.selectedWorkspaceID
        }) else { return }

        let normalized = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, database.projectCategories[index].colorHex != normalized else { return }
        database.projectCategories[index].colorHex = normalized
        scheduleSave(domain: .project)
    }

    @discardableResult
    func moveProjectCategory(_ categoryID: UUID, beforeCategoryID: UUID? = nil) -> Bool {
        guard ProjectCategoryReorderService.move(
            in: &database,
            categoryID: categoryID,
            workspaceID: selection.selectedWorkspaceID,
            beforeCategoryID: beforeCategoryID
        ) else { return false }
        scheduleSave(domain: .project)
        return true
    }

    func addProjectSection(name: String, projectID: UUID?) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, let projectID,
              let project = database.projects.first(where: {
                  $0.id == projectID && $0.workspaceID == selection.selectedWorkspaceID
              }) else { return }
        guard !projectSections(for: project.id).contains(where: {
            $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame
        }) else {
            notice = "已存在同名分区"
            return
        }

        let nextOrder = (projectSections(for: project.id).map(\.order).max() ?? -1) + 1
        database.projectSections.append(
            ProjectSection(projectID: project.id, name: cleanName, colorHex: "#2F6FD0", order: nextOrder)
        )
        selection.selectedProjectID = project.id
        selection.selectedOrganization = .projects
        selection.selectedSmartList = .all
        clearSelectedTask()
        selection.plannerView = .list
        scheduleSave(domain: .projectAndTask)
    }

    @discardableResult
    func moveProjectSection(_ sectionID: UUID, beforeSectionID: UUID? = nil) -> Bool {
        guard ProjectSectionService.moveSection(
            in: &database,
            sectionID: sectionID,
            workspaceID: selection.selectedWorkspaceID,
            beforeSectionID: beforeSectionID
        ) else { return false }
        scheduleSave(domain: .projectAndTask)
        return true
    }

    func updateProject(_ project: Project) {
        guard let index = database.projects.firstIndex(where: { $0.id == project.id }) else { return }
        let originalCategory = database.projects[index].category
        var updated = project
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.category = updated.category.trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.name.isEmpty { return }
        if updated.category.isEmpty { updated.category = "未分组" }
        ensureProjectCategory(named: updated.category)
        if originalCategory.localizedCaseInsensitiveCompare(updated.category) != .orderedSame {
            updated.order = currentProjects
                .filter {
                    $0.id != updated.id &&
                    $0.category.localizedCaseInsensitiveCompare(updated.category) == .orderedSame
                }
                .map(\.order)
                .max()
                .map { $0 + 1 } ?? 0
        }
        database.projects[index] = updated
        appendLog(action: "更新项目", target: updated.name, detail: "修改了项目属性")
        scheduleSave(domain: .projectAndTask)
    }

    func updateProjectSection(_ section: ProjectSection) {
        guard let index = database.projectSections.firstIndex(where: { $0.id == section.id }),
              let project = database.projects.first(where: {
                  $0.id == section.projectID && $0.workspaceID == selection.selectedWorkspaceID
              }) else { return }

        let cleanName = section.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        guard !projectSections(for: project.id).contains(where: {
            $0.id != section.id && $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame
        }) else {
            notice = "已存在同名分区"
            return
        }

        var updated = section
        updated.name = cleanName
        database.projectSections[index] = updated
        appendLog(action: "更新分区", target: updated.name, detail: "修改了项目内分区名称")
        scheduleSave(domain: .projectAndTask)
    }

    @discardableResult
    func moveProject(_ projectID: UUID, toCategory category: String, beforeProjectID: UUID? = nil) -> Bool {
        guard ProjectReorderService.move(
            in: &database,
            projectID: projectID,
            workspaceID: selection.selectedWorkspaceID,
            toCategory: category,
            beforeProjectID: beforeProjectID
        ) else { return false }
        scheduleSave(domain: .project)
        return true
    }

    func ensureProjectCategory(named name: String) {
        ensureProjectCategory(named: name, workspaceID: selection.selectedWorkspaceID)
    }

    func ensureProjectCategory(named name: String, workspaceID: UUID) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        guard !database.projectCategories.contains(where: {
            $0.workspaceID == workspaceID && $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame
        }) else { return }

        let nextOrder = database.projectCategories
            .filter { $0.workspaceID == workspaceID }
            .map(\.order)
            .max() ?? -1
        database.projectCategories.append(
            ProjectCategory(workspaceID: workspaceID, name: cleanName, order: nextOrder + 1)
        )
    }
}
