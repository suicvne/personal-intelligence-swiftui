// The app: one window with eight screens, plus Settings (⌘,).

import AppKit
import IntelKit
import SwiftUI

@main
struct IntelApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Intel") {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
                .onAppear {
                    // Needed when launched with `swift run` (no app bundle) so the window comes to the front.
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate()
                }
        }
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") { model.RequestRefresh() }
                    .keyboardShortcut("r")
                Button("Sync Now") { Task { await model.SyncNow() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
