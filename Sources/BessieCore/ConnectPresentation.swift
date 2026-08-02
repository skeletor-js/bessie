public struct ConnectPresentation: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case notChecked
        case notFound
        case stopped
        case incompatible
        case connecting
        case connected
        case retrying
        case lost
    }

    public let title: String
    public let detail: String
    public let status: Status

    public init(title: String, detail: String, status: Status) {
        self.title = title
        self.detail = detail
        self.status = status
    }

    public static let initial = ConnectPresentation(
        title: "Connecting to Herdr",
        detail: "Opening your Bessie session…",
        status: .notChecked
    )

    public init(connectionState: HerdrConnectionState) {
        switch connectionState {
        case .notFound:
            self.init(
                title: "Herdr not found",
                detail: "Install Herdr to use Bessie.",
                status: .notFound
            )
        case .resolutionFailed(let failure):
            self.init(title: "Runtime needs attention", detail: failure.localizedDescription, status: .notFound)
        case .validationFailed(_, let failure):
            self.init(title: "Runtime needs attention", detail: String(describing: failure), status: .incompatible)
        case .stopped:
            self.init(
                title: "Herdr is not running",
                detail: "Automatic startup is off. Start Herdr, then try again.",
                status: .stopped
            )
        case .starting:
            self.init(
                title: "Starting Herdr",
                detail: "Opening your Bessie session…",
                status: .connecting
            )
        case .startFailed(_, let reason):
            self.init(
                title: "Herdr couldn't start",
                detail: reason,
                status: .stopped
            )
        case .incompatible(_, _, let reason):
            self.init(title: "Herdr is incompatible", detail: reason, status: .incompatible)
        case .connecting:
            self.init(title: "Connecting to Herdr", detail: "Opening your Bessie session…", status: .connecting)
        case .apiUnavailable(_, let reason):
            self.init(title: "Herdr API unavailable", detail: reason, status: .lost)
        case .connected(_, _, let snapshot):
            self.init(
                title: "Connected to Herdr",
                detail: "\(Self.count(snapshot.workspaces.count, singular: "workspace")) · \(Self.count(snapshot.tabs.count, singular: "tab")) · \(Self.count(snapshot.panes.count, singular: "pane"))",
                status: .connected
            )
        case .retrying(_, _, let delay, _):
            self.init(title: "Reconnecting to Herdr", detail: "Trying again in \(delay.formatted()) seconds.", status: .retrying)
        case .lost:
            self.init(title: "Couldn't reconnect", detail: "Your work is still running. Start Herdr, then try again.", status: .lost)
        }
    }

    private static func count(_ value: Int, singular: String) -> String {
        "\(value) \(singular)\(value == 1 ? "" : "s")"
    }
}
