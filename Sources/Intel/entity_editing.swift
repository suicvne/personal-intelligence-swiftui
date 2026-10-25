// Adding and correcting entities: like `intel entity add|rename|alias|status|describe|merge` and
// `intel relationship add`. Each sheet sends one correction; intel remembers it over anything it inferred.

import IntelKit
import SwiftUI

/// The types an entity can be added as here (decisions, goals and tasks come from their own commands and notes).
let addableEntityTypes = ["project", "component", "repository", "concept", "person", "location"]

struct AddEntitySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let added: (EntityDetail) async -> Void
    @State private var type: String
    @State private var name = ""
    @State private var aliases = ""
    @State private var description = ""
    @State private var isWorking = false
    @State private var failure: String?

    init(type: String, added: @escaping (EntityDetail) async -> Void) {
        _type = State(initialValue: addableEntityTypes.contains(type) ? type : "project")
        self.added = added
    }

    var body: some View {
        EditForm(title: "Add an entity",
                 footnote: "Notes, commits and issues that mention its names are linked to it.",
                 action: "Add", canSave: !Trimmed(name).isEmpty, isWorking: isWorking, failure: failure, save: Save) {
            Picker("Type", selection: $type) {
                ForEach(addableEntityTypes, id: \.self) { Text($0).tag($0) }
            }
            TextField("Name", text: $name)
            TextField("Other names", text: $aliases, prompt: Text("comma-separated (optional)"))
            TextField("Description", text: $description, prompt: Text("optional"), axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private func Save() {
        let names = aliases.split(separator: ",").map { Trimmed(String($0)) }.filter { !$0.isEmpty }
        isWorking = true
        failure = nil
        Task {
            defer { isWorking = false }
            let result = await model.Submit({
                try await $0.AddEntity(type: type, name: Trimmed(name), aliases: names,
                                       description: Trimmed(description).isEmpty ? nil : Trimmed(description))
            }, failed: { failure = $0 })
            guard let result else { return }
            dismiss()
            await added(result)
        }
    }
}

/// The corrections the entity pane offers.
enum EntityEdit: String, Identifiable {
    case rename, addName, status, description, relationship, merge

    var id: String { rawValue }
}

struct EntityEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let edit: EntityEdit
    let entity: EntityDetail
    /// After a correction was saved, with what to say about it.
    let saved: (String) async -> Void

    @State private var text = ""
    @State private var nameKind = "alias"
    @State private var status = "active"
    @State private var note = ""
    @State private var predicates: [PredicateView] = []
    @State private var predicate = "PART_OF"
    @State private var other: EntitySummary?
    @State private var reversed = false
    @State private var isWorking = false
    @State private var failure: String?

    private var name: String { entity.entity.name }

    var body: some View {
        Group {
            switch edit {
            case .rename:
                EditForm(title: "Rename \(name)",
                         footnote: "'\(name)' stays a former name, so what mentions it still links here.",
                         action: "Rename", canSave: !Trimmed(text).isEmpty && Trimmed(text) != name,
                         isWorking: isWorking, failure: failure, save: Save) {
                    TextField("New name", text: $text)
                    NoteField()
                }
            case .addName:
                EditForm(title: "Add a name for \(name)",
                         footnote: "What mentions this name links to \(name) from now on.",
                         action: "Add", canSave: !Trimmed(text).isEmpty, isWorking: isWorking, failure: failure, save: Save) {
                    TextField("Name", text: $text)
                    Picker("It is", selection: $nameKind) {
                        Text("another name").tag("alias")
                        Text("a name it used to have").tag("former")
                    }
                    NoteField()
                }
            case .status:
                EditForm(title: "Status of \(name)", footnote: StatusMeaning,
                         action: "Save", canSave: status != entity.entity.status || !Trimmed(note).isEmpty,
                         isWorking: isWorking, failure: failure, save: Save) {
                    Picker("Status", selection: $status) {
                        ForEach(["active", "paused", "done", "archived"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    NoteField(prompt: "why (optional; shown with the status)")
                }
            case .description:
                EditForm(title: "Describe \(name)", footnote: "Answers and the brief use it. Leave it empty to remove it.",
                         action: "Save", canSave: Trimmed(text) != (entity.description ?? ""),
                         isWorking: isWorking, failure: failure, save: Save) {
                    TextField("Description", text: $text, axis: .vertical).lineLimit(3...8)
                }
            case .relationship:
                EditForm(title: "Relate \(name) to…", footnote: RelationshipSentence,
                         action: "Add", canSave: other != nil, isWorking: isWorking, failure: failure, save: Save) {
                    Picker("Predicate", selection: $predicate) {
                        ForEach(predicates.isEmpty ? [PredicateView(name: predicate, meaning: "")] : predicates) {
                            Text($0.name).tag($0.name)
                        }
                    }
                    if let meaning = predicates.first(where: { $0.name == predicate })?.meaning {
                        LabeledContent("") { Text(meaning).font(.caption).foregroundStyle(.secondary) }
                    }
                    LabeledContent("Other") { EntityChooser(excluding: [entity.entity.id], selection: $other) }
                    Toggle("\(name) is the object", isOn: $reversed)
                    NoteField()
                }
                .task {
                    predicates = await model.Run { try await $0.Predicates() } ?? []
                }
            case .merge:
                EditForm(title: "Merge into \(name)", footnote: MergeConsequence, action: "Merge", destructive: true,
                         canSave: other != nil, isWorking: isWorking, failure: failure, save: Save) {
                    LabeledContent("The same as") { EntityChooser(excluding: [entity.entity.id], selection: $other) }
                    NoteField()
                }
            }
        }
        .onAppear {
            switch edit {
            case .rename: text = name
            case .description: text = entity.description ?? ""
            case .status: status = entity.entity.status
            default: break
            }
        }
    }

    private func NoteField(prompt: String = "why (optional; kept with the correction)") -> some View {
        TextField("Note", text: $note, prompt: Text(prompt))
    }

    private var StatusMeaning: String {
        switch status {
        case "paused": "Paused: on hold on purpose. The brief won't remind you it's inactive."
        case "done": "Done: finished. The brief won't remind you it's inactive."
        case "archived": "Archived: no longer relevant. The brief won't remind you it's inactive."
        default: "Active: being worked on. The brief reminds you when it goes quiet."
        }
    }

    private var RelationshipSentence: String {
        guard let other else { return "Pick what \(name) is related to." }
        let (subject, object) = reversed ? (other.name, name) : (name, other.name)
        return "\(subject) \(predicate) \(object), confirmed."
    }

    private var MergeConsequence: String {
        guard let other else { return "Pick the entity that is the same thing as \(name)." }
        return "'\(other.name)' becomes another name of \(name), and its links, relationships and activity move here. "
            + "This can't be undone here."
    }

    private func Save() {
        let id = entity.entity.id
        let note = Trimmed(note).isEmpty ? nil : Trimmed(note)
        let text = Trimmed(text)
        isWorking = true
        failure = nil
        Task {
            defer { isWorking = false }
            let message: String? = await model.Submit({ client in
                switch edit {
                case .rename:
                    _ = try await client.RenameEntity(id: id, name: text, note: note)
                    return "Renamed \(name) to \(text)"
                case .addName:
                    _ = try await client.AddEntityName(id: id, name: text, kind: nameKind, note: note)
                    return "'\(text)' now refers to \(name)"
                case .status:
                    _ = try await client.SetEntityStatus(id: id, status: status, note: note)
                    return "\(name) is \(status)"
                case .description:
                    _ = try await client.DescribeEntity(id: id, description: text)
                    return text.isEmpty ? "Removed the description of \(name)" : "Described \(name)"
                case .relationship:
                    guard let other else { return nil }
                    let (subject, object) = reversed ? (String(other.id), String(id)) : (String(id), String(other.id))
                    let added = try await client.AddRelationship(subject: subject, predicate: predicate, object: object,
                                                                 note: note)
                    return "\(added.subject) \(added.predicate) \(added.object)"
                case .merge:
                    guard let other else { return nil }
                    _ = try await client.MergeEntity(id: id, absorb: String(other.id), note: note)
                    return "Merged '\(other.name)' into \(name)"
                }
            }, failed: { failure = $0 }) ?? nil
            guard let message else { return }
            dismiss()
            await saved(message)
        }
    }
}

/// Pick another entity: type to narrow the list, click one.
struct EntityChooser: View {
    @Environment(AppModel.self) private var model
    /// Not offered: these entities, and entities of these types.
    var excluding: Set<Int> = []
    var excludingTypes: Set<String> = []
    @Binding var selection: EntitySummary?
    @State private var entities: [EntitySummary] = []
    @State private var filter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Find by name", text: $filter, prompt: Text("Find by name"))
                .labelsHidden()
            List(Visible, selection: Binding(get: { selection?.id },
                                             set: { id in selection = entities.first { $0.id == id } })) { entity in
                HStack {
                    Text(entity.name)
                    Spacer()
                    Text(entity.type).font(.caption).foregroundStyle(.secondary)
                }
                .tag(entity.id)
            }
            .listStyle(.bordered)
            .frame(height: 170)
        }
        .task {
            let all = await model.Run { try await $0.Entities() } ?? []
            entities = all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var Visible: [EntitySummary] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return entities.filter { entity in
            !excluding.contains(entity.id) && !excludingTypes.contains(entity.type)
                && (needle.isEmpty || ([entity.name] + entity.otherNames).contains { $0.lowercased().contains(needle) })
        }
    }
}

/// A correction's sheet: title, fields, what saving does, why it failed, and Cancel / the action.
struct EditForm<Fields: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let footnote: String
    let action: String
    var destructive = false
    let canSave: Bool
    let isWorking: Bool
    let failure: String?
    let save: () -> Void
    @ViewBuilder let fields: () -> Fields

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Form { fields() }
            Text(footnote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button("Cancel", role: .cancel) { dismiss() }
                Button(action, role: destructive ? .destructive : nil, action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || isWorking)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

private func Trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
