// Sources: where intel reads from (folders of notes, git repositories, GitLab) and how each one's syncing goes.
// Mirrors `intel source list|add|enable|disable` and `intel sync --source`.

import AppKit
import IntelKit
import SwiftUI

struct SourcesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var sources: [SourceStatus] = []
    @State private var selection: SourceStatus.ID?
    @State private var filter = ""
    @State private var isLoading = false
    @State private var adding = false
    /// Sources being synced from this screen, by name.
    @State private var syncing: Set<String> = []
    @State private var message: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                Loadable(isLoading: isLoading, isEmpty: Visible.isEmpty,
                         emptyTitle: filter.isEmpty ? "No sources yet" : "Nothing matches", emptySymbol: "tray.2") {
                    List(Visible, selection: $selection) { source in
                        SourceRow(source: source, isSyncing: syncing.contains(source.name)).tag(source.id)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { MessageBar(message: message) }
            .frame(minWidth: 260, idealWidth: 320)

            Group {
                if let source = sources.first(where: { $0.id == selection }) {
                    SourceDetailPane(source: source, isSyncing: syncing.contains(source.name),
                                     sync: { Sync(source) }, setEnabled: { SetEnabled(source, $0) })
                } else {
                    ContentUnavailableView("Select a source", systemImage: "hand.point.left",
                                           description: Text("The folders of notes, git repositories and GitLab projects intel reads."))
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Sources")
        .searchable(text: $filter, prompt: "Filter by name or location")
        .toolbar {
            ToolbarItem {
                Button { adding = true } label: { Label("Add Source", systemImage: "plus") }
                    .help("Add a folder of notes, a git repository or GitLab projects")
            }
        }
        .sheet(isPresented: $adding) {
            AddSourceSheet { added, syncNow in
                filter = ""
                await Load()
                selection = added.id
                message = "Added \(added.name)" + (syncNow ? "" : "; the background service syncs it at its next cycle")
                if syncNow { Sync(added) }
                await model.LoadStatus()
            }
            .environment(model)
        }
        .task(id: model.refreshToken) { await Load() }
    }

    private var Visible: [SourceStatus] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return sources }
        return sources.filter { $0.name.lowercased().contains(needle) || ($0.location ?? "").lowercased().contains(needle) }
    }

    private func Load() async {
        isLoading = true
        defer { isLoading = false }
        if let result = await model.Run({ try await $0.Sources() }) {
            sources = result
        }
    }

    private func Sync(_ source: SourceStatus) {
        guard !syncing.contains(source.name) else { return }
        syncing.insert(source.name)
        message = "Syncing \(source.name)…"
        Task {
            if let result = await model.Run({ try await $0.Sync(sources: [source.name]) }) {
                message = (result.lines + (result.entitiesCreated > 0 ? ["\(result.entitiesCreated) new entities"] : []))
                    .joined(separator: " · ")
            } else {
                message = nil                   // the problem banner says why
            }
            syncing.remove(source.name)
            await Load()
            await model.LoadStatus()
        }
    }

    private func SetEnabled(_ source: SourceStatus, _ enabled: Bool) {
        Task {
            if let updated = await model.Run({ try await $0.SetSourceEnabled(id: source.id, enabled: enabled) }) {
                if let index = sources.firstIndex(where: { $0.id == updated.id }) { sources[index] = updated }
                message = enabled ? "Enabled \(updated.name)" : "Disabled \(updated.name); what it read is kept"
                await model.LoadStatus()
            }
        }
    }
}

/// How each kind of source is shown.
enum SourceKind {
    static func Name(_ kind: String) -> String {
        switch kind {
        case "filesystem": "Folder of notes"
        case "git": "Git repository"
        case "gitlab": "GitLab"
        default: kind
        }
    }

    static func Symbol(_ kind: String) -> String {
        switch kind {
        case "filesystem": "folder"
        case "git": "arrow.triangle.branch"
        case "gitlab": "network"
        default: "tray"
        }
    }
}

private struct SourceRow: View {
    let source: SourceStatus
    let isSyncing: Bool

    var body: some View {
        HStack {
            Image(systemName: SourceKind.Symbol(source.kind))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading) {
                Text(source.name)
                Text(source.enabled ? "\(source.records) records · synced \(Formatting.RelativeAge(source.lastSuccessAt))"
                                    : "disabled · \(source.records) records kept")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if isSyncing {
                ProgressView().controlSize(.small)
            } else if source.enabled && source.failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(source.lastError ?? "The last sync failed")
            }
        }
        .opacity(source.enabled ? 1 : 0.6)
    }
}

private struct SourceDetailPane: View {
    let source: SourceStatus
    let isSyncing: Bool
    let sync: () -> Void
    let setEnabled: @MainActor (Bool) -> Void

