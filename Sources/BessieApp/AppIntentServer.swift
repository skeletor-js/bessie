import BessieCore
import Foundation

final class AppIntentServer: @unchecked Sendable {
    let live: AppIntentLivePort
    let dispatcher: BessieIntentActionDispatcher
    private let server: BessieIntentSocketServer

    init(
        path: String = BessieIntentSocketPath.resolved(),
        projects: any BessieIntentProjectReadPort = BessieProjectStore()
    ) {
        let live = AppIntentLivePort()
        let executor = BessieIntentExecutor(live: live, projects: projects)
        self.live = live
        dispatcher = BessieIntentActionDispatcher(live: live, executor: executor)
        server = BessieIntentSocketServer(path: path) { request in executor.execute(request) }
    }

    func start() throws { try server.start() }
    func stop() { server.stop() }
}
