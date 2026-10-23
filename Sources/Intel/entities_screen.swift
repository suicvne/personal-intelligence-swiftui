// Entities: what intel knows about your projects, repositories, components and more.
// Mirrors `intel entity list` / `intel entity show` (read-only for now; correct things with the CLI).

import IntelKit
import SwiftUI

struct EntitiesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var entities: [EntitySummary] = []
    @State private var type = "project"
    @State private var filter = ""
    @State private var selection: EntitySummary.ID?
    @State private var isLoading = false

    private let types = ["project", "component", "repository", "decision", "goal", "task", "concept", "person", "location"]

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Loadable(isLoading: isLoading, isEmpty: Visible.isEmpty, emptyTitle: "None", emptySymbol: "circle.dashed") {
                    List(Visible, selection: $selection) { entity in
                        VStack(alignment: .leading) {
                            Text(entity.name)
                            if !entity.otherNames.isEmpty || entity.status != "active" {
                                Text(([entity.status == "active" ? nil : entity.status] + entity.otherNames.prefix(3).map { $0 })
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(entity.id)
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 300)

            Group {
                if let selection {
                    EntityDetailPane(id: selection).id(selection)
                } else {
                    ContentUnavailableView("Select something", systemImage: "hand.point.left")
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Entities")
        .searchable(text: $filter, prompt: "Filter by name")
        .toolbar {
            ToolbarItem {
                Picker("Type", selection: $type) {
                    ForEach(types, id: \.self) { Text($0).tag($0) }
                    Divider()
                    Text("everything").tag("")
                }
                .pickerStyle(.menu)
                .help("Which kind of entity to list")
            }
        }
        .task(id: "\(model.refreshToken)-\(type)") { await Load() }
    }

    private var Visible: [EntitySummary] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return entities }
        return entities.filter { entity in
            ([entity.name] + entity.otherNames).contains { $0.lowercased().contains(needle) }
        }
    }

    private func Load() async {
        isLoading = true
        defer { isLoading = false }
        if let result = await model.Run({ try await $0.Entities(type: type.isEmpty ? nil : type) }) {
            entities = result
        }
    }
}

private struct EntityDetailPane: View {
    @Environment(AppModel.self) private var model
    let id: Int
    @State private var detail: EntityDetail?

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(detail.entity.name).font(.title2.weight(.semibold))
                        Text("\(detail.entity.type) · \(detail.entity.status)" + (detail.statusNote.map { " — \($0)" } ?? ""))
                            .foregroundStyle(.secondary)
                        if let description = detail.description { Text(description) }
                        if let decision = detail.decision { Text("Decision: \(decision)") }
                        if let goal = detail.goal { Text("Goal: \(goal)") }
                    }
                    Block("Names") {
                        ForEach(detail.names, id: \.self) { name in
                            Row(name.name, "\(name.kind) · \(name.origin)" + (name.until.map { " · until \(Formatting.Day($0))" } ?? ""))
                        }
                    }
                    if !detail.identifiers.isEmpty {
                        Block("Source identifiers") {
                            ForEach(detail.identifiers.sorted(by: { $0.key < $1.key }), id: \.key) { Row($0.value, $0.key) }
                        }
                    }
                    if !detail.properties.isEmpty {
                        Block("Stated in files") {
                            ForEach(detail.properties, id: \.self) { property in
                                Row("\(property["key"] ?? "") = \(property["value"] ?? "")", property["where"] ?? "")
                            }
                        }
                    }
                    if !detail.relationships.isEmpty {
                        Block("Relationships") {
                            ForEach(detail.relationships) { relationship in
                                Row("\(relationship.subject) \(relationship.predicate) \(relationship.object)",
                                    "\(relationship.status) · \(relationship.origin)")
                                    .strikethrough(relationship.status == "rejected")
                            }
                        }
                    }
                    if !detail.activity.isEmpty {
                        Block("Latest recorded activity") {
                            ForEach(detail.activity, id: \.self) { item in
                                Row(item.title ?? item.kind, "\(Formatting.Day(item.at)) · \(item.kind) · \(item.source)")
                            }
                        }
                    }
                    ForEach(detail.observations) { observation in
                        ObservationCard(observation: observation) { await Load() }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView().padding(40)
            }
        }
        .task { await Load() }
    }

    private func Load() async {
        detail = await model.Run { try await $0.Entity(reference: String(id)) }
    }

    private func Block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            content()
        }
    }

    private func Row(_ text: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).textSelection(.enabled)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
