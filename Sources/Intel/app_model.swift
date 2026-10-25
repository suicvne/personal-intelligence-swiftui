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

    /// Run an API call, recording failures in `problem`. Returns nil when it failed or was cancelled.
    func Run<Result: Sendable>(_ call: (IntelClient) async throws -> Result) async -> Result? {
        do {
            let result = try await call(client)
            problem = nil
            return result
        } catch is CancellationError {
            return nil
        } catch {
            problem = error.localizedDescription
            return nil
        }
    }

    /// Like `Run`, for a form: why it failed goes to `failed`, to show next to the form. Only a failure to talk
    /// to intel also becomes `problem`; intel refusing the form's values ("There is no folder at …") doesn't.
    func Submit<Result: Sendable>(_ call: (IntelClient) async throws -> Result,
                                  failed: (String) -> Void) async -> Result? {
        do {
            let result = try await call(client)
            problem = nil
            return result
        } catch is CancellationError {
            return nil
        } catch IntelError.server(let status, let message) where (400..<500).contains(status) && status != 401 {
            failed(message)
            return nil
        } catch {
            problem = error.localizedDescription
            failed(error.localizedDescription)
            return nil
        }
    }

    /// Go through a stream of API events as they arrive, recording a failure in `problem` like `Run`.
    func Follow<Event: Sendable>(_ events: AsyncThrowingStream<Event, Error>, _ handle: (Event) -> Void) async {
        do {
            for try await event in events { handle(event) }
            if !Task.isCancelled { problem = nil }
        } catch is CancellationError {
        } catch {
            problem = error.localizedDescription
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
