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

@Test func DecodesLlmModels() throws {
    let models = try Sample("llm_models", as: LlmModelsView.self)
    #expect(models.enabled && models.error == nil)
    #expect(models.configured == "test-model" && models.chosen == "gemma-4-26b-a4b" && models.current == models.chosen)
    #expect(models.available.contains("qwen-3.8-27b"))
    #expect(try Sample("llm_model", as: LlmModelsView.self).current == "gemma-4-26b-a4b")
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
    #expect(answer.mode == "retrieval_only" && answer.spokenText == answer.text)
    #expect(answer.references.contains { $0.kind == "tasks" })
}

@Test func DecodesPersonas() throws {
    let added = try Sample("persona_add", as: PersonasView.self)
    #expect(added.chosen == nil && added.personas.map(\.name) == ["Flirty"])
    let chosen = try Sample("personas", as: PersonasView.self)
    #expect(chosen.chosen == chosen.personas.first?.id && chosen.personas.first?.voice == "Breathy.")
    #expect(chosen.configuredStyle.isEmpty && !chosen.configuredVoice.isEmpty)
}

@Test func DecodesAStreamedAnswer() throws {
    let url = try #require(Bundle.module.url(forResource: "ask_stream", withExtension: "txt", subdirectory: "Samples"))
    let events = try ServerSentEventParser.Events(in: String(contentsOf: url, encoding: .utf8)).compactMap {
        try IntelClient.AskEventFrom($0)
    }
    var streamed = ""
    var final: AnswerView?
    for event in events {
        switch event {
        case .delta(let piece): streamed += piece
        case .answer(let answer): final = answer
        }
    }
    let answer = try #require(final)
    guard case .answer = events.last else { Issue.record("the answer comes last"); return }
    #expect(events.count > 2 && answer.mode == "llm" && answer.gaps == ["No issue data."])
    #expect(streamed == answer.text && streamed.contains("(\"ui.md\").\nNothing"))
    #expect(answer.text.hasSuffix("recorded [R1].") && answer.spokenText?.hasSuffix("recorded.") == true)
}

@Test func ParsesEventStreams() throws {
    let events = ServerSentEventParser.Events(in: ": keep-alive\r\n\r\nevent: delta\r\ndata: {\"text\": \"a\"}\r\n\r\n"
                                                  + "data: one\ndata:two\nid: 7\n\nevent: answer\ndata: {}")
    #expect(events == [ServerSentEvent(name: "delta", data: "{\"text\": \"a\"}"),
                       ServerSentEvent(name: "message", data: "one\ntwo"),
                       ServerSentEvent(name: "answer", data: "{}")])
    #expect(try IntelClient.AskEventFrom(ServerSentEvent(name: "progress", data: "{}")) == nil)
    #expect(throws: IntelError.self) {
        try IntelClient.AskEventFrom(ServerSentEvent(name: "error", data: #"{"error": "internal error: boom", "status": 500}"#))
    }
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
