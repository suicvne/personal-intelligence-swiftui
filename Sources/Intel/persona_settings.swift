// Personas in Settings: which one answers (its style for the answer text, its voice for reading aloud), and
// adding, changing and removing them. The choice is applied with Settings' Save, like the model; adding,
// changing and removing a persona takes effect right away.

import IntelKit
import SwiftUI

struct PersonaSection: View {
    let client: IntelClient
    @Binding var personas: PersonasView?
    /// The persona to use; nil means intel's config.
    @Binding var chosen: Int?
    let problem: String?
    @State private var editing: PersonaDraft?
    @State private var deleting: PersonaView?
    @State private var deleteProblem: String?

    var body: some View {
        Section {
            if let personas {
                Picker("Persona", selection: $chosen) {
                    Text("From intel's config").tag(Int?.none)
                    if !personas.personas.isEmpty { Divider() }
                    ForEach(personas.personas) { Text($0.name).tag(Optional($0.id)) }
                }
                if chosen == nil {
                    Text(ConfiguredSummary(personas)).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(personas.personas) { persona in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(persona.name)
                            Text(persona.style.isEmpty ? "Plain answers" : persona.style)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Edit") { editing = PersonaDraft(persona) }
                        Button("Delete", systemImage: "trash") { deleting = persona }
                            .labelStyle(.iconOnly)
                            .help("Delete \(persona.name)")
                    }
                }
                Button("Add Persona…", systemImage: "plus") { editing = PersonaDraft() }
                if let deleteProblem { Text(deleteProblem).font(.caption).foregroundStyle(.orange) }
            } else if let problem {
                Text(problem).font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        } header: {
            Text("Persona")
        } footer: {
            Text("How answers are written, and the voice that reads them aloud. Evidence and references stay plain.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: $editing) { draft in
            PersonaEditor(draft: draft, client: client, configuredVoice: personas?.configuredVoice ?? "") { updated in
                Loaded(updated)
            }
        }
        .confirmationDialog("Delete the persona “\(deleting?.name ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { persona in
            Button("Delete", role: .destructive) { Task { await Delete(persona) } }
        } message: { _ in
            Text("If it is in use, answers go back to the style and voice in intel's config.")
        }
    }

    private func ConfiguredSummary(_ personas: PersonasView) -> String {
        let style = personas.configuredStyle.isEmpty ? "plain answers" : "“\(personas.configuredStyle)”"
        return "Style: \(style). Voice: “\(personas.configuredVoice)”."
    }

    private func Delete(_ persona: PersonaView) async {
        do {
            Loaded(try await client.DeletePersona(id: persona.id))
            deleteProblem = nil
        } catch {
            deleteProblem = error.localizedDescription
        }
    }

    /// Show the personas intel now has, keeping the choice not saved yet unless its persona is gone.
    private func Loaded(_ updated: PersonasView) {
        personas = updated
        if let chosen, !updated.personas.contains(where: { $0.id == chosen }) {
            self.chosen = nil
        }
    }
}

/// A persona being added (no `personaId`) or changed.
struct PersonaDraft: Identifiable {
    let id = UUID()
    var personaId: Int?
    var name = ""
    var style = ""
    var voice = ""

    init() {}

    init(_ persona: PersonaView) {
        personaId = persona.id
        name = persona.name
        style = persona.style
        voice = persona.voice
    }
}

struct PersonaEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: PersonaDraft
    let client: IntelClient
    let configuredVoice: String
    let saved: (PersonasView) -> Void
    @State private var speech = SpeechPlayer()
    @State private var problem: String?
    @State private var saving = false

    private static let sample = "Hi. This is how I'll sound when I read your answers aloud."

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("Drill sergeant"))
            }
            Section {
                TextField("Answer style", text: $draft.style, prompt: Text("Warm and encouraging."), axis: .vertical)
                    .lineLimit(3...8)
            } footer: {
                Text("How the answer text is written. Empty: plainly.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                TextField("Voice", text: $draft.voice, prompt: Text(configuredVoice), axis: .vertical)
                    .lineLimit(3...8)
                SpeechButton(title: "Preview Voice", player: speech) {
                    let voice = draft.voice.trimmingCharacters(in: .whitespacesAndNewlines)
                    speech.Speak(PersonaEditor.sample, voice: voice.isEmpty ? nil : voice, with: client)
                }
            } footer: {
                Text("What the voice sounds like when answers are read aloud. Empty: the voice in intel's config.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.personaId == nil ? "Add" : "Save") { Task { await Save() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480)
        .onDisappear { speech.Stop() }
    }

    private func Save() async {
        saving = true
        defer { saving = false }
        do {
            let updated = if let id = draft.personaId {
                try await client.UpdatePersona(id: id, name: draft.name, style: draft.style, voice: draft.voice)
            } else {
                try await client.AddPersona(name: draft.name, style: draft.style, voice: draft.voice)
            }
            saved(updated)
            dismiss()
        } catch {
            problem = error.localizedDescription
        }
    }
}
