// The JSON the intel API sends, as Swift values.
//
// These mirror the Pydantic models in personal-intelligence/src/intel/api.py. JSON keys are
// snake_case and decoded with .convertFromSnakeCase, so `created_at` arrives as `createdAt`.
// Tests/IntelKitTests decodes a real sample of every response to keep the two sides in step.

import Foundation

// MARK: - Status and sync

public struct HealthView: Codable, Sendable {
    public let ok: Bool
    public let version: String
}

public struct SourceStatus: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let kind: String
    public let enabled: Bool
    public let discovered: Bool
    public let location: String?
    public let records: Int
    public let lastSuccessAt: String?
    /// "succeeded", "failed", "running" or "interrupted"; nil before the first sync.
    public let lastRun: String?
    public let lastError: String?
    /// The git root or notes folder it was discovered in (nil when added by hand, or from an older intel).
    public let discoveredFrom: String?
    /// How often the background service syncs it.
    public let pollIntervalSeconds: Int?
    /// What else was set: include patterns, projects, groups… (nil from an older intel).
    public let settings: [String: String]?

    public var failed: Bool { lastRun == "failed" }
}

/// A source to add (POST /api/sources). `kind` is "filesystem" (a folder of notes), "git" (a local repository)
/// or "gitlab"; only the fields for that kind are used.
public struct NewSource: Encodable, Sendable {
    public var kind: String
    public var name: String
    public var path: String?
    /// Filename patterns to read ("*.md"); empty: intel's defaults.
    public var include: [String]
    /// git: also read the repository's Markdown and text files.
    public var includeDocuments: Bool
    public var url: String?
    public var projects: [String]
    public var groups: [String]
    /// gitlab: the environment variable (or Keychain item, `intel secret set`) that holds the access token.
    public var tokenEnv: String?
    public var verifyTls: Bool

    public init(kind: String, name: String, path: String? = nil, include: [String] = [], includeDocuments: Bool = true,
                url: String? = nil, projects: [String] = [], groups: [String] = [], tokenEnv: String? = nil,
                verifyTls: Bool = true) {
        self.kind = kind
        self.name = name
        self.path = path
        self.include = include
        self.includeDocuments = includeDocuments
        self.url = url
        self.projects = projects
        self.groups = groups
        self.tokenEnv = tokenEnv
        self.verifyTls = verifyTls
    }
}

public struct StatusView: Codable, Sendable {
    public let version: String
    public let database: String
    public let llm: String
    public let sources: [SourceStatus]
    public let entityCounts: [String: Int]
    public let pendingProposals: Int
    /// Every open observation, including ones already seen.
    public let openObservations: Int
    /// What the Brief would show right now: the Brief badge.
    public let needsAttention: Int
    public let openTasks: Int
    public let queue: [String: Int]
    public let lastObservedAt: String?
}

public struct SyncResult: Codable, Sendable {
    public let lines: [String]
    public let events: Int
    public let entitiesCreated: Int
    public let queued: Int
}

// MARK: - LLM model

public struct LlmModelsView: Codable, Sendable {
    public let enabled: Bool
    public let baseUrl: String?
    /// `[llm] model` in intel's config file.
    public let configured: String?
    /// Picked here or with `intel llm use`; overrides `configured`.
    public let chosen: String?
    /// The model in use: `chosen`, else `configured`.
    public let current: String?
    /// What the endpoint offers.
    public let available: [String]
    /// Why `available` is empty: the endpoint couldn't be asked.
    public let error: String?
}

// MARK: - Evidence and observations

public struct EvidenceView: Codable, Sendable, Hashable {
    public let recordId: Int?
    public let source: String?
    public let kind: String?
    public let title: String?
    public let location: String?
    public let uri: String?
    public let excerpt: String?
    public let context: String?
    public let note: String?
    public let stale: Bool
    public let model: String?
}

public struct ObservationView: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let category: String
    public let summary: String
    public let explanation: String
    public let confidence: Double
    public let priority: Int
    public let status: String
    public let createdAt: String
    public let reason: String?
    public let entities: [String]
    public let evidence: [EvidenceView]
}

public struct BriefView: Codable, Sendable {
    public let createdAt: String
    public let windowStart: String?
    public let observations: [ObservationView]
    public let activity: [String]
    public let knowledgeChanges: [String]
    public let pendingProposals: Int
    public let ambiguousMentions: Int
    public let failedWork: Int
    public let text: String
}

// MARK: - Activity

public struct EventView: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    /// "source": a change in a monitored source; "semantic": a change in what intel knows.
    public let layer: String
    /// commit.added, document.modified, entity.renamed, …
    public let type: String
    public let summary: String
    /// When it happened (in the source, when known), else when intel recorded it.
    public let at: String
    /// Source events: where it happened.
    public let source: String?
    public let recordId: Int?
    /// A file path or web URL to open.
    public let uri: String?
    /// Semantic events: what it is about.
    public let entityId: Int?
    public let entity: String?
    public let entityType: String?
    /// Semantic events: who changed it ("user", "llm", "rule", "source").
    public let origin: String?
}

public struct EventPage: Codable, Sendable {
    public let events: [EventView]
    /// Pass as `before` for the next page; nil on the last page.
    public let nextBefore: Int?
}

// MARK: - Proposals

