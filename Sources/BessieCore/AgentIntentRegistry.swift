import Foundation

public struct BessieIntentID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum BessieIntentOwner: String, Codable, Equatable, Sendable {
    case bessie
    case herdr
}

public enum BessieIntentRisk: String, Codable, Equatable, Sendable {
    case read
    case navigate
    case mutate
    case destructive
}

public enum BessieJSONSchemaType: String, Codable, Equatable, Sendable {
    case object
    case string
    case number
    case integer
    case boolean
    case array
}

public struct BessieJSONSchema: Codable, Equatable, Sendable {
    public let type: BessieJSONSchemaType
    public let description: String?
    public let properties: [String: BessieJSONSchema]?
    public let required: [String]?
    public let additionalProperties: Bool?

    public init(
        type: BessieJSONSchemaType,
        description: String? = nil,
        properties: [String: BessieJSONSchema]? = nil,
        required: [String]? = nil,
        additionalProperties: Bool? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }

    public static func object(
        properties: [String: BessieJSONSchema] = [:],
        required: [String] = []
    ) -> BessieJSONSchema {
        BessieJSONSchema(
            type: .object,
            properties: properties,
            required: required,
            additionalProperties: false
        )
    }

    public static func string(_ description: String) -> BessieJSONSchema {
        BessieJSONSchema(type: .string, description: description)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case description
        case properties
        case required
        case additionalProperties
    }
}

public struct BessieIntentDefinition: Codable, Equatable, Sendable {
    public let id: BessieIntentID
    public let description: String
    public let owner: BessieIntentOwner
    public let risk: BessieIntentRisk
    public let requiresLiveConnection: Bool
    public let offlineOK: Bool
    public let paramsSchema: BessieJSONSchema
    public let confirmation: String?

    public init(
        id: BessieIntentID,
        description: String,
        owner: BessieIntentOwner,
        risk: BessieIntentRisk,
        requiresLiveConnection: Bool,
        offlineOK: Bool = false,
        paramsSchema: BessieJSONSchema,
        confirmation: String? = nil
    ) {
        self.id = id
        self.description = description
        self.owner = owner
        self.risk = risk
        self.requiresLiveConnection = requiresLiveConnection
        self.offlineOK = offlineOK
        self.paramsSchema = paramsSchema
        self.confirmation = confirmation
    }

    enum CodingKeys: String, CodingKey {
        case id
        case description
        case owner
        case risk
        case requiresLiveConnection = "requires_live_connection"
        case offlineOK = "offline_ok"
        case paramsSchema = "params_schema"
        case confirmation
    }
}

public struct BessieIntentCatalog: Codable, Equatable, Sendable {
    public let version: Int
    public let intents: [BessieIntentDefinition]

    public init(version: Int, intents: [BessieIntentDefinition]) {
        self.version = version
        self.intents = intents
    }
}

public enum BessieIntentRegistry {
    public static let catalog = BessieIntentCatalog(version: 2, intents: [
        intent(
            "intents.list",
            "List the effective Bessie intent catalog and parameter schemas.",
            owner: .bessie,
            risk: .read,
            offlineOK: true
        ),
        intent(
            "app.status",
            "Report Bessie app and intent bus status.",
            owner: .bessie,
            risk: .read
        ),
        intent(
            "connection.status",
            "Report current Herdr connection status, optionally for one connection.",
            owner: .bessie,
            risk: .read,
            properties: [
                "connection_id": .string("Bessie connection identifier."),
            ]
        ),
        intent(
            "connection.context",
            "List configured Bessie herds with enabled, selected, default Project target, and live state; optionally filter by connection ID.",
            owner: .bessie,
            risk: .read,
            properties: [
                "connection_id": .string("Optional configured Bessie connection identifier."),
            ]
        ),
        intent(
            "session.projection",
            "Read Bessie's current projection of a Herdr session.",
            owner: .herdr,
            risk: .read,
            requiresLiveConnection: true,
            properties: connectionProperties(),
            required: ["connection_id"]
        ),
        intent(
            "pane.focus",
            "Focus an explicit Herdr pane on a connection.",
            owner: .herdr,
            risk: .navigate,
            requiresLiveConnection: true,
            properties: connectionProperties([
                "pane_id": .string("Herdr pane identifier scoped to the connection."),
            ]),
            required: ["connection_id", "pane_id"]
        ),
        intent(
            "workspace.focus",
            "Focus an explicit Herdr workspace on a connection.",
            owner: .herdr,
            risk: .navigate,
            requiresLiveConnection: true,
            properties: connectionProperties([
                "workspace_id": .string("Herdr workspace identifier scoped to the connection."),
            ]),
            required: ["connection_id", "workspace_id"]
        ),
        intent(
            "workspace.close",
            "Close a Herdr workspace and stop its pane processes after confirmation.",
            owner: .herdr,
            risk: .destructive,
            requiresLiveConnection: true,
            confirmation: "Requires a one-shot token from a needs_confirmation response.",
            properties: connectionProperties([
                "workspace_id": .string("Herdr workspace identifier scoped to the connection."),
            ]),
            required: ["connection_id", "workspace_id"]
        ),
        intent(
            "project.list",
            "List Bessie-owned Project recipes.",
            owner: .bessie,
            risk: .read,
            offlineOK: true
        ),
        intent(
            "project.show",
            "Read one Bessie-owned Project recipe.",
            owner: .bessie,
            risk: .read,
            offlineOK: true,
            properties: [
                "project_id": .string("Bessie Project UUID."),
            ],
            required: ["project_id"]
        ),
    ])

    public static func definition(for id: BessieIntentID) -> BessieIntentDefinition? {
        catalog.intents.first { $0.id == id }
    }

    public static func definition(for id: String) -> BessieIntentDefinition? {
        definition(for: BessieIntentID(id))
    }

    private static func intent(
        _ id: String,
        _ description: String,
        owner: BessieIntentOwner,
        risk: BessieIntentRisk,
        requiresLiveConnection: Bool = false,
        offlineOK: Bool = false,
        confirmation: String? = nil,
        properties: [String: BessieJSONSchema] = [:],
        required: [String] = []
    ) -> BessieIntentDefinition {
        BessieIntentDefinition(
            id: BessieIntentID(id),
            description: description,
            owner: owner,
            risk: risk,
            requiresLiveConnection: requiresLiveConnection,
            offlineOK: offlineOK,
            paramsSchema: .object(properties: properties, required: required),
            confirmation: confirmation
        )
    }

    private static func connectionProperties(
        _ additional: [String: BessieJSONSchema] = [:]
    ) -> [String: BessieJSONSchema] {
        var properties = additional
        properties["connection_id"] = .string("Bessie connection identifier.")
        return properties
    }
}
