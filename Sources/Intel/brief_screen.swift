// Brief: what deserves attention now, what changed, and what is waiting on you. Mirrors `intel brief`.
// Viewing it doesn't mark anything as seen; "Seen" (ack) and "Dismiss" do.

import IntelKit
import SwiftUI

struct BriefScreen: View {
    @Environment(AppModel.self) private var model
    @State private var brief: BriefView?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let brief {
                    Header(brief)
                    if brief.observations.isEmpty {
                        ContentUnavailableView("Nothing needs your attention", systemImage: "checkmark.circle",
                                               description: Text("Observations only appear when the evidence supports one."))
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(brief.observations) { observation in
                            ObservationCard(observation: observation) { await Load() }
                        }
                    }
                    Section("Source activity", lines: brief.activity)
                    Section("Knowledge changes", lines: brief.knowledgeChanges)
                    Waiting(brief)
                    if !model.lastSyncLines.isEmpty {
                        Section("Last sync", lines: model.lastSyncLines)
                    }
                } else if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .navigationTitle("Brief")
        .task(id: model.refreshToken) { await Load() }
    }

    private func Load() async {
        isLoading = true
        defer { isLoading = false }
        if let result = await model.Run({ try await $0.Brief() }) {
            brief = result
        }
    }

    private func Header(_ brief: BriefView) -> some View {
        Text(Formatting.LastHours(since: brief.windowStart, until: brief.createdAt))
            .font(.title3.weight(.semibold))
            .help("Changes since \(Formatting.Minute(brief.windowStart))")
    }

    @ViewBuilder
    private func Section(_ title: String, lines: [String]) -> some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                ForEach(lines, id: \.self) { line in
                    Text(line).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func Waiting(_ brief: BriefView) -> some View {
        let parts = [
            brief.pendingProposals > 0 ? "\(brief.pendingProposals) proposals to review" : nil,
            brief.ambiguousMentions > 0 ? "\(brief.ambiguousMentions) ambiguous references" : nil,
            brief.failedWork > 0 ? "\(brief.failedWork) failed reasoning items" : nil,
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text("Waiting on you: " + parts.joined(separator: " · ")).font(.callout)
        }
    }
}

struct ObservationCard: View {
    @Environment(AppModel.self) private var model
    let observation: ObservationView
    let afterResponse: () async -> Void
    @State private var showEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(observation.summary).font(.headline)
            Text(observation.explanation).textSelection(.enabled)
            HStack(spacing: 6) {
                Text("\(observation.category) · priority \(observation.priority) · confidence "
                     + observation.confidence.formatted(.number.precision(.fractionLength(2))))
                if let reason = observation.reason { Text("· \(reason)") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !observation.evidence.isEmpty {
                DisclosureGroup("Evidence", isExpanded: $showEvidence) {
                    ForEach(observation.evidence, id: \.self) { EvidenceCard(evidence: $0) }
                }
                .font(.callout)
            }
            HStack {
                Button("Seen") { Respond("ack") }
                    .help("Acknowledge: it only comes back if the situation changes")
                Button("Dismiss") { Respond("dismiss") }
                    .help("Don't show this situation again")
                Button("Not useful") { Respond("dismiss", unhelpful: true) }
                    .help("Dismiss, and show fewer observations of this kind")
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func Respond(_ action: String, unhelpful: Bool = false) {
        Task {
            _ = await model.Run { try await $0.RespondToObservation(id: observation.id, action: action, unhelpful: unhelpful) }
            await afterResponse()
            await model.LoadStatus()
        }
    }
}
