// Entities: what intel knows about your projects, repositories, components and more.
// Mirrors `intel entity list|show`, and adding and correcting them (entity_editing.swift): `intel entity
// add|rename|alias|status|describe|merge` and `intel relationship add|confirm|reject|end`.

import IntelKit
import SwiftUI

struct EntitiesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var entities: [EntitySummary] = []
    @State private var type = "project"
    @State private var filter = ""
    @State private var selection: EntitySummary.ID?
    @State private var isLoading = false
    @State private var adding = false

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
                    EntityDetailPane(id: selection) { await Load() }.id(selection)
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
            ToolbarItem {
                Button { adding = true } label: { Label("Add Entity", systemImage: "plus") }
                    .help("Add a project, component, repository, concept, person or location")
            }
        }
        .sheet(isPresented: $adding) {
            AddEntitySheet(type: type) { added in
                filter = ""
                if type != added.entity.type && !type.isEmpty {
                    type = added.entity.type        // reloads the list
                } else {
                    await Load()
                }
                selection = added.entity.id
            }
            .environment(model)
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
    /// After a correction: the list may need reloading (a new name, a merged entity gone).
    let changed: () async -> Void
    @State private var detail: EntityDetail?
    @State private var editing: EntityEdit?
    /// What the last correction did.
    @State private var message: String?

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(detail.entity.name).font(.title2.weight(.semibold))
                            Spacer()
                            EditMenu()
                        }
                        Text("\(detail.entity.type) · \(detail.entity.status)" + (detail.statusNote.map { " — \($0)" } ?? ""))
                            .foregroundStyle(.secondary)
                        if let description = detail.description { Text(description) }
                        if let decision = detail.decision { Text("Decision: \(decision)") }
                        if let goal = detail.goal { Text("Goal: \(goal)") }
                    }
                    Block("Names") {
                        ForEach(detail.names, id: \.self) { name in
                            let about = "\(name.kind) · \(name.origin)" + (name.until.map { " · until \(Formatting.Day($0))" } ?? "")
                            if name.kind == "canonical" {
                                Row(name.name, about)
                            } else {
                                Row(name.name, about) {
                                    Button("Remove '\(name.name)'") { RemoveName(name.name) }
                                }
                            }
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
                                    "\(relationship.status) · \(relationship.origin)") {
                                    if relationship.status != "confirmed" {
                                        Button("Confirm") { Decide(relationship, "confirm") }
                                    }
                                    if relationship.status != "rejected" {
                                        Button("Reject (not true; don't propose it again)") { Decide(relationship, "reject") }
                                        Button("End (no longer true; kept as history)") { Decide(relationship, "end") }
                                    }
                                }
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
        .safeAreaInset(edge: .bottom) { MessageBar(message: message) }
        .task { await Load() }
        .sheet(item: $editing) { edit in
            if let detail {
                EntityEditSheet(edit: edit, entity: detail) { done in await Changed(done) }
                    .environment(model)
            }
        }
    }

    private func EditMenu() -> some View {
        Menu {
            Button("Rename…") { editing = .rename }
            Button("Add a Name…") { editing = .addName }
            Button("Set Status…") { editing = .status }
            Button("Edit Description…") { editing = .description }
            Divider()
            Button("Add a Relationship…") { editing = .relationship }
            Divider()
            Button("Merge Another Entity Into This…") { editing = .merge }
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        .fixedSize()
        .help("Correct what intel knows about it")
    }

    private func Load() async {
        detail = await model.Run { try await $0.Entity(reference: String(id)) }
    }

    private func Changed(_ done: String) async {
        message = done
        await Load()
        await changed()
    }

    private func RemoveName(_ name: String) {
        Task {
            if await model.Run({ try await $0.RemoveEntityName(id: id, name: name) }) != nil {
                await Changed("Removed '\(name)'")
            }
        }
    }

    private func Decide(_ relationship: RelationshipView, _ action: String) {
        Task {
            if let result = await model.Run({ try await $0.DecideRelationship(id: relationship.id, action: action) }) {
                let done = ["confirm": "Confirmed", "reject": "Rejected", "end": "Ended"][action] ?? action
                await Changed("\(done): \(result.subject) \(result.predicate) \(result.object)")
            }
        }
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

    /// A line with things to do about it, in a menu at its end.
    private func Row<Actions: View>(_ text: String, _ detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Row(text, detail)
            Menu { actions() } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
        }
    }
}
