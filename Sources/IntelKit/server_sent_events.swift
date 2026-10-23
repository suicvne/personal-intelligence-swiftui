// Server-sent events (text/event-stream), as intel's streaming routes send them: `event: <name>`,
// `data: <JSON>`, then a blank line to end the event.

import Foundation

public struct ServerSentEvent: Sendable, Equatable {
    public let name: String
    public let data: String
}

/// Turns an event stream's lines into events. Feed it every line, the blank ones included.
public struct ServerSentEventParser: Sendable {
    private var name = ""
    private var data: [String] = []

    public init() {}

    /// The event this line completes, if any.
    public mutating func Feed(_ line: String) -> ServerSentEvent? {
        if line.isEmpty { return Dispatch() }
        if line.hasPrefix(":") { return nil }          // a comment (keep-alive)
        let (field, value) = Split(line)
        switch field {
        case "event": name = value
        case "data": data.append(value)
        default: break                                 // id and retry: not used by intel
        }
        return nil
    }

    /// The last event, when the stream ended without the blank line after it.
    public mutating func Finish() -> ServerSentEvent? { Dispatch() }

    /// Every event in a whole stream's text (for tests and samples).
    public static func Events(in text: String) -> [ServerSentEvent] {
        var parser = ServerSentEventParser()
        var events = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).compactMap {
            parser.Feed(String($0))
        }
        if let last = parser.Finish() { events.append(last) }
        return events
    }

    private mutating func Dispatch() -> ServerSentEvent? {
        defer { name = ""; data = [] }
        guard !data.isEmpty else { return nil }
        return ServerSentEvent(name: name.isEmpty ? "message" : name, data: data.joined(separator: "\n"))
    }

    private func Split(_ line: String) -> (field: String, value: String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        var value = line[line.index(after: colon)...]
        if value.first == " " { value = value.dropFirst() }
        return (String(line[..<colon]), String(value))
    }
}
