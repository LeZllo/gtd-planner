import AppKit
import Foundation

struct ObsidianImporter {
    enum ImportError: LocalizedError {
        case noVaultSelected

        var errorDescription: String? {
            switch self {
            case .noVaultSelected: "没有选择 Obsidian 资料库。"
            }
        }
    }

    @MainActor
    func chooseAndImport() throws -> GTDDatabase {
        let panel = NSOpenPanel()
        panel.title = "选择 Obsidian 资料库"
        panel.prompt = "导入"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { throw ImportError.noVaultSelected }
        return try importVault(at: url)
    }

    func importVault(at root: URL) throws -> GTDDatabase {
        var result = GTDDatabase.fresh()
        var workspaceIDs: [String: UUID] = [:]
        var projectIDs: [String: UUID] = [:]
        var pathToTaskID: [String: UUID] = [:]
        var pendingParents: [(UUID, String)] = []

        let urls = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "md" } ?? []

        for fileURL in urls {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let parsed = parseDocument(content)
            guard parsed.frontmatter["type"] == "gtd-task" else { continue }

            let workspaceName = parsed.frontmatter["workspace"] ?? "默认工作区"
            let workspaceID = workspaceID(for: workspaceName, in: &workspaceIDs, result: &result)
            let category = parsed.frontmatter["projectCategory"] ?? ""
            let projectName = parsed.frontmatter["project"] ?? ""
            var projectID: UUID?
            if !projectName.isEmpty {
                let key = "\(workspaceID.uuidString)|\(category)|\(projectName)"
                if let existing = projectIDs[key] {
                    projectID = existing
                } else {
                    let project = Project(id: UUID(), workspaceID: workspaceID, category: category.isEmpty ? "未分组" : category, name: projectName, colorHex: "#0AA58F")
                    projectID = project.id
                    projectIDs[key] = project.id
                    result.projects.append(project)
                }
            }

            let taskID = UUID(uuidString: parsed.frontmatter["taskId"] ?? "") ?? UUID()
            let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            let title = fileURL.deletingPathExtension().lastPathComponent
            let importedStatus = TaskStatus(rawValue: parsed.frontmatter["status"] ?? "inbox") ?? .inbox
            let importedActionList = ActionList(rawValue: parsed.frontmatter["actionList"] ?? "")
                ?? (importedStatus == .waiting ? .waiting : importedStatus == .someday ? .somedayMaybe : .nextAction)
            let plannedStart = parseDate(parsed.frontmatter["plannedStart"])
            let plannedEnd = parseDate(parsed.frontmatter["plannedEnd"])
            let task = GTDTask(id: taskID,
                               title: title,
                               workspaceID: workspaceID,
                               projectID: projectID,
                               parentID: nil,
                               status: importedStatus,
                               priority: Priority(rawValue: parsed.frontmatter["priority"] ?? "none") ?? .none,
                               actionList: importedActionList,
                               tags: parseArray(parsed.frontmatter["tags"]),
                               contexts: parseArray(parsed.frontmatter["contexts"]),
                               plannedStart: plannedStart,
                               plannedEnd: plannedEnd,
                               plannedPrecision: plannedStart == nil ? .none : .minute,
                               deadline: parseDate(parsed.frontmatter["deadline"]),
                               deadlinePrecision: DeadlinePrecision(rawValue: parsed.frontmatter["deadlinePrecision"] ?? "none") ?? .none,
                               recurrence: parsed.frontmatter["recurrence"] ?? "",
                               note: readSection(parsed.body, heading: "任务笔记"),
                               createdAt: parseDate(parsed.frontmatter["createdAt"]) ?? .now,
                               updatedAt: parseDate(parsed.frontmatter["updatedAt"]) ?? .now,
                               completedAt: parseDate(parsed.frontmatter["completedAt"]),
                               order: Int(parsed.frontmatter["order"] ?? "0") ?? 0,
                               completedInstances: parseArray(parsed.frontmatter["completedInstances"]),
                               skippedInstances: parseArray(parsed.frontmatter["skippedInstances"]))
            result.tasks.append(task)
            pathToTaskID[relativePath] = task.id
            pathToTaskID[fileURL.deletingPathExtension().path.replacingOccurrences(of: root.path + "/", with: "")] = task.id
            if let parent = parsed.frontmatter["parentTask"], !parent.isEmpty { pendingParents.append((task.id, parent)) }
        }

