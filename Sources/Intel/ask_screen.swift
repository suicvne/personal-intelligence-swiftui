// Ask: a question answered from stored evidence, with evidence and inference kept apart. Mirrors `intel ask`.

import IntelKit
import SwiftUI

struct AskScreen: View {
    @Environment(AppModel.self) private var model
    @State private var question = ""
    @State private var useModel = true
    @State private var answer: AnswerView?
    @State private var isAsking = false

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isAsking {
                        ProgressView("Thinking…").frame(maxWidth: .infinity)
                    } else if let answer {
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
                Button("Ask", action: AskNow)
                    .keyboardShortcut(.defaultAction)
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isAsking)
            }
            .padding(12)
            .background(.bar)
        }
        .navigationTitle("Ask")
    }

    private func AskNow() {
        let text = question.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !isAsking else { return }
        isAsking = true
        Task {
            defer { isAsking = false }
            answer = await model.Run { try await $0.Ask(question: text, useLlm: useModel) }
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
