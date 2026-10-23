// Tasks: tasks written in your notes, and the GitLab issue each is tracked as. Mirrors `intel tasks`.

import AppKit
import IntelKit
import SwiftUI

struct TasksScreen: View {
    @Environment(AppModel.self) private var model
    @State private var tasks: [TaskView] = []
    @State private var includeClosed = false
    @State private var filter = ""
    @State private var selection: TaskView.ID?
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            Loadable(isLoading: isLoading, isEmpty: Visible.isEmpty, emptyTitle: "No tasks found in your notes",
                     emptySymbol: "square.and.pencil") {
                Table(Visible, selection: $selection) {
                    TableColumn("Task", value: \.text)
                    TableColumn("Note", value: \.location).width(min: 160, ideal: 260)
                    TableColumn("Tracked as") { task in
                        Text(task.trackedAs ?? (task.backlog ? "backlog" : "—"))
                            .foregroundStyle(task.trackedAs == nil ? .secondary : .primary)
                    }
                    .width(min: 100, ideal: 170)
                    TableColumn("State", value: \.state).width(60)
                }
                .contextMenu(forSelectionType: TaskView.ID.self) { ids in
                    if let task = tasks.first(where: { ids.contains($0.id) }) {
                        Button("Open note") { Open(task.notePath) }
                        if task.issueUrl != nil { Button("Open issue") { Open(task.issueUrl) } }
                        Divider()
                        Button("Propose GitLab issues for this note's open tasks") { Import(task) }
                    }
                } primaryAction: { ids in
                    if let task = tasks.first(where: { ids.contains($0.id) }) { Open(task.issueUrl ?? task.notePath) }
                }
            }
        }
        .navigationTitle("Tasks")
        .searchable(text: $filter, prompt: "Filter by note or text")
        .toolbar {
            ToolbarItem {
                Toggle("Show done & removed", isOn: $includeClosed).toggleStyle(.checkbox)
            }
        }
        .safeAreaInset(edge: .bottom) { MessageBar(message: message) }
        .task(id: "\(model.refreshToken)-\(includeClosed)") { await Load() }
    }

    private var Visible: [TaskView] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return tasks }
        return tasks.filter { $0.text.lowercased().contains(needle) || $0.location.lowercased().contains(needle) }
    }

    private func Load() async {
        isLoading = true
        defer { isLoading = false }
        if let result = await model.Run({ try await $0.Tasks(includeClosed: includeClosed) }) {
            tasks = result
        }
    }

    private func Open(_ uri: String?) {
        if let url = Formatting.OpenableURL(uri) { NSWorkspace.shared.open(url) }
    }

    private func Import(_ task: TaskView) {
        Task {
            if let result = await model.Run({ try await $0.ImportTasks(note: "R\(task.recordId)") }) {
                message = "Proposed \(result.proposed) issues from \(result.note)"
                    + (result.unplaced > 0 ? "; \(result.unplaced) have no known GitLab project" : "")
                await model.LoadStatus()
            }
        }
    }
}
