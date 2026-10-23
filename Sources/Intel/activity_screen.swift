// Activity: what changed recently, in your sources and in what intel knows, newest first. Mirrors
// `intel events`, without the bookkeeping events (a repository first seen), as in the brief.
// Runs of similar changes fold into one row ("12 new commits in cascade"); expand it to see them.

import AppKit
import IntelKit
import SwiftUI

struct ActivityScreen: View {
    @Environment(AppModel.self) private var model
    @State private var events: [EventView] = []
    @State private var nextBefore: Int?
    @State private var layer = ""               // "", "source" or "semantic"
    @State private var filter = ""
    @State private var isLoading = false
    /// Counts loads of the first page, so a page of earlier activity that arrives after one is dropped.
    @State private var generation = 0

    var body: some View {
        Loadable(isLoading: isLoading, isEmpty: Visible.isEmpty,
                 emptyTitle: filter.isEmpty ? "No recorded activity" : "Nothing loaded matches", emptySymbol: "clock") {
            List {
                ForEach(ActivityFeed.Days(Visible)) { day in
                    Section(DayTitle(day.date)) {
                        ForEach(day.runs) { run in
                            if run.events.count == 1 {
                                EventRow(event: run.newest)
                            } else {
                                RunRow(run: run)
                            }
                        }
                    }
                }
                if nextBefore != nil {
                    Button(isLoading ? "Loading…" : "Show earlier activity") { Task { await LoadMore() } }
                        .buttonStyle(.link)
                        .disabled(isLoading)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Activity")
        .searchable(text: $filter, prompt: "Filter by text, source or entity")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $layer) {
                    Text("Everything").tag("")
                    Text("Sources").tag("source")
                    Text("Knowledge").tag("semantic")
                }
                .pickerStyle(.segmented)
                .help("Changes in your sources (commits, notes, issues), in what intel knows, or both")
            }
        }
        .task(id: "\(model.refreshToken)-\(layer)") { await Load() }
    }

    /// The loaded events that match the filter. Only what is loaded is searched; "Show earlier activity" loads more.
    private var Visible: [EventView] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return events }
        return events.filter { event in
            [event.summary, event.source, event.entity].contains { $0?.lowercased().contains(needle) == true }
        }
    }

    private func Load() async {
        generation += 1
        isLoading = true
        defer { isLoading = false }
        if let page = await model.Run({ try await $0.Events(layer: layer.isEmpty ? nil : layer) }) {
            events = page.events
            nextBefore = page.nextBefore
        }
    }

    private func LoadMore() async {
        guard let before = nextBefore, !isLoading else { return }
        let started = generation
        isLoading = true
        defer { isLoading = false }
        let page = await model.Run { try await $0.Events(before: before, layer: layer.isEmpty ? nil : layer) }
        guard let page, started == generation else { return }  // reloaded meanwhile (refresh, or another layer)
        let known = Set(events.map(\.id))
        events += page.events.filter { !known.contains($0.id) }
        nextBefore = page.nextBefore
    }

    private func DayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let sameYear = calendar.isDate(date, equalTo: .now, toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.weekday(.wide).day().month(.wide))
                        : date.formatted(.dateTime.day().month(.wide).year())
    }
}

/// One change: what it was, when, and where (the source, or the entity it is about and who changed it).
private struct EventRow: View {
    let event: EventView

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ActivitySymbol(type: event.type)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary).lineLimit(2).textSelection(.enabled)
                Text(Detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            OpenButton(title: "Open", uri: event.uri)
        }
        .padding(.vertical, 2)
        .contextMenu {
            if let url = Formatting.OpenableURL(event.uri) {
                Button("Open") { NSWorkspace.shared.open(url) }
            }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(event.summary, forType: .string)
            }
        }
    }

    private var Detail: String {
        let place = event.layer == "source"
            ? event.source
            : event.entity.flatMap { name in      // only when the summary doesn't already name it (decisions do)
                event.summary.contains(name) ? nil : event.entityType.map { "\($0) \(name)" } ?? name
            }
        return [Formatting.Time(event.at), place, ActivityFeed.Origin(event.origin)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Several similar changes in a row, folded; expanding shows each one.
private struct RunRow: View {
    let run: ActivityRun
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(run.events) { EventRow(event: $0) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ActivitySymbol(type: run.newest.type)
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.title)
                    Text(Span).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// "22:40–23:18", or one time when they all happened in the same minute.
    private var Span: String {
        let newest = Formatting.Time(run.newest.at), oldest = Formatting.Time(run.oldest.at)
        return newest == oldest ? newest : "\(oldest)–\(newest)"
    }
}

private struct ActivitySymbol: View {
    let type: String

    var body: some View {
        Image(systemName: Name)
            .foregroundStyle(.secondary)
            .frame(width: 18)
    }

    private var Name: String {
        if type.hasSuffix(".renamed") { return "pencil" }
        switch type {
        case "commit.added": return "smallcircle.filled.circle"
        case "document.created": return "doc.badge.plus"
        case "document.modified": return "doc.text"
        case "document.deleted": return "trash"
        case "issue.created", "issue.modified": return "ticket"
        case "issue.state_changed": return "checkmark.circle"
        case "issue.rescheduled": return "calendar"
        case "entity.created": return "plus.circle"
        case "entity.merged": return "arrow.triangle.merge"
        case "entity.status_changed": return "flag"
        case "relationship.added": return "link"
        case "relationship.rejected": return "xmark.circle"
        case "decision.superseded": return "arrow.uturn.backward.circle"
        default: return "circle"
        }
    }
}
