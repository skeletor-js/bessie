import Foundation

public struct BessieDragPayload: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case workspace
        case tab
    }

    public let kind: Kind
    public let id: String
    public let workspaceID: String?

    private init(kind: Kind, id: String, workspaceID: String?) {
        self.kind = kind
        self.id = id
        self.workspaceID = workspaceID
    }

    public static func workspace(id: String) -> BessieDragPayload {
        BessieDragPayload(kind: .workspace, id: id, workspaceID: nil)
    }

    public static func tab(id: String, workspaceID: String) -> BessieDragPayload {
        BessieDragPayload(kind: .tab, id: id, workspaceID: workspaceID)
    }

    public var encoded: String {
        guard let data = try? JSONEncoder().encode(self),
              let value = String(data: data, encoding: .utf8)
        else { return "" }
        return value
    }

    public init?(encoded: String) {
        guard let data = encoded.data(using: .utf8),
              let payload = try? JSONDecoder().decode(BessieDragPayload.self, from: data)
        else { return nil }
        self = payload
    }
}

public enum BessieReorderDrop {
    public static func workspaceAction(
        payload: BessieDragPayload,
        over targetID: String,
        projection: HerdrSessionProjection
    ) -> HerdrAction? {
        guard payload.kind == .workspace,
              payload.id != targetID,
              let sourceIndex = projection.workspaces.firstIndex(where: { $0.id == payload.id }),
              let targetIndex = projection.workspaces.firstIndex(where: { $0.id == targetID })
        else { return nil }
        // Herdr interprets insert_index as a slot in the pre-removal collection.
        let insertIndex = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
        return .workspaceMove(id: payload.id, insertIndex: insertIndex)
    }

    public static func tabAction(
        payload: BessieDragPayload,
        over targetID: String,
        workspaceID: String,
        projection: HerdrSessionProjection
    ) -> HerdrAction? {
        let tabs = projection.tabs.filter { $0.workspaceID == workspaceID }
        guard payload.kind == .tab,
              payload.workspaceID == workspaceID,
              payload.id != targetID,
              let sourceIndex = tabs.firstIndex(where: { $0.id == payload.id }),
              let targetIndex = tabs.firstIndex(where: { $0.id == targetID })
        else { return nil }
        let insertIndex = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
        return .tabMove(id: payload.id, insertIndex: insertIndex)
    }
}

public enum BessieSplitDrag {
    public static func ratio(original: Double, translation: Double, extent: Double) -> Double {
        guard original.isFinite, translation.isFinite, extent.isFinite, extent > 0 else { return original }
        return min(0.9, max(0.1, original + (translation / extent)))
    }
}
