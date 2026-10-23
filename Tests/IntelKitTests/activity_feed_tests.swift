// How the Activity screen groups the feed: by local day, with runs of similar changes folded.

import Foundation
import Testing
@testable import IntelKit

private let utc = TimeZone(identifier: "UTC")!

private func Commit(_ id: Int, _ at: String, in source: String = "cascade") -> EventView {
    EventView(id: id, layer: "source", type: "commit.added", summary: "New commit: \(id)", at: at, source: source,
              recordId: id, uri: nil, entityId: nil, entity: nil, entityType: nil, origin: nil)
}

private func Change(_ id: Int, _ at: String, by origin: String = "llm") -> EventView {
    EventView(id: id, layer: "semantic", type: id.isMultiple(of: 2) ? "entity.created" : "relationship.added",
              summary: "Change \(id)", at: at, source: nil, recordId: nil, uri: nil, entityId: 1, entity: "Cascade",
              entityType: "project", origin: origin)
}

@Test func GroupsByLocalDayNewestFirst() {
    let days = ActivityFeed.Days([Commit(3, "2026-10-23T01:00:00+00:00"), Commit(2, "2026-10-22T23:00:00+00:00", in: "intel"),
                                  Commit(1, "2026-10-21T10:00:00+00:00")], timeZone: utc)
    #expect(days.map(\.day) == ["2026-10-23", "2026-10-22", "2026-10-21"])
    let newYork = TimeZone(identifier: "America/New_York")!     // 01:00 UTC on the 23rd is still the 22nd there
    #expect(ActivityFeed.Days([Commit(3, "2026-10-23T01:00:00+00:00"), Commit(2, "2026-10-22T23:00:00+00:00")],
                              timeZone: newYork).map(\.day) == ["2026-10-22"])
}

@Test func FoldsRunsOfCommitsInOneSource() {
    let events = [Commit(6, "2026-10-22T23:00:00+00:00"), Commit(5, "2026-10-22T21:00:00+00:00"),
                  Commit(4, "2026-10-22T12:00:00+00:00"), Commit(3, "2026-10-22T11:00:00+00:00", in: "intel"),
                  Commit(2, "2026-10-22T10:00:00+00:00", in: "intel")]
    let runs = ActivityFeed.Days(events, timeZone: utc)[0].runs
    #expect(runs.map(\.events.count) == [3, 1, 1])                 // two in a row is too few to fold
    #expect(runs[0].title == "3 new commits in cascade")
    #expect(runs[0].newest.id == 6 && runs[0].oldest.id == 4)
}

@Test func FoldsBurstsOfKnowledgeChangesByTheSameHand() {
    let events = [Change(9, "2026-10-22T23:08:30+00:00"), Change(8, "2026-10-22T23:08:00+00:00"),
                  Change(7, "2026-10-22T23:05:00+00:00"), Change(6, "2026-10-22T23:01:00+00:00"),
                  Change(5, "2026-10-22T22:00:00+00:00"),                       // an hour earlier: not the same burst
                  Change(4, "2026-10-22T21:59:00+00:00", by: "user")]
    let runs = ActivityFeed.Days(events, timeZone: utc)[0].runs
    #expect(runs.map(\.events.count) == [4, 1, 1])
    #expect(runs[0].title == "4 knowledge changes by the model")
    #expect(ActivityFeed.Origin("user") == "by you" && ActivityFeed.Origin(nil) == nil)
}

@Test func NeverFoldsAcrossLayersOrDays() {
    let events = [Commit(5, "2026-10-22T00:30:00+00:00"), Commit(4, "2026-10-22T00:20:00+00:00"),
                  Commit(3, "2026-10-21T23:50:00+00:00"), Change(2, "2026-10-21T23:49:00+00:00"),
                  Commit(1, "2026-10-21T23:48:00+00:00")]
    let days = ActivityFeed.Days(events, timeZone: utc)
    #expect(days.map { $0.runs.map(\.events.count) } == [[1, 1], [1, 1, 1]])
}
