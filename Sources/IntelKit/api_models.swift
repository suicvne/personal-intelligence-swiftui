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
    public let lastRun: String?
    public let lastError: String?
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

public struct AnswerView: Codable, Sendable {
    public let question: String
    public let mode: String
    public let text: String
    public let evidence: [CitedStatement]
    public let inferences: [CitedStatement]
    public let gaps: [String]
    public let references: [ReferenceView]
    public let ambiguous: [String: [String]]
    public let invalidRefs: [String]
    public let note: String?
}
