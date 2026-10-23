// State shared by every screen: the connection, the latest status, and a refresh signal.

import Foundation
import IntelKit
import Observation

@MainActor
@Observable
final class AppModel {
    var settings: ConnectionSettings
    var status: StatusView?
    /// The last problem talking to intel, shown in a banner until the next success.
    var problem: String?
    var isSyncing = false
    var lastSyncLines: [String] = []
    /// Screens reload whenever this changes (⌘R, after syncing, after saving settings).
    private(set) var refreshToken = 0

    init() {
        settings = ConnectionSettings.Load()
    }

    var client: IntelClient { IntelClient(baseURL: settings.serverURL, token: settings.token) }

    func RequestRefresh() {
        refreshToken += 1
    }

    /// Run an API call, recording failures in `problem`. Returns nil when it failed.
    func Run<Result: Sendable>(_ call: (IntelClient) async throws -> Result) async -> Result? {
        do {
            let result = try await call(client)
            problem = nil
            return result
        } catch {
            problem = error.localizedDescription
            return nil
        }
    }

    func LoadStatus() async {
        if let status = await Run({ try await $0.Status() }) {
            self.status = status
        }
    }

    func SyncNow() async {
        isSyncing = true
        defer { isSyncing = false }
        if let result = await Run({ try await $0.Sync() }) {
            lastSyncLines = result.lines
            RequestRefresh()
        }
    }

    func Save(_ newSettings: ConnectionSettings) throws {
        try newSettings.Save()
        settings = newSettings
        problem = nil
        RequestRefresh()
    }
}
