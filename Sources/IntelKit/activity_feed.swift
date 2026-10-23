// How the Activity screen lays out the feed: events by local day, with runs of similar changes folded
// into one row ("12 new commits in cascade", "25 knowledge changes by the model").

import Foundation

/// Consecutive events that are the same kind of change in the same place; usually just one.
public struct ActivityRun: Identifiable, Sendable, Hashable {
    public let events: [EventView]

    public var id: Int { events[0].id }
    public var newest: EventView { events[0] }
    public var oldest: EventView { events[events.count - 1] }

    /// "12 new commits in cascade", "25 knowledge changes by the model".
    public var title: String {
        let event = newest
        if event.layer == "source" {
            let what = ActivityFeed.sourceChanges[event.type] ?? "\(event.type) events"
            return "\(events.count) \(what)" + (event.source.map { " in \($0)" } ?? "")
        }
        return "\(events.count) knowledge changes" + (ActivityFeed.Origin(event.origin).map { " \($0)" } ?? "")
    }
}

public struct ActivityDay: Identifiable, Sendable, Hashable {
    /// "2026-10-22", in local time.
    public let day: String
    /// When its newest event happened, for a "Today" / "Yesterday" heading.
    public let date: Date
    public let runs: [ActivityRun]

    public var id: String { day }
}

public enum ActivityFeed {
    /// Runs shorter than this are shown event by event.
    public static let foldsAt = 3
    /// Knowledge changes fold together when the same hand made them this close together (the model reading
    /// one note, a group of proposals approved at once).
    public static let burstGap: TimeInterval = 5 * 60

    static let sourceChanges = [
        "commit.added": "new commits", "document.created": "new documents", "document.modified": "documents changed",
        "document.deleted": "documents removed", "issue.created": "new issues", "issue.modified": "issues updated",
        "issue.state_changed": "issue state changes", "issue.rescheduled": "issues rescheduled",
    ]

    /// Who made a knowledge change, as words: "by you", "by the model", …; nil when unknown.
    public static func Origin(_ origin: String?) -> String? {
        switch origin {
        case "user": "by you"
        case "llm": "by the model"
        case "rule": "by intel's rules"
        case "source": "from your sources"
        default: nil
        }
    }

    /// The events (newest first, as the API sends them) by local day, similar neighbours folded into runs.
    public static func Days(_ events: [EventView], timeZone: TimeZone = .current) -> [ActivityDay] {
        var days: [ActivityDay] = []
        var day = ""
        var dayEvents: [EventView] = []
        func FinishDay() {
            guard let first = dayEvents.first else { return }
            days.append(ActivityDay(day: day, date: DateOf(first) ?? .distantPast, runs: Runs(dayEvents)))
            dayEvents = []
        }
        for event in events {
            let eventDay = Formatting.Day(event.at, timeZone: timeZone)
            if eventDay != day {
                FinishDay()
                day = eventDay
            }
            dayEvents.append(event)
        }
        FinishDay()
        return days
    }

    /// One day's events as runs: commits (or document changes, …) in one source, or knowledge changes made by
    /// the same hand within `burstGap` of each other.
    static func Runs(_ events: [EventView]) -> [ActivityRun] {
        var groups: [[EventView]] = []
        for event in events {
            if let previous = groups.last?.last, Continues(previous, with: event) {
                groups[groups.count - 1].append(event)
            } else {
                groups.append([event])
            }
        }
        return groups.flatMap { group in
            group.count >= foldsAt ? [ActivityRun(events: group)] : group.map { ActivityRun(events: [$0]) }
        }
    }

    private static func Continues(_ previous: EventView, with event: EventView) -> Bool {
        guard previous.layer == event.layer else { return false }
        if event.layer == "source" {
            return previous.source == event.source && previous.type == event.type
        }
        guard previous.origin == event.origin, let newer = DateOf(previous), let older = DateOf(event) else { return false }
        return newer.timeIntervalSince(older) <= burstGap
    }

    private static func DateOf(_ event: EventView) -> Date? {
        try? Date(event.at, strategy: .iso8601)
    }
}
