// Every sample in Samples/ is a real response from the intel server, captured from a fake world by
// personal-intelligence/tests/test_server.py. Refresh them after changing the API:
//
//   cd ../personal-intelligence
//   INTEL_EXPORT_SAMPLES=../personal-intelligence-swiftui/Tests/IntelKitTests/Samples \
//       .venv/bin/python -m pytest tests/test_server.py -k sample

import Foundation
import Testing
@testable import IntelKit

private func Sample<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Samples"))
    return try IntelClient.Decoder().decode(T.self, from: Data(contentsOf: url))
}

@Test func DecodesStatusAndSync() throws {
    let status = try Sample("status", as: StatusView.self)
    #expect(status.sources.contains { $0.name == "3dcrawler" && $0.kind == "git" })
    #expect(status.entityCounts["project"] == 1)
    #expect(status.needsAttention <= status.openObservations)
    #expect(try Sample("health", as: HealthView.self).ok)
    #expect(try Sample("sync", as: SyncResult.self).lines.isEmpty == false)
}

@Test func DecodesBriefAndObservations() throws {
    let brief = try Sample("brief", as: BriefView.self)
    #expect(brief.observations.first?.entities == ["Crawler"])
    #expect(brief.observations.first?.evidence.first?.kind == "commit")
    #expect(try Sample("observations", as: [ObservationView].self).isEmpty == false)
    #expect(try Sample("observation_response", as: ObservationView.self).status == "acknowledged")
}

@Test func DecodesProposalsAndDecisions() throws {
    let overview = try Sample("proposals", as: ProposalOverview.self)
    #expect(overview.predicates.contains("PART_OF"))
    #expect(overview.groups.contains { $0.name == "crawler-notes: essay.md" && $0.kinds["relationship"] == 1 })

    let detail = try Sample("proposal_detail", as: ProposalDetail.self)
    #expect(detail.fields == ["subject": "3dcrawler", "predicate": "DESCRIBES", "object": "The Pit"])
    #expect(detail.evidence.first?.context?.contains("The World Beneath") == true)

    let decision = try Sample("decision", as: DecisionResult.self)
    #expect(decision.proposal.summary == "The Pit PART_OF Crawler")
    #expect(decision.alsoApproved.count == 1)
    #expect(try Sample("proposal_group_preview", as: [ProposalView].self).count == 2)
    #expect(try Sample("group_decision", as: GroupDecisionResult.self).decision == "reject")
}

@Test func DecodesTasksEntitiesAndAnswers() throws {
    let tasks = try Sample("tasks", as: [TaskView].self)
    #expect(tasks.first?.location == "crawler-notes:ui.md:4")
    #expect(try Sample("task_import", as: ImportResult.self).proposed == 1)

    #expect(try Sample("entities", as: [EntitySummary].self).contains { $0.name == "Crawler" })
    let crawler = try Sample("entity_detail", as: EntityDetail.self)
    #expect(crawler.entity.type == "project")
    #expect(crawler.identifiers["manifest.file"] != nil)

    let answer = try Sample("ask", as: AnswerView.self)
    #expect(answer.mode == "retrieval_only")
    #expect(answer.references.contains { $0.kind == "tasks" })
}

@Test func FormatsTimestampsAndLinks() {
    let newYork = TimeZone(identifier: "America/New_York")!
    #expect(Formatting.Day("2026-10-18T16:47:45+00:00", timeZone: newYork) == "2026-10-18")
    #expect(Formatting.Day("2026-10-23T00:03:00+00:00", timeZone: newYork) == "2026-10-22")
    #expect(Formatting.Minute("2026-10-23T00:03:00+00:00", timeZone: newYork) == "2026-10-22 20:03")
    #expect(Formatting.Day("2026-10-23", timeZone: newYork) == "2026-10-23")
    #expect(Formatting.RelativeAge(nil) == "never")
    #expect(Formatting.OpenableURL("/tmp/note.md")?.isFileURL == true)
    #expect(Formatting.OpenableURL("http://git.example.com/x/-/issues/3")?.host() == "git.example.com")
}
