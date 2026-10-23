// A small async client for the intel HTTP API (personal-intelligence/src/intel/server.py).
//
// One method per route. Every call sends `Authorization: Bearer <token>`; errors come back as
// IntelError with the server's message, so views can show them as they are. A streaming route
// returns its events as an AsyncThrowingStream; ending the iteration closes the connection.

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

    /// A 404 from an intel older than the app: its service runs the old code until it restarts.
    static func Outdated(_ ability: String) -> IntelError {
        .server(status: 404, message: "This intel can't \(ability) yet. Restart its background service.")
    }
}

/// What /api/ask/stream sends: pieces of the answer text while the model writes it, then the answer.
public enum AskEvent: Sendable {
    case delta(String)
    /// The whole answer text, as soon as the model has written it (while it still writes the evidence):
    /// early enough to start reading it aloud. `spokenText` is the text without its citations.
    case answerText(text: String, spokenText: String)
    /// The final answer. Its `text` replaces the streamed text (they are usually the same; not when the
    /// model's reply had to be repaired or the model went away mid-answer).
    case answer(AnswerView)
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

    /// Ask, with the answer text streamed while the model writes it. Stopping the iteration (or cancelling
    /// its task) also stops the model writing.
    public func AskStream(question: String, useLlm: Bool = true) -> AsyncThrowingStream<AskEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await StreamAnswer(question: question, useLlm: useLlm, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The model intel uses and the models its endpoint offers.
    public func LlmModels() async throws -> LlmModelsView { try await Get("/api/llm/models") }

    /// Use `model` for every LLM task from now on; nil goes back to the model in intel's config.
    public func ChooseLlmModel(_ model: String?) async throws -> LlmModelsView {
        try await Post("/api/llm/model", body: ModelChoiceRequest(model: model))
    }

    /// `text` read aloud by intel's speech server (`[voice]` in intel's config), in the current persona's
    /// voice or the one `voice` describes (to try a voice before saving it). It arrives as one WAV stream
    /// in pieces, while the speech is still being generated; read them with WavStreamReader. Stopping the
    /// iteration (or cancelling its task) stops the speech being generated.
    public func SpeechStream(text: String, voice: String? = nil) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await StreamSpeech(text: text, voice: voice, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The personas, the one in use, and the style and voice in intel's config.
    public func Personas() async throws -> PersonasView {
        do {
            return try await Get("/api/personas")
        } catch IntelError.server(let status, _) where status == 404 {
            throw IntelError.Outdated("manage personas")
        }
    }

    public func AddPersona(name: String, style: String, voice: String) async throws -> PersonasView {
        try await Post("/api/personas", body: PersonaRequest(name: name, style: style, voice: voice))
    }

    public func UpdatePersona(id: Int, name: String, style: String, voice: String) async throws -> PersonasView {
        try await Post("/api/personas/\(id)", body: PersonaRequest(name: name, style: style, voice: voice))
    }

    public func DeletePersona(id: Int) async throws -> PersonasView {
        try await Post("/api/personas/\(id)/delete", body: EmptyBody())
    }

    /// Answer in this persona's style and voice from now on; nil goes back to those in intel's config.
    public func ChoosePersona(_ id: Int?) async throws -> PersonasView {
        try await Post("/api/personas/choose", body: PersonaChoiceRequest(id: id))
    }

    // MARK: Transport

    private func Get<Response: Decodable & Sendable>(_ path: String, query: [String: String] = [:]) async throws -> Response {
        try await Send(MakeRequest(path, query: query, method: "GET"))
    }

    private func Post<Body: Encodable, Response: Decodable & Sendable>(_ path: String, body: Body) async throws -> Response {
        try await Send(MakePost(path, body: body))
    }

    private func MakePost<Body: Encodable>(_ path: String, body: Body) throws -> URLRequest {
        var request = MakeRequest(path, query: [:], method: "POST")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
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
        guard (200..<300).contains(http.statusCode) else { throw ServerFailure(status: http.statusCode, body: data) }
        return try IntelClient.Decode(Response.self, from: data)
    }

    private func StreamAnswer(question: String, useLlm: Bool,
                              into continuation: AsyncThrowingStream<AskEvent, Error>.Continuation) async throws {
        let request = try MakePost("/api/ask/stream", body: AskRequest(question: question, useLlm: useLlm))
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw Unreachable(error)
        }
        guard let http = response as? HTTPURLResponse else { throw IntelError.invalidResponse }
        if http.statusCode == 404 {
            // An intel from before streaming (the service runs the old code until it restarts): ask plainly.
            continuation.yield(.answer(try await Ask(question: question, useLlm: useLlm)))
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw ServerFailure(status: http.statusCode, body: body)
        }

        var parser = ServerSentEventParser()
        var line: [UInt8] = []
        var answered = false
        func Handle(_ event: ServerSentEvent?) throws {
            guard let event, let decoded = try IntelClient.AskEventFrom(event) else { return }
            if case .answer = decoded { answered = true }
            continuation.yield(decoded)
        }
        do {
            // Split lines by hand: `bytes.lines` drops the blank lines that end each event.
            for try await byte in bytes {
                if byte == UInt8(ascii: "\n") {
                    if line.last == UInt8(ascii: "\r") { line.removeLast() }
                    try Handle(parser.Feed(String(decoding: line, as: UTF8.self)))
                    line.removeAll(keepingCapacity: true)
                } else {
                    line.append(byte)
                }
            }
        } catch let error as IntelError {
            throw error
        } catch {
            throw Unreachable(error)
        }
        try Handle(parser.Feed(String(decoding: line, as: UTF8.self)))
        try Handle(parser.Finish())
        if !answered {
            throw IntelError.unreachable("the connection closed before the answer was complete")
        }
    }

    private func StreamSpeech(text: String, voice: String?,
                              into continuation: AsyncThrowingStream<Data, Error>.Continuation) async throws {
        let request = try MakePost("/api/speak/stream", body: SpeechRequest(text: text, voice: voice))
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw Unreachable(error)
        }
        guard let http = response as? HTTPURLResponse else { throw IntelError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 { throw IntelError.Outdated("read aloud while it generates speech") }
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw ServerFailure(status: http.statusCode, body: body)
        }
        var piece = Data()
        do {
            for try await byte in bytes {        // passed on in pieces of about a fifth of a second
                piece.append(byte)
                if piece.count >= 9_600 {
                    continuation.yield(piece)
                    piece = Data()
                }
            }
        } catch {
            throw Unreachable(error)
        }
        if !piece.isEmpty { continuation.yield(piece) }
    }