        for fileURL in urls {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let parsed = parseDocument(content)
            guard parsed.frontmatter["type"] == "gtd-time-entry" else { continue }
            let workspaceName = parsed.frontmatter["workspace"] ?? "默认工作区"
            let workspaceID = workspaceID(for: workspaceName, in: &workspaceIDs, result: &result)
            let taskPath = normalizedLink(parsed.frontmatter["task"] ?? "")
            let taskID = taskPath.flatMap { pathToTaskID[$0] }
            guard let startedAt = parseDate(parsed.frontmatter["startedAt"]), let endedAt = parseDate(parsed.frontmatter["endedAt"]) else { continue }
            let source = TimeEntrySource(rawValue: parsed.frontmatter["source"] ?? "stopwatch") ?? .stopwatch
            result.timeEntries.append(TimeEntry(workspaceID: workspaceID, taskID: taskID,
                                                title: parsed.frontmatter["title"] ?? fileURL.deletingPathExtension().lastPathComponent,
                                                startedAt: startedAt, endedAt: endedAt, source: source,
                                                pomodoroPhase: nil, note: readSection(parsed.body, heading: "记录备注")))
        }

        for (taskID, parentLink) in pendingParents {
            let normalized = normalizedLink(parentLink)
            guard let parentID = normalized.flatMap({ pathToTaskID[$0] }), parentID != taskID,
                  let index = result.tasks.firstIndex(where: { $0.id == taskID }) else { continue }
            result.tasks[index].parentID = parentID
        }

        return result
    }

    private func workspaceID(for name: String, in ids: inout [String: UUID], result: inout GTDDatabase) -> UUID {
        if let existing = ids[name] { return existing }
        let colors = ["#0AA58F", "#6B8FE8", "#E7B63B", "#A27BD4"]
        let index = result.workspaces.count % colors.count
        let workspace = Workspace(id: UUID(), name: name, symbolName: result.workspaces.isEmpty ? "square.grid.2x2" : "briefcase", colorHex: colors[index])
        ids[name] = workspace.id
        if result.workspaces.count == 1, result.workspaces[0].name == "默认工作区", result.workspaces[0].id != workspace.id {
            result.workspaces.removeAll()
        }
        result.workspaces.append(workspace)
        return workspace.id
    }

    private func parseDocument(_ content: String) -> (frontmatter: [String: String], body: String) {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n"), let end = normalized.range(of: "\n---", range: normalized.index(normalized.startIndex, offsetBy: 4)..<normalized.endIndex) else {
            return ([:], normalized)
        }
        let yaml = String(normalized[normalized.index(normalized.startIndex, offsetBy: 4)..<end.lowerBound])
        let bodyStart = normalized.index(end.upperBound, offsetBy: normalized[end.upperBound...].hasPrefix("\n") ? 1 : 0)
        var values: [String: String] = [:]
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            values[String(key)] = unquote(String(value))
        }
        return (values, String(normalized[bodyStart...]))
    }

    private func parseArray(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        let raw = unquote(value)
        if let data = raw.data(using: .utf8), let array = try? JSONSerialization.jsonObject(with: data) as? [String] { return array }
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",").map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
    }

    private func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2, trimmed.first == "\"", trimmed.last == "\"" {
            return String(trimmed.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
        }
        if trimmed.count >= 2, trimmed.first == "'", trimmed.last == "'" { return String(trimmed.dropFirst().dropLast()) }
        return trimmed
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = value.count == 10 ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: value)
    }

    private func normalizedLink(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let link = trimmed.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
        return link.hasSuffix(".md") ? link : link + ".md"
    }

    private func readSection(_ body: String, heading: String) -> String {
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## \(heading)" }) else { return "" }
        let end = lines[(start + 1)...].firstIndex(where: { $0.hasPrefix("## ") && !$0.hasPrefix("### ") }) ?? lines.endIndex
        return lines[(start + 1)..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
