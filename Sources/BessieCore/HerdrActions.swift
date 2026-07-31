import Foundation

public struct HerdrActionRequest: Equatable, Sendable { public let method: String; public let params: [String: JSONValue] }

private func compactJSON(_ values: [String: JSONValue?]) -> [String: JSONValue] {
    values.compactMapValues { $0 }
}

public enum PaneZoomMode: String, Equatable, Sendable { case toggle, on, off }

public enum PaneMoveDestination: Equatable, Sendable {
    case tab(tabID: String, targetPaneID: String?, split: SplitDirection, ratio: Double?)
    case newTab(workspaceID: String?, label: String?)
    case newWorkspace(label: String?, tabLabel: String?)

    var json: JSONValue {
        switch self {
        case .tab(let tabID, let targetPaneID, let split, let ratio):
            return .object(compactJSON(["type": .string("tab"), "tab_id": .string(tabID), "target_pane_id": targetPaneID.map(JSONValue.string), "split": .string(split.rawValue), "ratio": ratio.map(JSONValue.number)]))
        case .newTab(let workspaceID, let label):
            return .object(compactJSON(["type": .string("new_tab"), "workspace_id": workspaceID.map(JSONValue.string), "label": label.map(JSONValue.string)]))
        case .newWorkspace(let label, let tabLabel):
            return .object(compactJSON(["type": .string("new_workspace"), "label": label.map(JSONValue.string), "tab_label": tabLabel.map(JSONValue.string)]))
        }
    }
}

public enum HerdrAction: Equatable, Sendable {
    case workspaceCreate(cwd: String?, label: String?, focus: Bool)
    case workspaceFocus(id: String), workspaceRename(id: String, label: String), workspaceMove(id: String, insertIndex: Int), workspaceClose(id: String)
    case tabCreate(workspaceID: String, cwd: String?, label: String?, focus: Bool)
    case tabFocus(id: String), tabRename(id: String, label: String), tabMove(id: String, insertIndex: Int), tabClose(id: String)
    case paneSplit(targetPaneID: String, direction: SplitDirection, ratio: Double?, cwd: String?, focus: Bool)
    case paneFocus(id: String), paneResize(id: String, direction: PaneDirection, amount: Double?)
    case paneSwap(id: String, direction: PaneDirection), paneSwapExplicit(sourceID: String, targetID: String)
    case paneMove(id: String, destination: PaneMoveDestination, focus: Bool)
    case paneZoom(id: String, mode: PaneZoomMode), paneRename(id: String, label: String?), paneClose(id: String)
    case setSplitRatio(tabID: String, path: [Bool], ratio: Double)
    case agentStart(paneID: String, kind: String, name: String, args: [String], timeoutMilliseconds: UInt64?)

    public var request: HerdrActionRequest {
        switch self {
        case .workspaceCreate(let cwd, let label, let focus): return .init(method: "workspace.create", params: compactJSON(["cwd": cwd.map(JSONValue.string), "label": label.map(JSONValue.string), "focus": .bool(focus)]))
        case .workspaceFocus(let id): return target("workspace.focus", "workspace_id", id)
        case .workspaceRename(let id, let label): return .init(method: "workspace.rename", params: ["workspace_id": .string(id), "label": .string(label)])
        case .workspaceMove(let id, let index): return .init(method: "workspace.move", params: ["workspace_id": .string(id), "insert_index": .number(Double(index))])
        case .workspaceClose(let id): return target("workspace.close", "workspace_id", id)
        case .tabCreate(let workspaceID, let cwd, let label, let focus): return .init(method: "tab.create", params: compactJSON(["workspace_id": .string(workspaceID), "cwd": cwd.map(JSONValue.string), "label": label.map(JSONValue.string), "focus": .bool(focus)]))
        case .tabFocus(let id): return target("tab.focus", "tab_id", id)
        case .tabRename(let id, let label): return .init(method: "tab.rename", params: ["tab_id": .string(id), "label": .string(label)])
        case .tabMove(let id, let index): return .init(method: "tab.move", params: ["tab_id": .string(id), "insert_index": .number(Double(index))])
        case .tabClose(let id): return target("tab.close", "tab_id", id)
        case .paneSplit(let targetID, let direction, let ratio, let cwd, let focus): return .init(method: "pane.split", params: compactJSON(["target_pane_id": .string(targetID), "direction": .string(direction.rawValue), "ratio": ratio.map(JSONValue.number), "cwd": cwd.map(JSONValue.string), "focus": .bool(focus)]))
        case .paneFocus(let id): return target("pane.focus", "pane_id", id)
        case .paneResize(let id, let direction, let amount): return .init(method: "pane.resize", params: compactJSON(["pane_id": .string(id), "direction": .string(direction.rawValue), "amount": amount.map(JSONValue.number)]))
        case .paneSwap(let id, let direction): return .init(method: "pane.swap", params: ["pane_id": .string(id), "direction": .string(direction.rawValue)])
        case .paneSwapExplicit(let source, let target): return .init(method: "pane.swap", params: ["source_pane_id": .string(source), "target_pane_id": .string(target)])
        case .paneMove(let id, let destination, let focus): return .init(method: "pane.move", params: ["pane_id": .string(id), "destination": destination.json, "focus": .bool(focus)])
        case .paneZoom(let id, let mode): return .init(method: "pane.zoom", params: ["pane_id": .string(id), "mode": .string(mode.rawValue)])
        case .paneRename(let id, let label): return .init(method: "pane.rename", params: ["pane_id": .string(id), "label": label.map(JSONValue.string) ?? .null])
        case .paneClose(let id): return target("pane.close", "pane_id", id)
        case .setSplitRatio(let tabID, let path, let ratio): return .init(method: "layout.set_split_ratio", params: ["tab_id": .string(tabID), "path": .array(path.map(JSONValue.bool)), "ratio": .number(ratio)])
        case .agentStart(let paneID, let kind, let name, let args, let timeout):
            return .init(method: "agent.start", params: compactJSON([
                "pane_id": .string(paneID), "kind": .string(kind), "name": .string(name),
                "args": args.isEmpty ? nil : .array(args.map(JSONValue.string)),
                "timeout_ms": timeout.map { .number(Double($0)) },
            ]))
        }
    }

    private func target(_ method: String, _ key: String, _ id: String) -> HerdrActionRequest { .init(method: method, params: [key: .string(id)]) }
}

public protocol HerdrMutationAPI: Sendable {
    func request(method: String, params: [String: JSONValue]) throws -> JSONValue
    func snapshot() throws -> HerdrSnapshot
}
extension HerdrSocketAPI: HerdrMutationAPI {}

public struct HerdrActionClient: Sendable {
    private let api: any HerdrMutationAPI
    public init(api: any HerdrMutationAPI) { self.api = api }
    public func perform(_ action: HerdrAction) throws -> HerdrSessionProjection {
        try perform([action])
    }
    public func perform(_ actions: [HerdrAction]) throws -> HerdrSessionProjection {
        guard !actions.isEmpty else { return try HerdrSessionProjection(snapshot: api.snapshot()) }
        for action in actions {
            let request = action.request
            _ = try api.request(method: request.method, params: request.params)
        }
        return try HerdrSessionProjection(snapshot: api.snapshot())
    }
}