    /// One /api/ask/stream event; nil for an event this app doesn't know.
    static func AskEventFrom(_ event: ServerSentEvent) throws -> AskEvent? {
        let data = Data(event.data.utf8)
        switch event.name {
        case "delta":
            return .delta(try Decode(TextPiece.self, from: data).text)
        case "answer_text":
            let piece = try Decode(AnswerTextPiece.self, from: data)
            return .answerText(text: piece.text, spokenText: piece.spokenText)
        case "answer":
            return .answer(try Decode(AnswerView.self, from: data))
        case "error":
            let failure = try Decode(StreamFailure.self, from: data)
            throw IntelError.server(status: failure.status ?? 500, message: failure.error)
        default:
            return nil
        }
    }

    private static func Decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do {
            return try IntelClient.Decoder().decode(Response.self, from: data)
        } catch {
            throw IntelError.invalidResponse
        }
    }

    private func ServerFailure(status: Int, body: Data) -> IntelError {
        let message = (try? JSONDecoder().decode(ServerError.self, from: body))?.error ?? "HTTP \(status)"
        return IntelError.server(status: status, message: message)
    }

    /// A transport failure as the error to report; cancelling is not a failure.
    private func Unreachable(_ error: Error) -> Error {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return CancellationError() }
        return IntelError.unreachable(error.localizedDescription)
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

private struct TextPiece: Decodable {
    let text: String
}

private struct AnswerTextPiece: Decodable {
    let text: String
    let spokenText: String
}

private struct StreamFailure: Decodable {
    let error: String
    let status: Int?
}

private struct SpeechRequest: Encodable {
    let text: String
    let voice: String?
}

private struct PersonaRequest: Encodable {
    let name: String
    let style: String
    let voice: String
}

private struct PersonaChoiceRequest: Encodable {
    let id: Int?            // nil leaves the key out, which intel reads as null
}

private struct ModelChoiceRequest: Encodable {
    let model: String?      // nil leaves the key out, which intel reads as null
}
