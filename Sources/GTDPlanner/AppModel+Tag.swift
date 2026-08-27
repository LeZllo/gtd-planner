import Foundation

extension AppModel {
    var currentTagCategories: [TagCategory] {
        _ = taskRevision
        return database.tagCategories
            .filter { $0.workspaceID == selection.selectedWorkspaceID }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    var currentTagDefinitions: [TaskTagDefinition] {
        _ = taskRevision
        let categoryOrder = Dictionary(uniqueKeysWithValues: currentTagCategories.map { ($0.id, $0.order) })
        return database.tagDefinitions
            .filter { $0.workspaceID == selection.selectedWorkspaceID }
            .sorted {
                let leftCategoryOrder = $0.categoryID.flatMap { categoryOrder[$0] } ?? Int.max
                let rightCategoryOrder = $1.categoryID.flatMap { categoryOrder[$0] } ?? Int.max
                if leftCategoryOrder != rightCategoryOrder { return leftCategoryOrder < rightCategoryOrder }
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    var selectedTagDefinition: TaskTagDefinition? {
        guard case .tag(let id) = selection.selectedTag else { return nil }
        return tagDefinition(withID: id)
    }

    func tagDefinition(withID id: UUID) -> TaskTagDefinition? {
        _ = taskRevision
        return database.tagDefinitions.first {
            $0.id == id && $0.workspaceID == selection.selectedWorkspaceID
        }
    }

    func tagCategory(withID id: UUID) -> TagCategory? {
        _ = taskRevision
        return database.tagCategories.first {
            $0.id == id && $0.workspaceID == selection.selectedWorkspaceID
        }
    }

    func tasks(for selection: TagSelection) -> [GTDTask] {
        let tasks = currentTasks.filter { task in
            switch selection {
            case .tag(let tagID):
                guard let tag = tagDefinition(withID: tagID) else { return false }
                return task.tags.contains { namesMatch($0, tag.name) }
            case .untagged:
                return task.tags.isEmpty
            }
        }
        return tasks.sorted(by: TaskDisplayOrdering.flatList)
    }

    func taskCount(for tagID: UUID) -> Int {
        guard let tag = tagDefinition(withID: tagID) else { return 0 }
        return currentTasks.reduce(into: 0) { count, task in
            if task.tags.contains(where: { namesMatch($0, tag.name) }) { count += 1 }
        }
    }

    func projectUsageCount(for tagID: UUID) -> Int {
        guard let tag = tagDefinition(withID: tagID) else { return 0 }
        return Set(currentTasks.compactMap { task -> UUID? in
            guard task.tags.contains(where: { namesMatch($0, tag.name) }) else { return nil }
            return task.projectID
        }).count
    }

    func addTagCategory(name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        guard !currentTagCategories.contains(where: { namesMatch($0.name, cleanName) }) else {
            notice = "已存在同名标签分类"
            return
        }
        let nextOrder = (currentTagCategories.map(\.order).max() ?? -1) + 1
        database.tagCategories.append(TagCategory(
            workspaceID: selection.selectedWorkspaceID,
            name: cleanName,
            order: nextOrder
        ))
        appendLog(action: "新建标签分类", target: cleanName)
        scheduleSave(domain: .task)
    }

    @discardableResult
    func addTag(name: String, categoryID: UUID? = nil) -> TaskTagDefinition? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        let resolvedCategoryID = categoryID.flatMap { tagCategory(withID: $0)?.id }
        if let existing = currentTagDefinitions.first(where: { namesMatch($0.name, cleanName) }) {
            selection.selectedTag = .tag(existing.id)
            notice = "已选择现有标签“\(existing.name)”"
            return existing
        }
        let nextOrder = database.tagDefinitions
            .filter {
                $0.workspaceID == selection.selectedWorkspaceID && $0.categoryID == resolvedCategoryID
            }
            .map(\.order)
            .max()
            .map { $0 + 1 } ?? 0
        let definition = TaskTagDefinition(
            workspaceID: selection.selectedWorkspaceID,
            categoryID: resolvedCategoryID,
            name: cleanName,
            order: nextOrder
        )
        database.tagDefinitions.append(definition)
        selection.selectedTag = .tag(definition.id)
        clearSelectedTask()
        appendLog(action: "新建标签", target: cleanName)
        scheduleSave(domain: .task)
        return definition
    }

    func updateTagCategory(_ category: TagCategory) {
        guard let index = database.tagCategories.firstIndex(where: {
            $0.id == category.id && $0.workspaceID == selection.selectedWorkspaceID
        }) else { return }
        let cleanName = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        guard !currentTagCategories.contains(where: {
            $0.id != category.id && namesMatch($0.name, cleanName)
        }) else {
            notice = "已存在同名标签分类"
            return
        }
        var updated = category
        updated.name = cleanName
        updated.updatedAt = .now
        guard database.tagCategories[index] != updated else { return }
        database.tagCategories[index] = updated
        scheduleSave(domain: .task)
    }

    func updateTagDefinition(_ definition: TaskTagDefinition) {
        guard let index = database.tagDefinitions.firstIndex(where: {
            $0.id == definition.id && $0.workspaceID == selection.selectedWorkspaceID
        }) else { return }
        let original = database.tagDefinitions[index]
        let cleanName = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        guard !currentTagDefinitions.contains(where: {
            $0.id != definition.id && namesMatch($0.name, cleanName)
        }) else {
            notice = "已存在同名标签"
            return
        }

        var updated = definition
        updated.name = cleanName
        updated.workspaceID = selection.selectedWorkspaceID
        updated.categoryID = definition.categoryID.flatMap { tagCategory(withID: $0)?.id }
        updated.updatedAt = .now
        guard updated != original else { return }

        if !namesMatch(original.name, cleanName) || original.name != cleanName {
            rewriteTaskTags(replacing: original.name, with: cleanName, workspaceID: original.workspaceID)
        }
        database.tagDefinitions[index] = updated
        appendLog(action: "更新标签", target: cleanName, detail: "修改了标签属性")
        scheduleSave(domain: .task)
    }

    @discardableResult
    func mergeTag(_ sourceID: UUID, into targetID: UUID) -> Bool {
        guard sourceID != targetID,
              let sourceIndex = database.tagDefinitions.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = database.tagDefinitions.firstIndex(where: { $0.id == targetID }) else { return false }
        let source = database.tagDefinitions[sourceIndex]
        let target = database.tagDefinitions[targetIndex]
        guard source.workspaceID == selection.selectedWorkspaceID,
              target.workspaceID == source.workspaceID else { return false }

        rewriteTaskTags(replacing: source.name, with: target.name, workspaceID: source.workspaceID)
        database.tagDefinitions.remove(at: sourceIndex)
        if let refreshedTargetIndex = database.tagDefinitions.firstIndex(where: { $0.id == target.id }) {
            database.tagDefinitions[refreshedTargetIndex].updatedAt = .now
        }
        selection.selectedTag = .tag(target.id)
        clearSelectedTask()
        appendLog(action: "合并标签", target: source.name, detail: "已合并到 \(target.name)")
        scheduleSave(domain: .task)
        return true
    }

    func requestDeleteTagCategory(_ category: TagCategory) {
        let count = database.tagDefinitions.filter { $0.categoryID == category.id }.count
        pendingDeletion = DeletionRequest(
            target: .tagCategory(category.id),
            title: "删除标签分类？",
            message: "“\(category.name)”中的 \(count) 个标签会转入未分类，标签和任务都不会被删除。",
            confirmTitle: "删除分类"
        )
    }

    func requestDeleteTag(_ definition: TaskTagDefinition) {
        let count = taskCount(for: definition.id)
        pendingDeletion = DeletionRequest(
            target: .tag(definition.id),
            title: "删除标签？",
            message: "“\(definition.name)”会从 \(count) 个任务中移除，任务本身不会被删除。",
            confirmTitle: "删除标签"
        )
    }

    func deleteTagCategory(_ categoryID: UUID) {
        guard let categoryIndex = database.tagCategories.firstIndex(where: {
            $0.id == categoryID && $0.workspaceID == selection.selectedWorkspaceID
        }) else { return }
        let category = database.tagCategories[categoryIndex]
        var affectedCount = 0
        for index in database.tagDefinitions.indices where database.tagDefinitions[index].categoryID == categoryID {
            database.tagDefinitions[index].categoryID = nil
            database.tagDefinitions[index].updatedAt = .now
            affectedCount += 1
        }
        database.tagCategories.remove(at: categoryIndex)
        appendLog(action: "删除标签分类", target: category.name, detail: "\(affectedCount) 个标签已转入未分类")
        scheduleSave(domain: .task)
    }

    func deleteTagDefinition(_ tagID: UUID) {
        guard let tagIndex = database.tagDefinitions.firstIndex(where: {
            $0.id == tagID && $0.workspaceID == selection.selectedWorkspaceID
        }) else { return }
        let definition = database.tagDefinitions[tagIndex]
        var affectedCount = 0
        for taskIndex in database.tasks.indices where database.tasks[taskIndex].workspaceID == definition.workspaceID {
            let previousCount = database.tasks[taskIndex].tags.count
            database.tasks[taskIndex].tags.removeAll { namesMatch($0, definition.name) }
            if database.tasks[taskIndex].tags.count != previousCount {
                database.tasks[taskIndex].updatedAt = .now
                affectedCount += 1
            }
        }
        database.tagDefinitions.remove(at: tagIndex)
        if selection.selectedTag == .tag(tagID) {
            let next = database.tagDefinitions.first { $0.workspaceID == selection.selectedWorkspaceID }
            selection.selectedTag = next.map { .tag($0.id) } ?? .untagged
        }
        clearSelectedTask()
        appendLog(action: "删除标签", target: definition.name, detail: "已从 \(affectedCount) 个任务移除")
        scheduleSave(domain: .task)
    }

    /// Returns canonical workspace label names and creates definitions for
    /// ad-hoc labels entered through existing task editors.
    func canonicalTagNames(_ names: [String], workspaceID: UUID) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for rawName in names {
            let cleanName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { continue }
            let key = cleanName.localizedLowercase
            guard seen.insert(key).inserted else { continue }
            if let existing = database.tagDefinitions.first(where: {
                $0.workspaceID == workspaceID && namesMatch($0.name, cleanName)
            }) {
                result.append(existing.name)
                continue
            }
            let nextOrder = database.tagDefinitions
                .filter { $0.workspaceID == workspaceID && $0.categoryID == nil }
                .map(\.order)
                .max()
                .map { $0 + 1 } ?? 0
            let definition = TaskTagDefinition(
                workspaceID: workspaceID,
                name: cleanName,
                order: nextOrder
            )
            database.tagDefinitions.append(definition)
            result.append(definition.name)
        }
        return result
    }

    private func rewriteTaskTags(replacing sourceName: String, with targetName: String, workspaceID: UUID) {
        for taskIndex in database.tasks.indices where database.tasks[taskIndex].workspaceID == workspaceID {
            guard database.tasks[taskIndex].tags.contains(where: { namesMatch($0, sourceName) }) else { continue }
            var rewritten: [String] = []
            var seen = Set<String>()
            for name in database.tasks[taskIndex].tags {
                let replacement = namesMatch(name, sourceName) ? targetName : name
                let key = replacement.localizedLowercase
                guard seen.insert(key).inserted else { continue }
                rewritten.append(replacement)
            }
            database.tasks[taskIndex].tags = rewritten
            database.tasks[taskIndex].updatedAt = .now
        }
    }

    private func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedSame
    }
}
