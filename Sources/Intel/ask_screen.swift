// Ask: a question answered from stored evidence, with evidence and inference kept apart. Mirrors `intel ask`.
// The answer text appears while the model writes it; evidence and references follow when it is done.

import IntelKit
import SwiftUI

struct AskScreen: View {
    @Environment(AppModel.self) private var model
    @State private var question = ""
    @State private var useModel = true
    @State private var answer: AnswerView?
    /// The answer text so far, while the model writes it (replaced by `answer` when that arrives).
    @State private var streamed = ""
    @State private var asking: Task<Void, Never>?

    private var isAsking: Bool { asking != nil }

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let answer {
                        Text(answer.text).font(.title3).textSelection(.enabled)
                        Statements("Evidence (what the records show)", answer.evidence)
                        Statements("Inference (interpretation, not established fact)", answer.inferences)
                        Lines("Missing or uncertain", answer.gaps)
                        Lines("Ambiguous names (not assumed)",
                              answer.ambiguous.map { "'\($0.key)' could be: \($0.value.joined(separator: ", "))" })
                        References(answer.references)
                        if !answer.invalidRefs.isEmpty {
                            Text("The model cited unknown references \(answer.invalidRefs.joined(separator: ", ")); they were discarded.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if let note = answer.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                    } else if isAsking && streamed.isEmpty {
                        ProgressView("Thinking…").frame(maxWidth: .infinity)
                    } else if !streamed.isEmpty {
                        Text(streamed).font(.title3).textSelection(.enabled)
                        if isAsking {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Writing… evidence and references follow.")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Stopped before the answer was complete.").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        ContentUnavailableView("Ask about your projects", systemImage: "questionmark.bubble",
                                               description: Text("Answers cite the notes, commits and issues they come from."))
                    }
                }
                .padding(20)
                .frame(maxWidth: 820, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("What has changed in Project Succubi recently?", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(AskNow)
                Toggle("Use the model", isOn: $useModel)
                    .toggleStyle(.checkbox)
                    .help("Off: show the retrieved evidence without a written answer")
                if isAsking {
                    Button("Stop") { asking?.cancel() }
                        .keyboardShortcut(.cancelAction)
                        .help("Stop the model writing (Esc)")
                } else {
                    Button("Ask", action: AskNow)
                        .keyboardShortcut(.defaultAction)
                        .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(12)
            .background(.bar)
        }
        .navigationTitle("Ask")
        .onDisappear { asking?.cancel() }    // leaving the screen loses the answer, so stop the model too
    }

    private func AskNow() {
        let text = question.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isAsking else { return }
        answer = nil
        streamed = ""
        asking = Task {
            await model.Follow(model.client.AskStream(question: text, useLlm: useModel)) { event in
                switch event {
                case .delta(let piece): streamed += piece
                case .answer(let final): answer = final
                }
            }
            asking = nil
        }
    }

    @ViewBuilder
    private func Statements(_ title: String, _ statements: [CitedStatement]) -> some View {
        if !statements.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                ForEach(statements, id: \.self) { statement in
                    Text("• \(statement.statement)" + (statement.refs.isEmpty ? "" : "  [\(statement.refs.joined(separator: ", "))]"))
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func Lines(_ title: String, _ lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                ForEach(lines, id: \.self) { Text("• \($0)").textSelection(.enabled) }
            }
        }
    }

    @ViewBuilder
    private func References(_ references: [ReferenceView]) -> some View {
        if !references.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("References").font(.headline)
                ForEach(references) { reference in
                    HStack(alignment: .firstTextBaseline) {
                        Text(reference.ref).font(.caption.monospaced()).frame(width: 34, alignment: .leading)
                        Text(reference.label).lineLimit(2)
                        Spacer()
                        OpenButton(title: "Open", uri: reference.uri)
                    }
                }
            }
        }
    }
}