    /// Readable names for the settings intel stores (others are shown as they are).
    private static let settingNames = [
        "include": "Files read", "document_patterns": "Documents read", "include_documents": "Reads documents",
        "exclude_dirs": "Skips", "projects": "Projects", "groups": "Groups", "token_env": "Token from",
        "write_token_env": "Token for new issues", "verify_tls": "Verifies TLS", "ref": "Branch",
        "max_commits": "First import, at most", "include_manifests": "Reads project files",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name).font(.title2.weight(.semibold))
                    Text(SourceKind.Name(source.kind) + (source.discoveredFrom.map { " · discovered in \($0)" } ?? ""))
                        .foregroundStyle(.secondary)
                    if let location = source.location {
                        HStack(alignment: .firstTextBaseline) {
                            Text(location).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                            OpenButton(title: source.kind == "gitlab" ? "Open" : "Show in Finder", uri: location)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Toggle("Enabled", isOn: Binding(get: { source.enabled }, set: setEnabled))
                        .toggleStyle(.switch)
                        .help("A disabled source isn't synced; what it already read is kept")
                    Button(action: sync) { Label("Sync Now", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(!source.enabled || isSyncing)
                    if isSyncing {
                        ProgressView().controlSize(.small)
                        Text("Syncing…").foregroundStyle(.secondary)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    Fact("Records", "\(source.records)")
                    Fact("Last synced", source.lastSuccessAt.map {
                        "\(Formatting.RelativeAge($0)) (\(Formatting.Minute($0)))"
                    } ?? "never")
                    Fact("Last run", source.lastRun ?? "not yet")
                    if let seconds = source.pollIntervalSeconds, source.enabled {
                        Fact("Checked", "every " + Duration.seconds(seconds).formatted(
                            .units(allowed: [.days, .hours, .minutes, .seconds], width: .wide)))
                    }
                }

                if source.failed, let error = source.lastError {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                        if source.kind == "gitlab" && error.localizedCaseInsensitiveContains("token") {
                            Text("Store the token in the Keychain with `intel secret set \(source.settings?["token_env"] ?? "GITLAB_TOKEN")`.")
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }

                if let settings = source.settings, !settings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings").font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                            ForEach(settings.sorted { $0.key < $1.key }, id: \.key) { key, value in
                                Fact(Self.settingNames[key] ?? key, value)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func Fact(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

// MARK: - Adding a source

private struct AddSourceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let added: (SourceStatus, _ syncNow: Bool) async -> Void

    @State private var kind = "filesystem"
    @State private var name = ""
    @State private var path = ""
    @State private var include = ""
    @State private var includeDocuments = true
    @State private var url = ""
    @State private var projects = ""
    @State private var groups = ""
    @State private var tokenEnv = "GITLAB_TOKEN"
    @State private var verifyTls = true
    @State private var syncNow = true
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a source").font(.headline)
            Picker("Kind", selection: $kind) {
                Text("Folder of notes").tag("filesystem")
                Text("Git repository").tag("git")
                Text("GitLab").tag("gitlab")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(Explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Form {
                TextField("Name", text: $name, prompt: Text(kind == "gitlab" ? "gitlab" : "a short name, e.g. notes"))
                if kind == "gitlab" {
                    TextField("GitLab URL", text: $url, prompt: Text("https://git.example.com"))
                    TextField("Projects", text: $projects, prompt: Text("group/project, … (comma-separated)"))
                    TextField("Groups", text: $groups, prompt: Text("groups or user names, … (comma-separated)"))
                    TextField("Token variable", text: $tokenEnv)
                        .help("intel reads the access token from this environment variable, or from the Keychain item of that name (intel secret set)")
                    Toggle("Verify the TLS certificate", isOn: $verifyTls)
                        .help("Turn off for a self-signed certificate")
                } else {
                    LabeledContent(kind == "git" ? "Repository" : "Folder") {
                        HStack {
                            TextField("Path", text: $path, prompt: Text(kind == "git" ? "~/git/project" : "~/Notes"))
                                .labelsHidden()
                            Button("Choose…", action: ChooseFolder)
                        }
                    }
                    if kind == "git" {
                        Toggle("Also read its Markdown and text files", isOn: $includeDocuments)
                    }
                    if kind == "filesystem" || includeDocuments {
                        TextField(kind == "git" ? "Documents" : "Files", text: $include,
                                  prompt: Text("*.md, *.txt, … (blank: the usual note files)"))
                    }
                }
                Toggle("Sync it now", isOn: $syncNow)
                    .help("Otherwise the background service syncs it at its next cycle")
            }

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add", action: Add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!CanAdd || isWorking)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onChange(of: kind) { failure = nil }
    }

    private var Explanation: String {
        switch kind {
        case "git":
            "A local clone: its commits, and its notes and README. Repositories under the git roots in intel's config are added on their own."
        case "gitlab":
            "The issues of GitLab projects and groups. intel reads the access token from the variable below, or from the Keychain (intel secret set GITLAB_TOKEN)."
        default:
            "Markdown and text notes in a folder and its subfolders. Tasks written in them show up under Tasks."
        }
    }

    private var CanAdd: Bool {
        guard !Trimmed(name).isEmpty else { return false }
        return kind == "gitlab" ? !Trimmed(url).isEmpty && !(Split(projects) + Split(groups)).isEmpty
                                : !Trimmed(path).isEmpty
    }

    private func ChooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        path = folder.path
        if Trimmed(name).isEmpty { name = folder.lastPathComponent }
    }

    private func Add() {
        let gitlab = kind == "gitlab"
        let source = NewSource(kind: kind, name: Trimmed(name), path: gitlab ? nil : Trimmed(path),
                               include: gitlab ? [] : Split(include), includeDocuments: includeDocuments,
                               url: gitlab ? Trimmed(url) : nil, projects: gitlab ? Split(projects) : [],
                               groups: gitlab ? Split(groups) : [], tokenEnv: gitlab ? Trimmed(tokenEnv) : nil,
                               verifyTls: verifyTls)
        isWorking = true
        failure = nil
        Task {
            defer { isWorking = false }
            guard let result = await model.Submit({ try await $0.AddSource(source) }, failed: { failure = $0 }) else { return }
            dismiss()
            await added(result, syncNow)
        }
    }

    private func Trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "a, b,,c" -> ["a", "b", "c"]
    private func Split(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0.isNewline }).map { Trimmed(String($0)) }.filter { !$0.isEmpty }
    }
}
