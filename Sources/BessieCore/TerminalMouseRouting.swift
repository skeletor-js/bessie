import Foundation

/// Routes pointer events into a Herdr-owned pane.
///
/// Ghostty works because it owns the PTY and only encodes mouse when the app
/// enabled DECSET mouse modes. Bessie cannot see those modes in Herdr's painted
/// ANSI frames, so it synthesizes SGR for mouse-aware TUIs (Hermes uses
/// 1000+1002+1003+1006). Free motion is cell-throttled by the caller to avoid
/// flooding shells with sub-pixel mouseMoved events.
public enum TerminalMouseCaptureCapability: Equatable, Sendable {
    /// No SGR — local selection + Herdr wheel only.
    case unavailable
    /// Button/drag SGR only; free motion never becomes PTY bytes.
    case buttons
    /// Click/drag/hover/wheel SGR (Hermes-grade). Only for panes that opt in.
    case full
}

public enum TerminalPointerKind: Equatable, Sendable {
    case buttonDown
    case buttonUp
    case drag
    case motion
    case wheel
}

public enum TerminalMouseRoute: Equatable, Sendable {
    case none
    case focusOnly
    case localSelection
    case focusAndLocalSelection
    case herdrScroll(direction: TerminalScrollDirection, lines: Int)
    case sgrRaw(Data)
}

public enum TerminalMouseRouting: Sendable {
    /// Decide whether this pane should receive synthesized SGR mouse bytes.
    ///
    /// Plain shells must never get SGR — that is the "gibberish flood" bug.
    /// Ghostty only encodes mouse after DECSET; Bessie cannot see DECSET in
    /// Herdr frames, so gate on pane identity instead: Hermes TUI panes opt in,
    /// everything else stays quiet.
    public static func captureCapability(
        agent: String?,
        foregroundCWD: String? = nil
    ) -> TerminalMouseCaptureCapability {
        if let agent, agent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "hermes" {
            return .full
        }
        if let foregroundCWD,
           foregroundCWD.contains("hermes-agent/ui-tui") || foregroundCWD.contains("/ui-tui") {
            return .full
        }
        return .unavailable
    }

    /// - Parameter sgrData: pre-encoded SGR bytes (encode on the MainActor first —
    ///   do not pass a MainActor-isolated encoder closure into this nonisolated
    ///   function; that deadlocks).
    public static func route(
        kind: TerminalPointerKind,
        forceLocalSelection: Bool,
        capture: TerminalMouseCaptureCapability,
        gestureArmed: Bool = false,
        motionCellChanged: Bool = true,
        wheelDeltaY: Double = 0,
        sgrData: Data? = nil
    ) -> TerminalMouseRoute {
        if forceLocalSelection {
            switch kind {
            case .buttonDown, .buttonUp, .drag:
                return .localSelection
            case .motion:
                return .none
            case .wheel:
                return herdrScroll(deltaY: wheelDeltaY)
            }
        }

        switch capture {
        case .unavailable:
            switch kind {
            case .buttonDown:
                return .focusAndLocalSelection
            case .buttonUp, .drag:
                return .localSelection
            case .motion:
                return .none
            case .wheel:
                return herdrScroll(deltaY: wheelDeltaY)
            }

        case .buttons:
            switch kind {
            case .buttonDown:
                return sgr(sgrData) ?? .focusAndLocalSelection
            case .buttonUp, .drag:
                if gestureArmed {
                    return sgr(sgrData) ?? .none
                }
                return .localSelection
            case .motion:
                return .none
            case .wheel:
                return sgr(sgrData) ?? herdrScroll(deltaY: wheelDeltaY)
            }

        case .full:
            switch kind {
            case .buttonDown, .buttonUp, .drag, .motion, .wheel:
                if kind == .motion, !motionCellChanged {
                    return .none
                }
                return sgr(sgrData) ?? .none
            }
        }
    }

    private static func sgr(_ data: Data?) -> TerminalMouseRoute? {
        guard let data else { return nil }
        return .sgrRaw(data)
    }

    private static func herdrScroll(deltaY: Double) -> TerminalMouseRoute {
        guard deltaY != 0 else { return .none }
        let lines = max(1, Int(abs(deltaY) / 8))
        return .herdrScroll(direction: deltaY > 0 ? .up : .down, lines: lines)
    }
}