public struct ProposalView: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let kind: String
    public let origin: String
    public let status: String
    public let summary: String
    public let source: String
    public let group: String
    public let confidence: Double?
    public let createdAt: String
}

public struct ProposalGroupView: Codable, Sendable, Identifiable, Hashable {
    public let name: String
    public let sources: Int
    public let kinds: [String: Int]
    public let proposals: [ProposalView]

    public var id: String { name }

    public init(name: String, sources: Int, kinds: [String: Int], proposals: [ProposalView]) {
        self.name = name
        self.sources = sources
        self.kinds = kinds
        self.proposals = proposals
    }
}

public struct ProposalOverview: Codable, Sendable {
    public let total: Int
    public let groups: [ProposalGroupView]
    public let predicates: [String]
}

public struct ProposalDetail: Codable, Sendable {
    public let proposal: ProposalView
    public let rationale: String?
    public let decisionNote: String?
    /// Current values of the fields that may be corrected before approving.
    public let fields: [String: String]
    public let evidence: [EvidenceView]
}

public struct DecisionResult: Codable, Sendable {
    public let proposal: ProposalView
    public let alsoApproved: [ProposalView]
    public let createdIssueUrl: String?
}

public struct GroupDecisionResult: Codable, Sendable {
    public let decision: String
    public let decided: Int
    public let groups: [String]
}

// MARK: - Tasks

public struct TaskView: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let text: String
    public let state: String
    public let location: String
    public let notePath: String?
    public let line: Int
    public let section: String?
    public let backlog: Bool
    public let trackedAs: String?
    public let issueUrl: String?
    public let recordId: Int
}

public struct ImportResult: Codable, Sendable {
    public let note: String
    public let proposed: Int
    public let unplaced: Int
}

// MARK: - Entities

public struct EntitySummary: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let type: String
    public let name: String
    public let status: String
    public let otherNames: [String]
}

public struct NameView: Codable, Sendable, Hashable {
    public let name: String
    public let kind: String
    public let origin: String
    public let until: String?
}

public struct RelationshipView: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let subjectId: Int
    public let subject: String
    public let predicate: String
    public let objectId: Int
    public let object: String
    public let status: String
    public let origin: String
    public let confidence: Double?
}

/// A relationship predicate (USES, PART_OF, …) and what it means.
public struct PredicateView: Codable, Sendable, Identifiable, Hashable {
    public let name: String
    public let meaning: String

    public var id: String { name }

    public init(name: String, meaning: String) {
        self.name = name
        self.meaning = meaning
    }
}

public struct ActivityView: Codable, Sendable, Hashable {
    public let at: String
    public let kind: String
    public let title: String?
    public let source: String
    public let recordId: Int
}

public struct EntityDetail: Codable, Sendable {
    public let entity: EntitySummary
    public let description: String?
    public let statusNote: String?
    public let names: [NameView]
    public let identifiers: [String: String]
    public let properties: [[String: String]]
    public let relationships: [RelationshipView]
    public let activity: [ActivityView]
    public let observations: [ObservationView]
    public let decision: String?
    public let goal: String?
}

// MARK: - Ask

public struct CitedStatement: Codable, Sendable, Hashable {
    public let statement: String
    public let refs: [String]
}

public struct ReferenceView: Codable, Sendable, Identifiable, Hashable {
    public let ref: String
    public let kind: String
    public let label: String
    public let recordId: Int?
    public let entityId: Int?
    public let uri: String?

    public var id: String { ref }
}

/// One lookup the model made before answering.
public struct LookupView: Codable, Sendable, Hashable {
    /// The call and what it found: "search_records(since=2026-10-24, until=2026-10-24): 11 records".
    public let text: String
    /// What was looked up, in words: "records changed on 2026-10-24" (`text` from an intel that doesn't say).
    public let description: String
    /// What it found: "11 records", or the reference it was given ("R13"); nil from an intel that doesn't say.
    public let result: String?

    public init(text: String, description: String, result: String?) {
        self.text = text
        self.description = description
        self.result = result
    }

    public init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {    // an intel from before descriptions
            self.init(text: text, description: text, result: nil)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .text)
        self.init(text: text, description: try container.decodeIfPresent(String.self, forKey: .description) ?? text,
                  result: try container.decodeIfPresent(String.self, forKey: .result))
    }
}

public struct AnswerView: Codable, Sendable {
    public let question: String
    public let mode: String
    public let text: String
    /// `text` without its citations, for reading aloud (nil from an intel that can't read aloud yet).
    public let spokenText: String?
    public let evidence: [CitedStatement]
    public let inferences: [CitedStatement]
    public let gaps: [String]
    public let references: [ReferenceView]
    public let ambiguous: [String: [String]]
    public let invalidRefs: [String]
    public let note: String?
    /// What the model looked up before answering (nil from an intel that can't look things up).
    public let lookups: [LookupView]?
}

// MARK: - Personas

public struct PersonaView: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    /// How the answer text is written; "" means plainly.
    public let style: String
    /// What the voice sounds like when answers are read aloud; "" means `PersonasView.configuredVoice`.
    public let voice: String
}

public struct PersonasView: Codable, Sendable {
    public let personas: [PersonaView]
    /// The persona in use; nil means the style and voice in intel's config.
    public let chosen: Int?
    /// `[ask] persona` in intel's config.
    public let configuredStyle: String
    /// `[voice] instruct` in intel's config.
    public let configuredVoice: String
}
