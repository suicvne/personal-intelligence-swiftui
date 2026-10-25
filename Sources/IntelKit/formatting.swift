// Small display helpers shared by the views.

import Foundation

public enum Formatting {
    /// "3 minutes ago" for an ISO-8601 timestamp from the API; "never" when missing.
    public static func RelativeAge(_ timestamp: String?, now: Date = .now) -> String {
        guard let timestamp, let date = try? Date(timestamp, strategy: .iso8601) else { return "never" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }

    /// "2026-10-18": the local calendar day of an ISO-8601 timestamp from the API (which is in UTC).
    /// A plain date without a time of day is shown as it is.
    public static func Day(_ timestamp: String?, timeZone: TimeZone = .current) -> String {
        Local(timestamp, format: "yyyy-MM-dd", width: 10, timeZone: timeZone)
    }

    /// "2026-10-18 20:03" in local time.
    public static func Minute(_ timestamp: String?, timeZone: TimeZone = .current) -> String {
        Local(timestamp, format: "yyyy-MM-dd HH:mm", width: 16, timeZone: timeZone)
    }

    /// "20:03": the local time of day of an ISO-8601 timestamp; "" for a plain date.
    public static func Time(_ timestamp: String?, timeZone: TimeZone = .current) -> String {
        Local(timestamp, format: "HH:mm", width: 0, timeZone: timeZone)
    }

    /// "Last 24 hours": the span a brief covers, from its window start to when it was made.
    public static func LastHours(since start: String?, until end: String) -> String {
        guard let start, let from = try? Date(start, strategy: .iso8601),
              let to = try? Date(end, strategy: .iso8601) else { return "Recent changes" }
        let hours = max(1, Int((to.timeIntervalSince(from) / 3600).rounded()))
        return hours == 1 ? "Last hour" : "Last \(hours) hours"
    }

    private static func Local(_ timestamp: String?, format: String, width: Int, timeZone: TimeZone) -> String {
        guard let timestamp else { return "" }
        guard timestamp.count > 10, let date = try? Date(timestamp, strategy: .iso8601) else {
            return String(timestamp.prefix(width))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// Whole local days from today to a calendar day ("2026-10-30"); negative once it has passed.
    public static func DaysUntil(_ day: String, now: Date = .now, timeZone: TimeZone = .current) -> Int? {
        guard let target = LocalDate(day, timeZone: timeZone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: target).day
    }

    /// "due today", "due tomorrow", "due in 5 days", "2 days overdue": a target date from today.
    public static func Due(_ day: String, now: Date = .now, timeZone: TimeZone = .current) -> String {
        guard let days = DaysUntil(day, now: now, timeZone: timeZone) else { return "due \(day)" }
        switch days {
        case 0: return "due today"
        case 1: return "due tomorrow"
        case 2...: return "due in \(days) days"
        case -1: return "a day overdue"
        default: return "\(-days) days overdue"
        }
    }

    /// The start of a calendar day ("2026-10-30") in local time.
    public static func LocalDate(_ day: String, timeZone: TimeZone = .current) -> Date? {
        DayFormatter(timeZone).date(from: String(day.prefix(10)))
    }

    /// "2026-10-30": the local calendar day of a date (e.g. one picked in a DatePicker).
    public static func CalendarDay(_ date: Date, timeZone: TimeZone = .current) -> String {
        DayFormatter(timeZone).string(from: date)
    }

    private static func DayFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// A URL to open for a record: a local file path or a web link.
    public static func OpenableURL(_ uri: String?) -> URL? {
        guard let uri, !uri.isEmpty else { return nil }
        return uri.hasPrefix("/") ? URL(fileURLWithPath: uri) : URL(string: uri)
    }
}
