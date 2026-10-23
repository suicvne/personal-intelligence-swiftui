// Proposals: what intel inferred and is asking you about, grouped by where it came from.
// Mirrors `intel proposals` / `intel proposal show|approve|reject`, plus correcting a proposal
// before approving it (e.g. DESCRIBES -> PART_OF).

import IntelKit
import SwiftUI

struct ProposalsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var overview: ProposalOverview?
    @State private var selection: ProposalView.ID?
    @State private var filter = ""
    @State private var isLoading = false
    @State private var lastResult: String?
    @State private var groupDecision: GroupDecision?
    /// Group order fixed when the list loads (largest first) and kept while you review, so sections
    /// don't jump around as you approve or reject. Only an explicit refresh (⌘R) or a sync re-sorts.
    @State private var groupOrder: [String] = []

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Loadable(isLoading: isLoading, isEmpty: VisibleGroups.isEmpty,
                         emptyTitle: filter.isEmpty ? "No proposals waiting" : "Nothing matches",
                         emptySymbol: "checkmark.seal") {
                    List(selection: $selection) {
                        ForEach(VisibleGroups) { group in
                            Section {
                                ForEach(group.proposals) { proposal in
                                    ProposalRow(proposal: proposal).tag(proposal.id)
                                }
                            } header: {
                                GroupHeader(group: group) { decision in
                                    groupDecision = GroupDecision(group: group.name, decision: decision,
                                                                  count: group.proposals.count)
                                }
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { MessageBar(message: lastResult) }
            .frame(minWidth: 340, idealWidth: 420)

            Group {
                if let selection {
                    ProposalDetailPane(id: selection, predicates: overview?.predicates ?? []) { message in
                        await Decided(selection, message: message)
                    }
                    .id(selection)
                } else {
                    ContentUnavailableView("Select a proposal", systemImage: "hand.point.left",
                                           description: Text("Approve what's right, correct what's almost right, reject the rest."))
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Proposals")
        .searchable(text: $filter, prompt: "Filter by source or summary")
        .task(id: model.refreshToken) { await Load(resort: true) }
        .sheet(item: $groupDecision) { decision in
            GroupDecisionSheet(decision: decision) { message in
                lastResult = message
                await Load(resort: false)
                await model.LoadStatus()
            }
            .environment(model)
        }
    }

    private var VisibleGroups: [ProposalGroupView] {
        guard let overview else { return [] }
        let position = Dictionary(uniqueKeysWithValues: groupOrder.enumerated().map { ($1, $0) })
        let ordered = overview.groups.sorted { (position[$0.name] ?? .max) < (position[$1.name] ?? .max) }
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return ordered }
        return ordered.compactMap { group in
            let proposals = group.proposals.filter {
                $0.summary.lowercased().contains(needle) || $0.source.lowercased().contains(needle)
            }
            return proposals.isEmpty ? nil
                : ProposalGroupView(name: group.name, sources: group.sources, kinds: group.kinds, proposals: proposals)
        }
    }

    /// `resort`: take the server's order (largest group first). Otherwise keep the current order and
    /// append groups that weren't there before.
    private func Load(resort: Bool) async {
        isLoading = true
        defer { isLoading = false }
        guard let result = await model.Run({ try await $0.Proposals() }) else { return }
        let names = result.groups.map(\.name)
        if resort || groupOrder.isEmpty {
            groupOrder = names
        } else {
            groupOrder += names.filter { !groupOrder.contains($0) }
        }
        overview = result
    }

    /// After a decision: report it, reload, and move on to the next proposal in the list.
    private func Decided(_ id: ProposalView.ID, message: String) async {
        let ordered = VisibleGroups.flatMap(\.proposals).map(\.id)
        let next = ordered.firstIndex(of: id).flatMap { index in
            ordered.indices.contains(index + 1) ? ordered[index + 1] : (index > 0 ? ordered[index - 1] : nil)
        }
        lastResult = message
        await Load(resort: false)
        await model.LoadStatus()
        selection = next.flatMap { candidate in VisibleGroups.flatMap(\.proposals).contains { $0.id == candidate } ? candidate : nil }
    }
}

private struct ProposalRow: View {
    let proposal: ProposalView

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            KindBadge(kind: proposal.kind)
            Text(proposal.summary.replacingOccurrences(of: "Decision: ", with: ""))
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }
}

private struct GroupHeader: View {
    let group: ProposalGroupView
    let decideAll: (String) -> Void

    var body: some View {
        HStack {
            Text(group.name).lineLimit(1).truncationMode(.middle)
            Text("\(group.proposals.count)").foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button("Approve all \(group.proposals.count)…") { decideAll("approve") }
                Button("Reject all \(group.proposals.count)…") { decideAll("reject") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

struct GroupDecision: Identifiable {
    let group: String
    let decision: String
    let count: Int
    var id: String { group + decision }
}

private struct GroupDecisionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let decision: GroupDecision
    let done: (String) async -> Void
    @State private var note = ""
    @State private var preview: [ProposalView]?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(decision.decision.capitalized) every proposal from \(decision.group)?").font(.headline)
            if let preview {
                Text("\(preview.count) proposals: "
                     + Dictionary(grouping: preview, by: \.kind).map { "\($0.value.count) \($0.key)" }.sorted().joined(separator: ", "))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
            TextField(decision.decision == "reject" ? "Why? (remembered with the rejection)" : "Note (optional)",
                      text: $note)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(decision.decision.capitalized) {
                    Task {
                        let result = await model.Run {
                            try await $0.DecideGroup(decision.group, decision: decision.decision,
                                                     note: note.isEmpty ? nil : note)
                        }
                        if let result {
                            await done("\(result.decision == "approve" ? "Approved" : "Rejected") \(result.decided) from \(decision.group)")
                        }
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview?.isEmpty ?? true)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { preview = await model.Run { try await $0.PreviewGroup(decision.group) } }
    }
}

// MARK: - Detail

private struct ProposalDetailPane: View {
    @Environment(AppModel.self) private var model
    let id: Int
    let predicates: [String]
    let decided: (String) async -> Void
    @State private var detail: ProposalDetail?
    @State private var edited: [String: String] = [:]
    @State private var note = ""
    @State private var isWorking = false
    /// Why the last approve/reject failed, shown next to the buttons.
    @State private var failure: String?

    /// Fields in a sensible reading order.
    private static let fieldOrder = ["subject", "predicate", "object", "type", "name", "kind", "description",
                                     "statement", "rationale", "title"]

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        KindBadge(kind: detail.proposal.kind)
                        Text(detail.proposal.summary).font(.title3.weight(.semibold)).textSelection(.enabled)
                    }
                    Text("From \(detail.proposal.source) · \(detail.proposal.origin)"
                         + (detail.proposal.confidence.map { " · confidence \($0.formatted(.number.precision(.fractionLength(2))))" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                    if let rationale = detail.rationale {
                        Text(rationale).foregroundStyle(.secondary)
                    }
                    ForEach(detail.evidence, id: \.self) { EvidenceCard(evidence: $0) }
                    if detail.proposal.status == "pending" {
                        Editor(detail)
                        Decision()
                    } else {
                        Text("Already \(detail.proposal.status)" + (detail.decisionNote.map { ": \($0)" } ?? ""))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            } else {
                ProgressView().padding(40)
            }
        }
        .task {
            if let result = await model.Run({ try await $0.Proposal(id: id) }) {
                detail = result
                edited = result.fields
            }
        }
    }

    @ViewBuilder
    private func Editor(_ detail: ProposalDetail) -> some View {
        let keys = detail.fields.keys.sorted { (Self.fieldOrder.firstIndex(of: $0) ?? 99) < (Self.fieldOrder.firstIndex(of: $1) ?? 99) }
        if !keys.isEmpty {
            GroupBox("Correct before approving") {
                Form {
                    ForEach(keys, id: \.self) { key in
                        Field(key)
                    }
                }
                .padding(4)
            }
        }
    }

    @ViewBuilder
    private func Field(_ key: String) -> some View {
        let binding = Binding(get: { edited[key] ?? "" }, set: { edited[key] = $0 })
        switch key {
        case "predicate":
            Picker("Predicate", selection: binding) {
                ForEach(Array(Set(predicates + [binding.wrappedValue])).sorted(), id: \.self) { Text($0).tag($0) }
            }
        case "kind":
            Picker("Name is", selection: binding) {
                Text("another name").tag("alias")
                Text("a former name").tag("former")
                Text("the main name now").tag("canonical")
            }
        case "description", "statement", "rationale":
            TextField(key.capitalized, text: binding, axis: .vertical).lineLimit(1...4)
        default:
            TextField(key.capitalized, text: binding)
        }
    }

    private func Decision() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Note (why; kept with your decision)", text: $note)
            HStack {
                Button("Approve") { Decide("approve") }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                Button("Reject") { Decide("reject") }
                    .keyboardShortcut(.delete, modifiers: .command)
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Text("⌘↩ approve · ⌘⌫ reject").font(.caption).foregroundStyle(.tertiary)
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .disabled(isWorking)
    }

    private func Decide(_ decision: String) {
        guard let detail else { return }
        let changes = edited.filter { detail.fields[$0.key] != $0.value }
        isWorking = true
        failure = nil
        Task {
            defer { isWorking = false }
            let result = await model.Run {
                try await $0.Decide(id: id, decision: decision, note: note.isEmpty ? nil : note,
                                    edits: decision == "approve" && !changes.isEmpty ? changes : nil)
            }
            guard let result else {
                failure = model.problem ?? "That didn't work."
                return
            }
            var message = "P\(result.proposal.id) \(result.proposal.status): \(result.proposal.summary)"
            if !result.alsoApproved.isEmpty {
                message += " (also approved: \(result.alsoApproved.map(\.summary).joined(separator: ", ")))"
            }
            if let url = result.createdIssueUrl { message += " — created \(url)" }
            await decided(message)
        }
    }
}
