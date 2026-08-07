import Foundation
import XCTest
@testable import BessieCore

final class AgentIntentRegistryTests: XCTestCase {
    func testPilotCatalogRoundTripsWithoutLosingSchemaMetadata() throws {
        let catalog = BessieIntentRegistry.catalog

        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(BessieIntentCatalog.self, from: data)

        XCTAssertEqual(decoded, catalog)
        XCTAssertEqual(catalog.version, 2)
    }

    func testPilotIntentNamesAreCompleteUniqueAndMCPCompatible() throws {
        let intents = BessieIntentRegistry.catalog.intents
        let expected: Set<String> = [
            "intents.list",
            "app.status",
            "connection.status",
            "connection.context",
            "session.projection",
            "pane.focus",
            "workspace.focus",
            "workspace.close",
            "project.list",
            "project.show",
        ]

        XCTAssertEqual(Set(intents.map(\.id.rawValue)), expected)
        XCTAssertEqual(Set(intents.map(\.id)).count, intents.count)

        let pattern = try NSRegularExpression(pattern: "^[A-Za-z0-9_.-]+$")
        for intent in intents {
            let range = NSRange(intent.id.rawValue.startIndex..., in: intent.id.rawValue)
            XCTAssertNotNil(pattern.firstMatch(in: intent.id.rawValue, range: range), intent.id.rawValue)
        }
    }

    func testEveryPilotIntentExportsRequiredAgentMetadata() {
        for intent in BessieIntentRegistry.catalog.intents {
            XCTAssertFalse(intent.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertEqual(intent.paramsSchema.type, .object)
            XCTAssertNotNil(intent.paramsSchema.additionalProperties)
            if intent.risk == .destructive {
                XCTAssertFalse(intent.confirmation?.isEmpty ?? true)
            }
        }

        let close = BessieIntentRegistry.definition(for: "workspace.close")
        XCTAssertEqual(close?.owner, .herdr)
        XCTAssertEqual(close?.risk, .destructive)
        XCTAssertEqual(close?.requiresLiveConnection, true)
        XCTAssertEqual(close?.paramsSchema.required, ["connection_id", "workspace_id"])

        let projectShow = BessieIntentRegistry.definition(for: "project.show")
        XCTAssertEqual(projectShow?.owner, .bessie)
        XCTAssertEqual(projectShow?.risk, .read)
        XCTAssertEqual(projectShow?.offlineOK, true)
        XCTAssertEqual(projectShow?.paramsSchema.required, ["project_id"])

        let connectionContext = BessieIntentRegistry.definition(for: "connection.context")
        XCTAssertEqual(connectionContext?.owner, .bessie)
        XCTAssertEqual(connectionContext?.risk, .read)
        XCTAssertEqual(connectionContext?.requiresLiveConnection, false)
        XCTAssertEqual(connectionContext?.paramsSchema.required, [])
    }

    func testSchemaExportUsesJSONSchemaFieldNames() throws {
        let intent = try XCTUnwrap(BessieIntentRegistry.definition(for: "pane.focus"))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any])
        let schema = try XCTUnwrap(object["params_schema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])

        XCTAssertEqual(object["id"] as? String, "pane.focus")
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertEqual(Set(properties.keys), ["connection_id", "pane_id"])
        XCTAssertEqual(schema["required"] as? [String], ["connection_id", "pane_id"])
    }
}
