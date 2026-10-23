// Optional: decode every read-only endpoint of a running intel against its real data.
// Skipped unless INTEL_LIVE_TOKEN is set (INTEL_LIVE_URL defaults to http://127.0.0.1:8765):
//
//   INTEL_LIVE_TOKEN=$(intel api token) swift test --filter Live

import Foundation
import Testing
@testable import IntelKit

private let environment = ProcessInfo.processInfo.environment

private func LiveClient() -> IntelClient {
    let url = environment["INTEL_LIVE_URL"].flatMap(URL.init(string:)) ?? ConnectionSettings.defaultServer
    return IntelClient(baseURL: url, token: environment["INTEL_LIVE_TOKEN"] ?? "")
}

@Test(.enabled(if: environment["INTEL_LIVE_TOKEN"] != nil))
func LiveEndpointsDecode() async throws {
    let client = LiveClient()
    let status = try await client.Status()
    _ = try await client.Brief()
    _ = try await client.Observations(includeClosed: true)
    let overview = try await client.Proposals()
    if let first = overview.groups.first?.proposals.first {
        _ = try await client.Proposal(id: first.id)
        _ = try await client.PreviewGroup(overview.groups[0].name)
    }
    _ = try await client.Tasks(includeClosed: true)
    for type in ["project", "component", "repository"] {
        if let entity = try await client.Entities(type: type).first {
            _ = try await client.Entity(reference: String(entity.id))
        }
    }
    #expect(!status.sources.isEmpty)
}
