// The window: a sidebar of screens with counts, the selected screen, and a status footer.

import IntelKit
import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case brief = "Brief"
    case proposals = "Proposals"
    case tasks = "Tasks"
    case entities = "Entities"
    case ask = "Ask"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .brief: "sun.horizon"
        case .proposals: "checklist"
        case .tasks: "square.and.pencil"
        case .entities: "circle.hexagongrid"
        case .ask: "questionmark.bubble"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var screen: Screen? = .brief
    @State private var showingSettings = false

    @State private var showingSidebar = true

    // Layout: one title bar across the whole window, with the sidebar and the screen both below it,
    // so sidebar rows and content start on the same line. (NavigationSplitView runs the sidebar up
    // through the title bar instead.)
    var body: some View {
        HSplitView {
            if showingSidebar {
                List(Screen.allCases, selection: $screen) { screen in
                    Label(screen.rawValue, systemImage: screen.symbol)
                        .badge(Count(for: screen))
                        .tag(screen)
                }
                .listStyle(.sidebar)
                .safeAreaInset(edge: .bottom) { StatusFooter() }
                .frame(minWidth: 170, idealWidth: 190, maxWidth: 280)
            }
            Group {
                switch screen ?? .brief {
                case .brief: BriefScreen()
                case .proposals: ProposalsScreen()
                case .tasks: TasksScreen()
                case .entities: EntitiesScreen()
                case .ask: AskScreen()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let problem = model.problem {
                    ProblemBanner(message: problem) { showingSettings = true }
                }
            }
            .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { withAnimation { showingSidebar.toggle() } } label: {
                    Label("Sidebar", systemImage: "sidebar.left")
                }
                .help(showingSidebar ? "Hide the sidebar" : "Show the sidebar")
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.RequestRefresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .help("Reload (⌘R)")
                Button { Task { await model.SyncNow() } } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Sync every source now (⇧⌘S)")
                .disabled(model.isSyncing)
            }
        }
        .task(id: model.refreshToken) { await model.LoadStatus() }
        .sheet(isPresented: $showingSettings) {
            SettingsView().environment(model).padding().frame(width: 520)
        }
        .onAppear { showingSettings = !model.settings.IsComplete }
        .task {
            if let directory = DebugSnapshot.Directory {
                await DebugSnapshot.CaptureAllScreens(select: { screen = $0 }, into: directory)
            }
        }
    }

    private func Count(for screen: Screen) -> Int {
        guard let status = model.status else { return 0 }
        switch screen {
        case .brief: return status.needsAttention
        case .proposals: return status.pendingProposals
        case .tasks: return status.openTasks
        case .entities, .ask: return 0
        }
    }
}

private struct StatusFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            if model.isSyncing {
                ProgressView("Syncing…").controlSize(.small)
            } else if let status = model.status {
                let newest = status.sources.compactMap(\.lastSuccessAt).max()
                Text("Synced \(Formatting.RelativeAge(newest))")
                Text("\(status.sources.filter(\.enabled).count) sources · \(status.llm)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not connected").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private struct ProblemBanner: View {
    let message: String
    let openSettings: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).textSelection(.enabled)
            Spacer()
            Button("Settings…", action: openSettings)
        }
        .padding(10)
        .background(.orange.opacity(0.12))
    }
}
