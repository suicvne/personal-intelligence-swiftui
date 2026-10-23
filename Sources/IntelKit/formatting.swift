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

    /// A URL to open for a record: a local file path or a web link.
    public static func OpenableURL(_ uri: String?) -> URL? {
        guard let uri, !uri.isEmpty else { return nil }
        return uri.hasPrefix("/") ? URL(fileURLWithPath: uri) : URL(string: uri)
    }
}
