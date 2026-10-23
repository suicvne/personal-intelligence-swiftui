// A small async client for the intel HTTP API (personal-intelligence/src/intel/server.py).
//
// One method per route. Every call sends `Authorization: Bearer <token>`; errors come back as
// IntelError with the server's message, so views can show them as they are.

import Foundation

public enum IntelError: LocalizedError, Sendable {
    case server(status: Int, message: String)
    case unreachable(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .server(let status, let message):
            return status == 401 ? "The token was refused. Run `intel api token` and paste it in Settings." : message
        case .unreachable(let message):
            return "Can't reach intel: \(message). Is the background service running? (intel service status)"
        case .invalidResponse:
            return "intel sent a response this app doesn't understand. Are the app and intel the same version?"
        }
    }
}

public struct IntelClient: Sendable {
    public let baseURL: URL
    public let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    // MARK: Routes

    public func Health() async throws -> HealthView { try await Get("/api/health") }
    public func Status() async throws -> StatusView { try await Get("/api/status") }
    public func Sync() async throws -> SyncResult { try await Post("/api/sync", body: EmptyBody()) }
    public func Brief() async throws -> BriefView { try await Get("/api/brief") }

    public func Observations(includeClosed: Bool = false) async throws -> [ObservationView] {
        try await Get("/api/observations", query: includeClosed ? ["all": "1"] : [:])
    }

    /// `action` is "ack", "dismiss" or "resolve".
    public func RespondToObservation(id: Int, action: String, note: String? = nil,
                                     unhelpful: Bool = false) async throws -> ObservationView {
        try await Post("/api/observations/\(id)/\(action)", body: ObservationResponseRequest(note: note, unhelpful: unhelpful))
    }

    public func Proposals(filter: String? = nil, status: String = "pending", kind: String? = nil) async throws -> ProposalOverview {
        try await Get("/api/proposals", query: ["filter": filter, "status": status, "kind": kind].compactMapValues { $0 })
    }

    public func Proposal(id: Int) async throws -> ProposalDetail { try await Get("/api/proposals/\(id)") }

    /// `decision` is "approve" or "reject". `edits` corrects the proposal before it is applied.
    public func Decide(id: Int, decision: String, note: String? = nil, rename: Bool = false,
                       edits: [String: String]? = nil) async throws -> DecisionResult {
        try await Post("/api/proposals/\(id)/\(decision)", body: DecisionRequest(note: note, rename: rename, edits: edits))
    }

    /// The proposals a group decision would affect: exactly the named `group`.
    public func PreviewGroup(_ group: String, kind: String? = nil) async throws -> [ProposalView] {
        try await Get("/api/proposals/group", query: ["group": group, "kind": kind].compactMapValues { $0 })
    }

    /// Approve or reject every pending proposal in a group (as named in ProposalOverview).
    public func DecideGroup(_ group: String, decision: String, kind: String? = nil,
                            note: String? = nil) async throws -> GroupDecisionResult {
        try await Post("/api/proposals/group", body: GroupDecisionRequest(group: group, decision: decision, kind: kind, note: note))
    }

    public func Tasks(includeClosed: Bool = false, note: String? = nil) async throws -> [TaskView] {
        var query: [String: String] = [:]
        if includeClosed { query["all"] = "1" }
        if let note { query["note"] = note }
        return try await Get("/api/tasks", query: query)
    }

    /// Propose GitLab issues for one note's open tasks. `note` may be "R<record id>".
    public func ImportTasks(note: String, project: String? = nil) async throws -> ImportResult {
        try await Post("/api/tasks/import", body: TaskImportRequest(note: note, project: project))
    }

    public func Entities(type: String? = nil) async throws -> [EntitySummary] {
        try await Get("/api/entities", query: ["type": type].compactMapValues { $0 })
    }

    /// `reference` is an id ("12"), a name, or a typed name ("repository:cascade").
    public func Entity(reference: String) async throws -> EntityDetail {
        let encoded = reference.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? reference
        return try await Get("/api/entities/\(encoded)")
    }

    public func Ask(question: String, useLlm: Bool = true) async throws -> AnswerView {
        try await Post("/api/ask", body: AskRequest(question: question, useLlm: useLlm))
    }

    /// The model intel uses and the models its endpoint offers.
    public func LlmModels() async throws -> LlmModelsView { try await Get("/api/llm/models") }

    /// Use `model` for every LLM task from now on; nil goes back to the model in intel's config.
    public func ChooseLlmModel(_ model: String?) async throws -> LlmModelsView {
        try await Post("/api/llm/model", body: ModelChoiceRequest(model: model))
    }

    // MARK: Transport

    private func Get<Response: Decodable & Sendable>(_ path: String, query: [String: String] = [:]) async throws -> Response {
        try await Send(MakeRequest(path, query: query, method: "GET"))
    }

    private func Post<Body: Encodable, Response: Decodable & Sendable>(_ path: String, body: Body) async throws -> Response {
        var request = MakeRequest(path, query: [:], method: "POST")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await Send(request)
    }

    private func MakeRequest(_ path: String, query: [String: String], method: String) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 120   // asking the model can take a while
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func Send<Response: Decodable & Sendable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw IntelError.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw IntelError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data))?.error ?? "HTTP \(http.statusCode)"
            throw IntelError.server(status: http.statusCode, message: message)
        }
        do {
            return try IntelClient.Decoder().decode(Response.self, from: data)
        } catch {
            throw IntelError.invalidResponse
        }
    }

    /// The decoder every response goes through (also used by the tests).
    public static func Decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

// MARK: - Request bodies

private struct EmptyBody: Encodable {}

private struct ServerError: Decodable {
    let error: String
}

private struct ObservationResponseRequest: Encodable {
    let note: String?
    let unhelpful: Bool
}

private struct DecisionRequest: Encodable {
    let note: String?
    let rename: Bool
    let edits: [String: String]?
}

private struct GroupDecisionRequest: Encodable {
    let group: String
    let decision: String
    let kind: String?
    let note: String?
}

private struct TaskImportRequest: Encodable {
    let note: String
    let project: String?
}

private struct AskRequest: Encodable {
    let question: String
    let useLlm: Bool
}

private struct ModelChoiceRequest: Encodable {
    let model: String?      // nil leaves the key out, which intel reads as null
}
