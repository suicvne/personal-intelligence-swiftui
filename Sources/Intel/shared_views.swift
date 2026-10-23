// Small views used on several screens.

import AppKit
import IntelKit
import SwiftUI

/// Opens a note in its app or a GitLab issue in the browser.
struct OpenButton: View {
    let title: String
    let uri: String?

    var body: some View {
        if let url = Formatting.OpenableURL(uri) {
            Button(title) { NSWorkspace.shared.open(url) }
                .buttonStyle(.link)
        }
    }
}

/// Why something is believed: the record it comes from, the quoted passage, and the text around it.
struct EvidenceCard: View {
    let evidence: EvidenceView

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text([evidence.kind, evidence.source.map { "in \($0)" }].compactMap { $0 }.joined(separator: " "))
                    .font(.caption).foregroundStyle(.secondary)
                Text(evidence.location ?? evidence.title ?? "").font(.caption.bold()).lineLimit(1)
                if evidence.stale {
                    Text("changed since").font(.caption2).padding(.horizontal, 4).background(.yellow.opacity(0.3))
                }
                Spacer()
                OpenButton(title: "Open", uri: evidence.uri)
            }
            if let context = evidence.context {
                Text(Highlighted(context, evidence.excerpt))
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            } else if let excerpt = evidence.excerpt {
                Text("“\(excerpt)”").font(.callout).textSelection(.enabled)
            }
            if let note = evidence.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if let model = evidence.model {
                Text("read by \(model)").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    /// The surrounding text with the quoted passage emphasized.
    private func Highlighted(_ context: String, _ excerpt: String?) -> AttributedString {
        var text = AttributedString(context.trimmingCharacters(in: .newlines))
        if let excerpt, let range = text.range(of: excerpt, options: .caseInsensitive) {
            text[range].backgroundColor = .yellow.opacity(0.35)
        } else {
            text.foregroundColor = .primary
        }
        return text
    }
}

struct KindBadge: View {
    let kind: String

    var body: some View {
        Text(kind)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(for: kind).opacity(0.18), in: Capsule())
            .foregroundStyle(Color(for: kind))
    }

    private func Color(for kind: String) -> SwiftUI.Color {
        switch kind {
        case "decision": .purple
        case "relationship": .blue
        case "entity": .teal
        case "alias": .orange
        case "issue": .green
        case "merge": .red
        default: .secondary
        }
    }
}

/// A screen's loading/empty/content states in one place.
struct Loadable<Content: View>: View {
    let isLoading: Bool
    let isEmpty: Bool
    let emptyTitle: String
    let emptySymbol: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isLoading && isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: emptySymbol)
        } else {
            content()
        }
    }
}

/// A one-line result shown at the bottom of a screen ("Proposed 3 issues from …"); nothing when empty.
struct MessageBar: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar)
        }
    }
}
