import Foundation
import XCTest
@testable import BessieCore

final class BessieProjectMaterializationTests: XCTestCase {
    func testValidationAndConnectionGatesRunBeforeMutation() throws {
        let api = MaterializationAPI()
        let materializer = BessieProjectMaterializer(api: api, connectionStatus: { _ in .current })
        var invalid = makeProject(directory: "/definitely/missing/bessie-project")
        invalid.name = " "

        XCTAssertThrowsError(try materializer.materialize(invalid, on: localConnection())) { error in
            XCTAssertEqual(failure(error).stage, .validatingProject)
            XCTAssertFalse(failure(error).partialResult.isPartial)
        }
        XCTAssertTrue(api.requests.isEmpty)

        try withTemporaryDirectory { directory in
            let project = makeProject(directory: directory.path)
            XCTAssertThrowsError(try materializer.materialize(
                project,
                on: localConnection(identity: .init(version: "0.7.4", protocolVersion: 16))
            )) {
                guard case .incompatibleConnection = failure($0).ownerError else {
                    return XCTFail("expected incompatible connection, got \(failure($0).ownerError)")
                }
            }
            XCTAssertTrue(api.requests.isEmpty)
        }
    }

    func testRemoteConnectionMaterializesRemotePathThroughPublicHerdrAPI() throws {
        let remoteDirectory = "/srv/bessie/remote-only"
        let project = makeProject(directory: remoteDirectory)
        let api = MaterializationAPI(
            results: [
                workspaceResult("remote-workspace", "remote-tab", "remote-pane"),
                infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "remote-tab"),
                infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "remote-pane"),
            ],
            snapshots: snapshotsForMaterialization(
                directory: remoteDirectory,
                project: project,
                workspaceID: "remote-workspace",
                runtimeTabs: ["remote-tab"],
                runtimePanes: ["remote-pane"]
            )
        )

        let result = try BessieProjectMaterializer(
            api: api,
            connectionStatus: { _ in .current },
            remoteFolderResolver: { folder in
                XCTAssertEqual(folder.path, remoteDirectory)
                return remoteDirectory
            }
        ).materialize(project, on: localConnection(kind: .ssh))

        XCTAssertEqual(result.plan.connection.definition.kind, .ssh)
        XCTAssertEqual(result.workspaceID, "remote-workspace")
        XCTAssertEqual(
            api.requests.first(where: { $0.method == "workspace.create" })?.params["cwd"],
            .string(remoteDirectory)
        )
        XCTAssertFalse(api.requests.contains { $0.method.contains("close") })
    }

    func testRemoteVerificationDoesNotResolveTargetPathThroughClientFilesystem() throws {
        try withTemporaryDirectory { clientDirectory in
            let clientTarget = clientDirectory.appendingPathComponent("client-target", isDirectory: true)
            let targetHostPath = clientDirectory.appendingPathComponent("target-host-path", isDirectory: true)
            try FileManager.default.createDirectory(at: clientTarget, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: targetHostPath, withDestinationURL: clientTarget)
            let project = makeProject(directory: targetHostPath.path)
            let api = MaterializationAPI(
                results: [
                    workspaceResult("remote-workspace", "remote-tab", "remote-pane"),
                    infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "remote-tab"),
                    infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "remote-pane"),
                ],
                snapshots: snapshotsForMaterialization(
                    directory: targetHostPath.path,
                    project: project,
                    workspaceID: "remote-workspace",
                    runtimeTabs: ["remote-tab"],
                    runtimePanes: ["remote-pane"]
                )
            )

            let result = try BessieProjectMaterializer(
                api: api,
                connectionStatus: { _ in .current },
                remoteFolderResolver: { _ in targetHostPath.path }
            ).materialize(project, on: localConnection(kind: .ssh))

            XCTAssertEqual(result.plan.project.workingDirectory, targetHostPath.path)
            XCTAssertNotEqual(targetHostPath.resolvingSymlinksInPath().path, targetHostPath.path)
        }
    }

    func testRemoteMacPathFailsPreflightBeforeBootstrapWorkspaceMutation() throws {
        let macPath = "/Users/example/Workspace/client-project"
        let project = makeProject(directory: macPath)
        let api = MaterializationAPI()

        XCTAssertThrowsError(try BessieProjectMaterializer(
            api: api,
            connectionStatus: { _ in .current },
            remoteFolderResolver: { _ in throw WorkspacePathError.notFound }
        ).materialize(project, on: localConnection(kind: .ssh))) { error in
            let failure = failure(error)
            XCTAssertEqual(failure.stage, .validatingProject)
            XCTAssertEqual(
                failure.ownerError,
                .remoteFolderUnavailable(
                    folderID: project.folders[0].id,
                    path: macPath,
                    reason: WorkspacePathError.notFound.localizedDescription
                )
            )
            XCTAssertNil(failure.partialResult.workspaceID)
            XCTAssertEqual(failure.partialResult.mutationOutcome, .notAttempted)
        }
        XCTAssertTrue(api.requests.isEmpty)
    }

    func testProjectTargetConnectionMismatchFailsBeforeMutation() throws {
        var project = makeProject(directory: "/srv/catapult")
        project.targetConnectionID = "different-herd"
        let api = MaterializationAPI()

        XCTAssertThrowsError(try BessieProjectMaterializer(
            api: api,
            connectionStatus: { _ in .current }
        ).materialize(project, on: localConnection(kind: .ssh))) { error in
            XCTAssertEqual(
                failure(error).ownerError,
                .targetConnectionMismatch(expectedConnectionID: "different-herd", actualConnectionID: "fixture")
            )
            XCTAssertEqual(failure(error).partialResult.mutationOutcome, .notAttempted)
        }
        XCTAssertTrue(api.requests.isEmpty)
    }

    func testFallbackCWDDoesNotAbortAtBootstrapButStopsCommandsAfterFullTopologyVerification() throws {
        let targetDirectory = "/srv/workstreams/client-project"
        let fallbackDirectory = "/home/example"
        let firstRoot = UUID(), split = UUID(), secondRoot = UUID()
        let project = makeProject(directory: targetDirectory, command: nil, tabs: [
            .init(name: "Catapult Boss", panes: [
                .init(id: firstRoot, label: "Boss", command: "hermes", placement: .root),
                .init(
                    id: split,
                    label: "Logs",
                    placement: .split(fromPaneID: firstRoot, direction: .right, ratio: 0.5)
                ),
            ]),
            .init(name: "Tests", panes: [
                .init(id: secondRoot, label: "Tests", placement: .root),
            ]),
        ])
        let wrongCWD = snapshotsForMaterialization(
            directory: fallbackDirectory,
            project: project,
            workspaceID: "w2X",
            runtimeTabs: ["w2X:t1", "w2X:t2"],
            runtimePanes: ["w2X:p1", "w2X:p2", "w2X:p3"],
            finalCopies: 8
        )
        let api = MaterializationAPI(
            results: [
                workspaceResult("w2X", "w2X:t1", "w2X:p1"),
                infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "w2X:t1"),
                infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "w2X:p1"),
                tabResult("w2X:t2", "w2X:p3"),
                infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "w2X:p3"),
                paneResult("w2X:p2"),
                infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "w2X:p2"),
            ],
            snapshots: wrongCWD
        )

        XCTAssertThrowsError(try BessieProjectMaterializer(
            api: api,
            connectionStatus: { _ in .current },
            remoteFolderResolver: { _ in targetDirectory }
        ).materialize(project, on: localConnection(kind: .ssh))) { error in
            let failure = failure(error)
            XCTAssertEqual(failure.stage, .verifyingTopology)
            guard case .verification(let issues) = failure.ownerError else {
                return XCTFail("expected final topology verification failure")
            }
            XCTAssertTrue(issues.contains(.paneCWDMismatch(
                recipePaneID: firstRoot,
                runtimePaneID: "w2X:p1",
                expected: targetDirectory,
                actual: fallbackDirectory
            )))
            XCTAssertEqual(failure.partialResult.tabIDsByRecipeID.count, 2)
            XCTAssertEqual(failure.partialResult.paneIDsByRecipeID.count, 3)
            XCTAssertTrue(failure.partialResult.commands.isEmpty)
        }

        let methods = api.requests.map(\.method)
        XCTAssertTrue(methods.contains("tab.rename"))
        XCTAssertTrue(methods.contains("tab.create"))
        XCTAssertTrue(methods.contains("pane.split"))
        XCTAssertEqual(methods.filter { $0 == "pane.rename" }.count, 3)
        XCTAssertFalse(methods.contains("pane.read"))
        XCTAssertFalse(methods.contains("pane.send_input"))
    }

    func testFolderAvailabilityAndPaneReferencesAreValidatedBeforeAnyHerdrMutation() throws {
        try withTemporaryDirectory { directory in
            let api = MaterializationAPI()
            let missingFolderID = UUID()
            let project = BessieProject(
                name: "Folder validation",
                targetConnectionID: "fixture",
                folders: [
                    .init(name: "Primary", path: directory.path, isPrimary: true),
                ],
                tabs: [.init(name: "Main", panes: [
                    .init(folderID: missingFolderID, placement: .root),
                ])]
            )

            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: api,
                connectionStatus: { _ in .current }
            ).materialize(project, on: localConnection())) { error in
                guard case .validation(let issues) = failure(error).ownerError else {
                    return XCTFail("expected folder validation failure, got \(failure(error).ownerError)")
                }
                XCTAssertTrue(issues.contains {
                    $0.code == .paneFolderMissing && $0.folderID == missingFolderID
                })
            }
            XCTAssertTrue(api.requests.isEmpty)
        }
    }

    func testCancellationBeforeWorkspaceCreationMakesNoRequest() throws {
        try withTemporaryDirectory { directory in
            let api = MaterializationAPI()
            let materializer = BessieProjectMaterializer(
                api: api, connectionStatus: { _ in .current }, isCancelled: { true }
            )

            XCTAssertThrowsError(try materializer.materialize(
                makeProject(directory: directory.path), on: localConnection()
            )) {
                XCTAssertEqual(failure($0).ownerError, .cancelled)
                XCTAssertEqual(failure($0).stage, .validatingConnection)
                XCTAssertFalse(failure($0).partialResult.isPartial)
            }
            XCTAssertTrue(api.requests.isEmpty)
        }
    }

    func testTransportSocketAndBootstrappedIdentityMustMatchConnectionBeforeMutation() throws {
        try withTemporaryDirectory { directory in
            let project = makeProject(directory: directory.path)
            let wrongSocketAPI = MaterializationAPI(socketPath: "/tmp/a-different-isolated.sock")
            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: wrongSocketAPI, connectionStatus: { _ in .current }
            ).materialize(project, on: localConnection())) {
                XCTAssertEqual(failure($0).ownerError, .invalidEndpoint)
            }
            XCTAssertTrue(wrongSocketAPI.requests.isEmpty)

            let changedIdentityAPI = MaterializationAPI(
                identity: .init(version: "0.7.4", protocolVersion: 19)
            )
            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: changedIdentityAPI, connectionStatus: { _ in .current }
            ).materialize(project, on: localConnection())) {
                XCTAssertEqual(failure($0).ownerError, .connectionChanged)
            }
            XCTAssertTrue(changedIdentityAPI.requests.isEmpty)
        }
    }

    func testWhitespaceOnlyCommandIsRejectedBeforeMutation() throws {
        try withTemporaryDirectory { directory in
            let api = MaterializationAPI()
            let project = makeProject(directory: directory.path, command: " \t ")

            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: api, connectionStatus: { _ in .current }
            ).materialize(project, on: localConnection())) {
                XCTAssertEqual(
                    failure($0).ownerError,
                    .invalidCommand(recipePaneID: project.tabs[0].panes[0].id)
                )
                XCTAssertEqual(failure($0).partialResult.mutationOutcome, .notAttempted)
            }
            XCTAssertTrue(api.requests.isEmpty)
        }
    }

    func testMaterializesExactReturnedIDsInDeterministicOrderBeforeCommands() throws {
        try withTemporaryDirectory { directory in
            let rootOne = UUID(), splitOne = UUID(), splitTwo = UUID(), rootTwo = UUID()
            let project = makeProject(directory: directory.path, tabs: [
                .init(name: "duplicate", panes: [
                    .init(id: rootOne, label: "duplicate", command: "echo first", placement: .root),
                    .init(id: splitOne, label: "duplicate", placement: .split(fromPaneID: rootOne, direction: .right, ratio: 0.4)),
                    .init(id: splitTwo, command: "echo second", placement: .split(fromPaneID: splitOne, direction: .down, ratio: 0.6)),
                ]),
                .init(name: "duplicate", panes: [
                    .init(id: rootTwo, label: "duplicate", placement: .root),
                ]),
            ])
            let normalizedDirectory = try project.normalized().workingDirectory
            let api = MaterializationAPI(
                results: [
                    workspaceResult("runtime-workspace", "runtime-tab-a", "runtime-pane-a"),
                    infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "runtime-tab-a"),
                    infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "runtime-pane-a"),
                    tabResult("runtime-tab-d", "runtime-pane-d"),
                    infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "runtime-pane-d"),
                    paneResult("runtime-pane-b"),
                    infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "runtime-pane-b"),
                    paneResult("runtime-pane-c"),
                    paneRead("$ "), ok(), paneRead("$ echo first"), paneRead("$ echo first"), ok(),
                    paneRead("$ "), ok(), paneRead("$ echo second"), paneRead("$ echo second"), ok(),
                ],
                snapshots: snapshotsForMaterialization(
                    directory: normalizedDirectory,
                    project: project,
                    runtimeTabs: ["runtime-tab-a", "runtime-tab-d"],
                    runtimePanes: ["runtime-pane-a", "runtime-pane-b", "runtime-pane-c", "runtime-pane-d"]
                )
            )
            let result = try BessieProjectMaterializer(
                api: api, connectionStatus: { _ in .current }
            ).materialize(project, on: localConnection())

            XCTAssertEqual(result.workspaceID, "runtime-workspace")
            XCTAssertEqual(result.tabIDsByRecipeID[project.tabs[0].id], "runtime-tab-a")
            XCTAssertEqual(result.tabIDsByRecipeID[project.tabs[1].id], "runtime-tab-d")
            XCTAssertEqual(result.paneIDsByRecipeID[rootOne], "runtime-pane-a")
            XCTAssertEqual(result.paneIDsByRecipeID[splitOne], "runtime-pane-b")
            XCTAssertEqual(result.paneIDsByRecipeID[splitTwo], "runtime-pane-c")
            XCTAssertEqual(result.paneIDsByRecipeID[rootTwo], "runtime-pane-d")
            XCTAssertEqual(result.commands.map(\.enterSubmitted), [true, true])
            XCTAssertTrue(result.verificationFacts.contains(.workspace(
                recipeProjectID: project.id, runtimeWorkspaceID: "runtime-workspace"
            )))
            XCTAssertTrue(result.verificationFacts.contains(.commandEnterSubmitted(
                recipePaneID: rootOne, runtimePaneID: "runtime-pane-a"
            )))

            let methods = api.requests.map(\.method)
            XCTAssertEqual(methods.filter { $0 == "workspace.create" }.count, 1)
            XCTAssertEqual(methods.filter { $0 == "tab.create" }.count, 1)
            let splitRequests = api.requests.filter { $0.method == "pane.split" }
            XCTAssertEqual(splitRequests.map { $0.params["target_pane_id"] }, [.string("runtime-pane-a"), .string("runtime-pane-b")])
            XCTAssertEqual(splitRequests.map { $0.params["ratio"] }, [.number(0.4), .number(0.6)])
            let firstCommandIndex = try XCTUnwrap(methods.firstIndex(of: "pane.read"))
            let lastTopologyIndex = try XCTUnwrap(methods.lastIndex(where: { ["workspace.create", "tab.create", "pane.split", "tab.rename", "pane.rename"].contains($0) }))
            XCTAssertGreaterThan(firstCommandIndex, lastTopologyIndex)
            XCTAssertFalse(api.requests.contains { $0.method.contains("close") })
        }
    }

    func testMaterializesAndVerifiesExactFolderCWDForWorkspaceTabAndSplitPane() throws {
        try withTemporaryDirectory { directory in
            let additional = directory.appendingPathComponent("Additional", isDirectory: true)
            try FileManager.default.createDirectory(at: additional, withIntermediateDirectories: true)
            let primaryID = UUID(), additionalID = UUID()
            let firstRoot = UUID(), split = UUID(), secondRoot = UUID()
            let project = BessieProject(
                name: "Two folders",
                targetConnectionID: "fixture",
                folders: [
                    .init(id: primaryID, name: "Primary", path: directory.path, isPrimary: true),
                    .init(id: additionalID, name: "Additional", path: additional.path),
                ],
                tabs: [
                    .init(name: "Primary tab", panes: [
                        .init(id: firstRoot, placement: .root),
                        .init(
                            id: split,
                            folderID: additionalID,
                            placement: .split(fromPaneID: firstRoot, direction: .right, ratio: 0.5)
                        ),
                    ]),
                    .init(name: "Additional tab", panes: [
                        .init(id: secondRoot, folderID: additionalID, placement: .root),
                    ]),
                ]
            )
            let normalized = try project.normalized()
            let primaryCWD = try XCTUnwrap(normalized.workingDirectory(for: normalized.tabs[0].panes[0]))
            let additionalCWD = try XCTUnwrap(normalized.workingDirectory(for: normalized.tabs[0].panes[1]))
            let api = MaterializationAPI(
                results: [
                    workspaceResult("w1", "t1", "p1"),
                    infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t1"),
                    tabResult("t2", "p3"),
                    paneResult("p2"),
                ],
                snapshots: snapshotsForMaterialization(
                    directory: primaryCWD,
                    project: normalized,
                    workspaceID: "w1",
                    runtimeTabs: ["t1", "t2"],
                    runtimePanes: ["p1", "p2", "p3"],
                    paneDirectories: [primaryCWD, additionalCWD, additionalCWD]
                )
            )

            let result = try BessieProjectMaterializer(
                api: api,
                connectionStatus: { _ in .current }
            ).materialize(project, on: localConnection())

            XCTAssertEqual(
                api.requests.first(where: { $0.method == "workspace.create" })?.params["cwd"],
                .string(primaryCWD)
            )
            XCTAssertEqual(
                api.requests.first(where: { $0.method == "tab.create" })?.params["cwd"],
                .string(additionalCWD)
            )
            XCTAssertEqual(
                api.requests.first(where: { $0.method == "pane.split" })?.params["cwd"],
                .string(additionalCWD)
            )
            XCTAssertTrue(result.verificationFacts.contains(
                .pane(recipePaneID: firstRoot, runtimePaneID: "p1", runtimeTabID: "t1", cwd: primaryCWD)
            ))
            XCTAssertTrue(result.verificationFacts.contains(
                .pane(recipePaneID: split, runtimePaneID: "p2", runtimeTabID: "t1", cwd: additionalCWD)
            ))
            XCTAssertTrue(result.verificationFacts.contains(
                .pane(recipePaneID: secondRoot, runtimePaneID: "p3", runtimeTabID: "t2", cwd: additionalCWD)
            ))
        }
    }

    func testReadinessTimeoutReturnsPartialWithoutTextEnterOrCleanup() throws {
        try withTemporaryDirectory { directory in
            var project = makeProject(directory: directory.path, command: "echo waiting")
            project.tabs[0].panes[0].label = nil
            let normalizedDirectory = try project.normalized().workingDirectory
            let api = MaterializationAPI(
                results: [
                    workspaceResult("w1", "t1", "p1"),
                    infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t1"),
                    paneRead(""), paneRead(" "), paneRead(""),
                ],
                snapshots: snapshotsForMaterialization(
                    directory: normalizedDirectory, project: project,
                    workspaceID: "w1", runtimeTabs: ["t1"], runtimePanes: ["p1"], finalCopies: 3
                )
            )
            let clock = MaterializationClock()
            let materializer = BessieProjectMaterializer(
                api: api,
                connectionStatus: { _ in .current },
                commandPolicy: .init(pollInterval: 0.5, readinessTimeout: 1, echoTimeout: 1),
                now: clock.now,
                wait: clock.wait
            )

            XCTAssertThrowsError(try materializer.materialize(project, on: localConnection())) {
                XCTAssertEqual(failure($0).stage, .waitingForCommandReadiness)
                XCTAssertEqual(failure($0).ownerError, .startup(.readinessTimedOut(paneID: "p1")))
                XCTAssertEqual(failure($0).partialResult.commands.map(\.textSubmitted), [false])
            }
            XCTAssertFalse(api.requests.contains { $0.method == "pane.send_input" || $0.method.contains("close") })
        }
    }

    func testEchoTimeoutReturnsExactPartialCommandStateWithoutEnterOrCleanup() throws {
        try withTemporaryDirectory { directory in
            let project = makeProject(directory: directory.path, command: "echo never-confirmed")
            let normalizedDirectory = try project.normalized().workingDirectory
            let api = MaterializationAPI(
                results: [
                    workspaceResult("w-exact", "t-exact", "p-exact"),
                    infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t-exact"),
                    infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "p-exact"),
                    paneRead("$ "), ok(), paneRead("$ unrelated"), paneRead("$ unrelated"),
                ],
                snapshots: snapshotsForMaterialization(
                    directory: normalizedDirectory, project: project,
                    workspaceID: "w-exact", runtimeTabs: ["t-exact"], runtimePanes: ["p-exact"], finalCopies: 3
                )
            )
            let clock = MaterializationClock()
            let materializer = BessieProjectMaterializer(
                api: api,
                connectionStatus: { _ in .current },
                commandPolicy: .init(pollInterval: 0.5, readinessTimeout: 1, echoTimeout: 1),
                now: clock.now,
                wait: clock.wait
            )

            XCTAssertThrowsError(try materializer.materialize(project, on: localConnection())) { error in
                let partial = failure(error).partialResult
                XCTAssertEqual(failure(error).stage, .waitingForCommandEcho)
                XCTAssertEqual(partial.workspaceID, "w-exact")
                XCTAssertEqual(partial.commands.count, 1)
                XCTAssertTrue(partial.commands[0].attempted)
                XCTAssertTrue(partial.commands[0].textSubmitted)
                XCTAssertFalse(partial.commands[0].echoConfirmed)
                XCTAssertFalse(partial.commands[0].enterSubmitted)
                XCTAssertNotNil(partial.freshSnapshot)
            }
            XCTAssertEqual(api.requests.filter { $0.method == "pane.send_input" }.count, 1)
            XCTAssertFalse(api.requests.contains { $0.method.contains("close") })
        }
    }

    func testDisconnectAfterCommandTextReturnsPartialWithoutEnter() throws {
        try withTemporaryDirectory { directory in
            let project = makeProject(directory: directory.path, command: "echo disconnected")
            let normalizedDirectory = try project.normalized().workingDirectory
            let connected = ConnectionSwitch()
            let api = MaterializationAPI(
                results: [
                    workspaceResult("w1", "t1", "p1"),
                    infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t1"),
                    infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "p1"),
                    paneRead("$ "), ok(),
                ],
                snapshots: snapshotsForMaterialization(
                    directory: normalizedDirectory, project: project,
                    workspaceID: "w1", runtimeTabs: ["t1"], runtimePanes: ["p1"]
                ),
                afterRequest: { request in
                    if request.method == "pane.send_input" { connected.value = false }
                }
            )

            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: api,
                connectionStatus: { _ in connected.value ? .current : .disconnected }
            ).materialize(project, on: localConnection())) { error in
                XCTAssertEqual(failure(error).ownerError, .connectionLost)
                XCTAssertEqual(failure(error).stage, .waitingForCommandEcho)
                XCTAssertTrue(failure(error).partialResult.commands[0].textSubmitted)
                XCTAssertFalse(failure(error).partialResult.commands[0].enterSubmitted)
            }
            XCTAssertEqual(api.requests.filter { $0.method == "pane.send_input" }.count, 1)
            XCTAssertFalse(api.requests.contains { $0.method == "pane.send_keys" || $0.method.contains("close") })
        }
    }

    func testCancellationBeforeCommandTextAndEnterPreservesExactCommandState() throws {
        try withTemporaryDirectory { directory in
            let project = makeProject(directory: directory.path, command: "echo boundary")
            let normalizedDirectory = try project.normalized().workingDirectory
            for (targetStage, expectedTextCount) in [
                (BessieProjectMaterializationStage.submittingCommandText, 0),
                (.submittingCommandEnter, 1),
            ] {
                let cancellation = CancellationSwitch()
                let api = MaterializationAPI(
                    results: [
                        workspaceResult("w1", "t1", "p1"),
                        infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t1"),
                        infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "p1"),
                        paneRead("$ "), ok(), paneRead("$ echo boundary"), paneRead("$ echo boundary"),
                    ],
                    snapshots: snapshotsForMaterialization(
                        directory: normalizedDirectory, project: project,
                        workspaceID: "w1", runtimeTabs: ["t1"], runtimePanes: ["p1"]
                    )
                )

                XCTAssertThrowsError(try BessieProjectMaterializer(
                    api: api, connectionStatus: { _ in .current }, isCancelled: { cancellation.value }
                ).materialize(project, on: localConnection()) { fact in
                    if fact.stage == targetStage { cancellation.value = true }
                }) { error in
                    XCTAssertEqual(failure(error).ownerError, .cancelled)
                    XCTAssertEqual(failure(error).stage, targetStage)
                    XCTAssertEqual(failure(error).partialResult.commands[0].textSubmitted, expectedTextCount == 1)
                    XCTAssertFalse(failure(error).partialResult.commands[0].enterSubmitted)
                }
                XCTAssertEqual(api.requests.filter { $0.method == "pane.send_input" }.count, expectedTextCount)
                XCTAssertFalse(api.requests.contains { $0.method == "pane.send_keys" || $0.method.contains("close") })
            }
        }
    }

    func testCancellationAtMutationBoundaryPreservesVerifiedPartialState() throws {
        try withTemporaryDirectory { directory in
            let project = makeProject(directory: directory.path, tabs: [
                .init(name: "One", panes: [.init(placement: .root)]),
                .init(name: "Two", panes: [.init(placement: .root)]),
            ])
            let normalizedDirectory = try project.normalized().workingDirectory
            let cancellation = CancellationSwitch()
            let api = MaterializationAPI(
                results: [workspaceResult("w1", "t1", "p1")],
                snapshots: snapshotsForMaterialization(
                    directory: normalizedDirectory, project: project,
                    workspaceID: "w1", runtimeTabs: ["t1"], runtimePanes: ["p1"], finalCopies: 2
                ),
                afterRequest: { request in
                    if request.method == "workspace.create" { cancellation.value = true }
                }
            )
            let materializer = BessieProjectMaterializer(
                api: api, connectionStatus: { _ in .current }, isCancelled: { cancellation.value }
            )

            XCTAssertThrowsError(try materializer.materialize(project, on: localConnection())) { error in
                XCTAssertEqual(failure(error).ownerError, .cancelled)
                XCTAssertEqual(failure(error).stage, .renamingInitialTab)
                XCTAssertEqual(failure(error).partialResult.workspaceID, "w1")
                XCTAssertEqual(failure(error).partialResult.paneIDsByRecipeID.values.sorted(), ["p1"])
            }
            XCTAssertEqual(api.requests.map(\.method), ["workspace.create"])
            XCTAssertFalse(api.requests.contains { $0.method.contains("close") })
        }
    }

    func testCancellationAtEveryTopologyMutationBoundarySendsNoCurrentMutation() throws {
        try withTemporaryDirectory { directory in
            let rootOne = UUID(), rootTwo = UUID(), split = UUID()
            let firstTab = UUID(), secondTab = UUID()
            let project = makeProject(directory: directory.path, tabs: [
                .init(id: firstTab, name: "One", panes: [
                    .init(id: rootOne, label: "root-one", placement: .root),
                    .init(
                        id: split, label: "split",
                        placement: .split(fromPaneID: rootOne, direction: .right, ratio: 0.4)
                    ),
                ]),
                .init(id: secondTab, name: "Two", panes: [
                    .init(id: rootTwo, label: "root-two", placement: .root),
                ]),
            ])
            let normalizedDirectory = try project.normalized().workingDirectory
            let cases: [(BessieProjectMaterializationStage, BessieProjectMaterializationAttempt, String, Int)] = [
                (.creatingWorkspace, .project(project.id), "workspace.create", 0),
                (.renamingInitialTab, .tab(firstTab), "tab.rename", 0),
                (.labelingPane, .pane(rootOne), "pane.rename", 0),
                (.creatingTab, .tab(secondTab), "tab.create", 0),
                (.labelingPane, .pane(rootTwo), "pane.rename", 1),
                (.splittingPane, .pane(split), "pane.split", 0),
                (.labelingPane, .pane(split), "pane.rename", 2),
            ]

            for (targetStage, targetAttempt, method, expectedCount) in cases {
                let cancellation = CancellationSwitch()
                let api = MaterializationAPI(
                    results: [
                        workspaceResult("w1", "t1", "p1"),
                        infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t1"),
                        infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "p1"),
                        tabResult("t2", "p2"),
                        infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "p2"),
                        paneResult("p3"),
                        infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: "p3"),
                    ],
                    snapshots: snapshotsForMaterialization(
                        directory: normalizedDirectory, project: project,
                        workspaceID: "w1", runtimeTabs: ["t1", "t2"],
                        runtimePanes: ["p1", "p3", "p2"]
                    )
                )
                XCTAssertThrowsError(try BessieProjectMaterializer(
                    api: api, connectionStatus: { _ in .current }, isCancelled: { cancellation.value }
                ).materialize(project, on: localConnection()) { fact in
                    if fact.stage == targetStage && fact.attempt == targetAttempt {
                        cancellation.value = true
                    }
                }) { error in
                    XCTAssertEqual(failure(error).ownerError, .cancelled)
                    XCTAssertEqual(failure(error).stage, targetStage)
                    XCTAssertEqual(failure(error).attempt, targetAttempt)
                    XCTAssertEqual(failure(error).partialResult.mutationOutcome, .notAttempted)
                }
                XCTAssertEqual(api.requests.filter { $0.method == method }.count, expectedCount)
                XCTAssertFalse(api.requests.contains { $0.method.contains("close") })
            }
        }
    }

    func testGenerationChangeStopsBeforeNextMutation() throws {
        try withTemporaryDirectory { directory in
            let project = makeProject(directory: directory.path)
            let normalizedDirectory = try project.normalized().workingDirectory
            let initialGeneration = UUID()
            let generation = GenerationBox(initialGeneration)
            let api = MaterializationAPI(
                results: [workspaceResult("w1", "t1", "p1")],
                snapshots: snapshotsForMaterialization(
                    directory: normalizedDirectory, project: project,
                    workspaceID: "w1", runtimeTabs: ["t1"], runtimePanes: ["p1"]
                ),
                afterRequest: { request in
                    if request.method == "workspace.create" { generation.value = UUID() }
                }
            )
            let connection = localConnection(generation: initialGeneration)
            let materializer = BessieProjectMaterializer(
                api: api,
                connectionStatus: { expected in
                    guard let current = generation.value else { return .disconnected }
                    return current == expected.generation ? .current : .changed
                }
            )

            XCTAssertThrowsError(try materializer.materialize(project, on: connection)) {
                XCTAssertEqual(failure($0).ownerError, .connectionChanged)
                XCTAssertEqual(failure($0).partialResult.workspaceID, "w1")
                XCTAssertNil(failure($0).partialResult.freshSnapshot)
            }
            XCTAssertEqual(api.requests.map(\.method), ["workspace.create"])
        }
    }

    func testGenerationChangeDuringFinalSnapshotCannotReturnComplete() throws {
        try withTemporaryDirectory { directory in
            var project = makeProject(directory: directory.path)
            project.tabs[0].panes[0].label = nil
            let normalizedDirectory = try project.normalized().workingDirectory
            let initialGeneration = UUID()
            let generation = GenerationBox(initialGeneration)
            let api = MaterializationAPI(
                results: [
                    workspaceResult("w1", "t1", "p1"),
                    infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t1"),
                ],
                snapshots: snapshotsForMaterialization(
                    directory: normalizedDirectory, project: project,
                    workspaceID: "w1", runtimeTabs: ["t1"], runtimePanes: ["p1"], finalCopies: 3
                ),
                afterSnapshot: { count in
                    if count == 3 { generation.value = UUID() }
                }
            )
            let connection = localConnection(generation: initialGeneration)

            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: api,
                connectionStatus: { expected in
                    generation.value == expected.generation ? .current : .changed
                }
            ).materialize(project, on: connection)) {
                XCTAssertEqual(failure($0).stage, .verifyingComplete)
                XCTAssertEqual(failure($0).ownerError, .connectionChanged)
                XCTAssertNotNil(failure($0).partialResult.lastVerifiedSnapshot)
            }
        }
    }

    func testDisconnectDuringTopologySnapshotReturnsConnectionLost() throws {
        try withTemporaryDirectory { directory in
            let project = makeProject(directory: directory.path)
            let normalizedDirectory = try project.normalized().workingDirectory
            let connected = ConnectionSwitch()
            let api = MaterializationAPI(
                results: [workspaceResult("w1", "t1", "p1")],
                snapshots: snapshotsForMaterialization(
                    directory: normalizedDirectory, project: project,
                    workspaceID: "w1", runtimeTabs: ["t1"], runtimePanes: ["p1"], finalCopies: 1
                ),
                afterSnapshot: { _ in connected.value = false }
            )

            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: api,
                connectionStatus: { _ in connected.value ? .current : .disconnected }
            ).materialize(project, on: localConnection())) {
                XCTAssertEqual(failure($0).stage, .verifyingCreation)
                XCTAssertEqual(failure($0).ownerError, .connectionLost)
                XCTAssertNil(failure($0).partialResult.lastVerifiedSnapshot)
            }
            XCTAssertEqual(api.requests.map(\.method), ["workspace.create"])
        }
    }

    func testRequestFailureIsAttributedWithoutPretendingMutationSucceeded() throws {
        try withTemporaryDirectory { directory in
            let project = makeProject(directory: directory.path, tabs: [
                .init(name: "One", panes: [.init(placement: .root)]),
                .init(name: "Two", panes: [.init(placement: .root)]),
            ])
            let normalizedDirectory = try project.normalized().workingDirectory
            let api = MaterializationAPI(
                results: [
                    workspaceResult("w1", "t1", "p1"),
                    infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t1"),
                ],
                snapshots: snapshotsForMaterialization(
                    directory: normalizedDirectory, project: project,
                    workspaceID: "w1", runtimeTabs: ["t1"], runtimePanes: ["p1"], finalCopies: 3
                ),
                failure: .init(method: "tab.create", error: .connectionClosed)
            )

            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: api, connectionStatus: { _ in .current }
            ).materialize(project, on: localConnection())) { error in
                let launchFailure = failure(error)
                XCTAssertEqual(launchFailure.stage, .creatingTab)
                XCTAssertEqual(launchFailure.attempt, .tab(project.tabs[1].id))
                XCTAssertNil(launchFailure.partialResult.tabIDsByRecipeID[project.tabs[1].id])
                XCTAssertEqual(launchFailure.partialResult.workspaceID, "w1")
                XCTAssertEqual(launchFailure.partialResult.mutationOutcome, .outcomeUnknown)
                XCTAssertNotNil(launchFailure.partialResult.freshSnapshot)
                XCTAssertNotNil(launchFailure.partialResult.lastVerifiedSnapshot)
            }
            XCTAssertEqual(api.requests.filter { $0.method == "tab.create" }.count, 1)
            XCTAssertFalse(api.requests.contains { $0.method.contains("close") })
        }
    }

    func testDuplicateReturnedTabAndPaneIDsAreRejected() throws {
        try withTemporaryDirectory { directory in
            let twoTabs = makeProject(directory: directory.path, tabs: [
                .init(name: "One", panes: [.init(placement: .root)]),
                .init(name: "Two", panes: [.init(placement: .root)]),
            ])
            let normalizedDirectory = try twoTabs.normalized().workingDirectory
            let duplicateTabAPI = MaterializationAPI(
                results: [
                    workspaceResult("w1", "t1", "p1"),
                    infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t1"),
                    tabResult("t1", "p2"),
                ],
                snapshots: snapshotsForMaterialization(
                    directory: normalizedDirectory, project: twoTabs,
                    workspaceID: "w1", runtimeTabs: ["t1", "t2"], runtimePanes: ["p1", "p2"]
                )
            )
            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: duplicateTabAPI, connectionStatus: { _ in .current }
            ).materialize(twoTabs, on: localConnection())) {
                XCTAssertEqual(failure($0).ownerError, .duplicateRuntimeTabID("t1"))
                XCTAssertNil(failure($0).partialResult.tabIDsByRecipeID[twoTabs.tabs[1].id])
            }

            let root = UUID(), split = UUID()
            let splitProject = makeProject(directory: directory.path, tabs: [
                .init(name: "One", panes: [
                    .init(id: root, placement: .root),
                    .init(id: split, placement: .split(fromPaneID: root, direction: .right, ratio: 0.5)),
                ]),
            ])
            let duplicatePaneAPI = MaterializationAPI(
                results: [
                    workspaceResult("w1", "t1", "p1"),
                    infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t1"),
                    paneResult("p1"),
                ],
                snapshots: snapshotsForMaterialization(
                    directory: normalizedDirectory, project: splitProject,
                    workspaceID: "w1", runtimeTabs: ["t1"], runtimePanes: ["p1", "p2"]
                )
            )
            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: duplicatePaneAPI, connectionStatus: { _ in .current }
            ).materialize(splitProject, on: localConnection())) {
                XCTAssertEqual(failure($0).ownerError, .duplicateRuntimePaneID("p1"))
                XCTAssertNil(failure($0).partialResult.paneIDsByRecipeID[split])
            }
        }
    }

    func testSplitFailureRetainsOnlyAcknowledgedExactIDs() throws {
        try withTemporaryDirectory { directory in
            let root = UUID(), split = UUID()
            let project = makeProject(directory: directory.path, tabs: [
                .init(name: "One", panes: [
                    .init(id: root, placement: .root),
                    .init(id: split, placement: .split(fromPaneID: root, direction: .down, ratio: 0.35)),
                ]),
            ])
            let normalizedDirectory = try project.normalized().workingDirectory
            let api = MaterializationAPI(
                results: [
                    workspaceResult("w1", "t1", "p1"),
                    infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t1"),
                ],
                snapshots: snapshotsForMaterialization(
                    directory: normalizedDirectory, project: project,
                    workspaceID: "w1", runtimeTabs: ["t1"], runtimePanes: ["p1"], finalCopies: 3
                ),
                failure: .init(method: "pane.split", error: .server(code: "split_failed", message: "split failed"))
            )

            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: api, connectionStatus: { _ in .current }
            ).materialize(project, on: localConnection())) {
                XCTAssertEqual(failure($0).stage, .splittingPane)
                XCTAssertEqual(failure($0).attempt, .pane(split))
                XCTAssertEqual(failure($0).partialResult.paneIDsByRecipeID, [root: "p1"])
                XCTAssertNil(failure($0).partialResult.paneIDsByRecipeID[split])
            }
            XCTAssertEqual(api.requests.filter { $0.method == "pane.split" }.count, 1)
            XCTAssertFalse(api.requests.contains { $0.method.contains("close") })
        }
    }

    func testMalformedWorkspaceCreationIDDoesNotInventPartialIdentity() throws {
        try withTemporaryDirectory { directory in
            let project = makeProject(directory: directory.path)
            let api = MaterializationAPI(
                results: [workspaceResult(" ", "t1", "p1")],
                snapshots: [snapshot(
                    directory: directory.path, workspaceID: "unknown", workspaceLabel: "unknown",
                    tabs: [("unknown-tab", "unknown", "unknown")],
                    panes: [("unknown-pane", "unknown", "unknown-tab", nil)]
                )]
            )

            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: api, connectionStatus: { _ in .current }
            ).materialize(project, on: localConnection())) {
                XCTAssertEqual(failure($0).stage, .creatingWorkspace)
                XCTAssertNil(failure($0).partialResult.workspaceID)
                XCTAssertEqual(failure($0).partialResult.mutationOutcome, .outcomeUnknown)
                XCTAssertNotNil(failure($0).partialResult.freshSnapshot)
                XCTAssertNil(failure($0).partialResult.lastVerifiedSnapshot)
                guard case .herdr(.unexpectedResponse(_)) = failure($0).ownerError else {
                    return XCTFail("expected malformed authoritative ID failure")
                }
            }
            XCTAssertEqual(api.requests.map(\.method), ["workspace.create"])
        }
    }

    func testFreshSnapshotWrongParentFailsVerification() throws {
        try withTemporaryDirectory { directory in
            let project = makeProject(directory: directory.path)
            let normalizedDirectory = try project.normalized().workingDirectory
            let wrong = snapshot(
                directory: normalizedDirectory, workspaceID: "w1", workspaceLabel: project.name,
                tabs: [("t1", "other-workspace", project.tabs[0].name)],
                panes: [("p1", "w1", "t1", nil)]
            )
            let api = MaterializationAPI(
                results: [workspaceResult("w1", "t1", "p1")],
                snapshots: [wrong, wrong]
            )

            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: api, connectionStatus: { _ in .current }
            ).materialize(project, on: localConnection())) { error in
                guard case .verification(let issues) = failure(error).ownerError else {
                    return XCTFail("expected verification failure")
                }
                XCTAssertTrue(issues.contains(.tabWrongWorkspace(recipeTabID: project.tabs[0].id, runtimeTabID: "t1", expectedWorkspaceID: "w1", actualWorkspaceID: "other-workspace")))
                XCTAssertNil(failure(error).partialResult.lastVerifiedSnapshot)
            }
            XCTAssertEqual(api.requests.map(\.method), ["workspace.create"])
        }
    }

    func testFreshSnapshotsMissingPaneOrLayoutFailVerification() throws {
        try withTemporaryDirectory { directory in
            var project = makeProject(directory: directory.path)
            project.tabs[0].panes[0].label = nil
            let normalizedDirectory = try project.normalized().workingDirectory
            let missingPane = snapshot(
                directory: normalizedDirectory, workspaceID: "w1", workspaceLabel: project.name,
                tabs: [("t1", "w1", project.tabs[0].name)], panes: [], layouts: []
            )
            let missingPaneAPI = MaterializationAPI(
                results: [workspaceResult("w1", "t1", "p1")],
                snapshots: [missingPane, missingPane]
            )
            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: missingPaneAPI, connectionStatus: { _ in .current }
            ).materialize(project, on: localConnection())) { error in
                guard case .verification(let issues) = failure(error).ownerError else {
                    return XCTFail("expected missing pane verification failure")
                }
                XCTAssertTrue(issues.contains(.missingPane(
                    recipePaneID: project.tabs[0].panes[0].id, runtimePaneID: "p1"
                )))
            }

            let valid = snapshotsForMaterialization(
                directory: normalizedDirectory, project: project,
                workspaceID: "w1", runtimeTabs: ["t1"], runtimePanes: ["p1"], finalCopies: 1
            )[0]
            let missingLayout = HerdrSnapshot(
                version: valid.version, protocolVersion: valid.protocolVersion,
                focusedWorkspaceID: valid.focusedWorkspaceID, focusedTabID: valid.focusedTabID,
                focusedPaneID: valid.focusedPaneID, workspaces: valid.workspaces,
                tabs: valid.tabs, panes: valid.panes, layouts: [], agents: valid.agents
            )
            let missingLayoutAPI = MaterializationAPI(
                results: [
                    workspaceResult("w1", "t1", "p1"),
                    infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t1"),
                ],
                snapshots: [valid, missingLayout, missingLayout]
            )
            XCTAssertThrowsError(try BessieProjectMaterializer(
                api: missingLayoutAPI, connectionStatus: { _ in .current }
            ).materialize(project, on: localConnection())) { error in
                guard case .verification(let issues) = failure(error).ownerError else {
                    return XCTFail("expected missing layout verification failure")
                }
                XCTAssertTrue(issues.contains(.tabLayoutUnavailable(
                    recipeTabID: project.tabs[0].id, runtimeTabID: "t1"
                )))
            }
        }
    }

    func testFreshSnapshotWrongSplitDirectionAndRatioFailTopologyVerification() throws {
        try withTemporaryDirectory { directory in
            let root = UUID(), split = UUID()
            let project = makeProject(directory: directory.path, tabs: [
                .init(name: "One", panes: [
                    .init(id: root, placement: .root),
                    .init(id: split, placement: .split(fromPaneID: root, direction: .down, ratio: 0.35)),
                ]),
            ])
            let normalizedDirectory = try project.normalized().workingDirectory
            for placement in [(0, SplitDirection.right, 0.35), (0, .down, 0.65), (0, .down, 0.509)] {
                let wrongLayout = testLayout(
                    workspaceID: "w1", tabID: "t1", panes: ["p1", "p2"],
                    placements: [nil, placement]
                )
                let wrongSnapshot = snapshot(
                    directory: normalizedDirectory, workspaceID: "w1", workspaceLabel: project.name,
                    tabs: [("t1", "w1", project.tabs[0].name)],
                    panes: [("p1", "w1", "t1", nil), ("p2", "w1", "t1", nil)],
                    layouts: [wrongLayout]
                )
                let api = MaterializationAPI(
                    results: [
                        workspaceResult("w1", "t1", "p1"),
                        infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t1"),
                        paneResult("p2"),
                    ],
                    snapshots: Array(repeating: wrongSnapshot, count: 4)
                )

                XCTAssertThrowsError(try BessieProjectMaterializer(
                    api: api, connectionStatus: { _ in .current }
                ).materialize(project, on: localConnection())) { error in
                    guard case .verification(let issues) = failure(error).ownerError else {
                        return XCTFail("expected topology verification failure")
                    }
                    XCTAssertTrue(issues.contains(.tabTopologyMismatch(
                        recipeTabID: project.tabs[0].id, runtimeTabID: "t1"
                    )))
                    XCTAssertNotNil(failure(error).partialResult.lastVerifiedSnapshot)
                }
                XCTAssertFalse(api.requests.contains { $0.method.contains("close") })
            }
        }
    }

    func testNestedOddCellLayoutUsesHerdrRoundedSplitBoundaries() throws {
        try withTemporaryDirectory { directory in
            let root = UUID(), second = UUID(), nested = UUID()
            let project = makeProject(directory: directory.path, tabs: [
                .init(name: "One", panes: [
                    .init(id: root, placement: .root),
                    .init(id: second, placement: .split(fromPaneID: root, direction: .right, ratio: 0.5)),
                    .init(id: nested, placement: .split(fromPaneID: root, direction: .right, ratio: 0.5)),
                ]),
            ])
            let normalizedDirectory = try project.normalized().workingDirectory
            func rect(_ x: Int, _ width: Int) -> JSONValue {
                LayoutRect(x: x, y: 0, width: width, height: 10).json
            }
            let fiveColumnLayout: JSONValue = .object([
                "workspace_id": .string("w1"), "tab_id": .string("t1"),
                "panes": .array([
                    .object(["pane_id": .string("p1"), "focused": .bool(true), "rect": rect(0, 2)]),
                    .object(["pane_id": .string("p3"), "focused": .bool(false), "rect": rect(2, 1)]),
                    .object(["pane_id": .string("p2"), "focused": .bool(false), "rect": rect(3, 2)]),
                ]),
                "splits": .array([
                    .object([
                        "id": .string("split_root"), "direction": .string("right"),
                        "ratio": .number(0.5), "rect": rect(0, 5),
                    ]),
                    .object([
                        "id": .string("split_0"), "direction": .string("right"),
                        "ratio": .number(0.5), "rect": rect(0, 3),
                    ]),
                ]),
            ])
            let authoritative = snapshot(
                directory: normalizedDirectory, workspaceID: "w1", workspaceLabel: project.name,
                tabs: [("t1", "w1", project.tabs[0].name)],
                panes: [("p1", "w1", "t1", nil), ("p2", "w1", "t1", nil), ("p3", "w1", "t1", nil)],
                layouts: [fiveColumnLayout]
            )
            let api = MaterializationAPI(
                results: [
                    workspaceResult("w1", "t1", "p1"),
                    infoResult(type: "tab_info", key: "tab", idKey: "tab_id", id: "t1"),
                    paneResult("p2"), paneResult("p3"),
                ],
                snapshots: Array(repeating: authoritative, count: 5)
            )

            let result = try BessieProjectMaterializer(
                api: api, connectionStatus: { _ in .current }
            ).materialize(project, on: localConnection())
            XCTAssertEqual(result.paneIDsByRecipeID, [root: "p1", second: "p2", nested: "p3"])
        }
    }
}

private final class MaterializationAPI: BessieProjectMaterializationAPI, @unchecked Sendable {
    struct Request { let method: String; let params: [String: JSONValue] }
    struct InjectedFailure { let method: String; let error: HerdrClientError }

    private var results: [JSONValue]
    private var snapshots: [HerdrSnapshot]
    private let failure: InjectedFailure?
    private let afterRequest: ((Request) -> Void)?
    private let afterSnapshot: ((Int) -> Void)?
    private(set) var requests: [Request] = []
    private var snapshotCount = 0
    let socketPath: String
    private let identity: HerdrServerIdentity

    init(
        results: [JSONValue] = [],
        snapshots: [HerdrSnapshot] = [],
        failure: InjectedFailure? = nil,
        afterRequest: ((Request) -> Void)? = nil,
        afterSnapshot: ((Int) -> Void)? = nil,
        socketPath: String = "/tmp/bessie-materializer-fixture.sock",
        identity: HerdrServerIdentity = .init(version: "0.8.0", protocolVersion: 19)
    ) {
        self.results = results
        self.snapshots = snapshots
        self.failure = failure
        self.afterRequest = afterRequest
        self.afterSnapshot = afterSnapshot
        self.socketPath = socketPath
        self.identity = identity
    }

    func ping() throws -> HerdrServerIdentity { identity }

    func request(method: String, params: [String: JSONValue]) throws -> JSONValue {
        let request = Request(method: method, params: params)
        requests.append(request)
        afterRequest?(request)
        if failure?.method == method { throw failure!.error }
        guard !results.isEmpty else { throw HerdrClientError.unexpectedResponse("missing fake result for \(method)") }
        let result = results.removeFirst()
        guard method == "pane.read", case .string(let paneID)? = params["pane_id"],
              case .object(var resultObject) = result,
              case .object(var readObject)? = resultObject["read"] else { return result }
        readObject["pane_id"] = .string(paneID)
        resultObject["read"] = .object(readObject)
        return .object(resultObject)
    }

    func snapshot() throws -> HerdrSnapshot {
        guard !snapshots.isEmpty else { throw HerdrClientError.unexpectedResponse("missing fake snapshot") }
        let snapshot = snapshots.removeFirst()
        snapshotCount += 1
        afterSnapshot?(snapshotCount)
        return snapshot
    }
}

private final class CancellationSwitch: @unchecked Sendable { var value = false }
private final class ConnectionSwitch: @unchecked Sendable { var value = true }
private final class GenerationBox: @unchecked Sendable {
    var value: UUID?
    init(_ value: UUID?) { self.value = value }
}
private final class MaterializationClock: @unchecked Sendable {
    private var value = Date(timeIntervalSinceReferenceDate: 0)
    lazy var now: @Sendable () -> Date = { [self] in value }
    lazy var wait: @Sendable (TimeInterval) -> Void = { [self] in value = value.addingTimeInterval($0) }
}

private extension BessieProjectMaterializationTests {
    func failure(_ error: Error) -> BessieProjectMaterializationFailure {
        guard let failure = error as? BessieProjectMaterializationFailure else {
            XCTFail("expected BessieProjectMaterializationFailure, got \(error)")
            fatalError("unexpected error")
        }
        return failure
    }

    func localConnection(
        kind: BessieConnectionKind = .local,
        identity: HerdrServerIdentity = .init(version: "0.8.0", protocolVersion: 19),
        generation: UUID = UUID()
    ) -> BessieProjectMaterializationConnection {
        .init(
            definition: .init(
                id: "fixture", name: "Fixture", kind: kind,
                sshHost: kind == .ssh ? "fixture.test" : nil,
                session: "isolated"
            ),
            socketPath: "/tmp/bessie-materializer-fixture.sock",
            generation: generation,
            identity: identity
        )
    }

    func makeProject(
        directory: String,
        command: String? = nil,
        tabs: [BessieProjectTab]? = nil
    ) -> BessieProject {
        BessieProject(
            name: "duplicate",
            targetConnectionID: "fixture",
            workingDirectory: directory,
            tabs: tabs ?? [.init(name: "duplicate", panes: [.init(label: "duplicate", command: command, placement: .root)])]
        )
    }

    func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}

private func workspaceResult(_ workspaceID: String, _ tabID: String, _ paneID: String) -> JSONValue {
    .object([
        "type": .string("workspace_created"),
        "workspace": .object(["workspace_id": .string(workspaceID)]),
        "tab": .object(["tab_id": .string(tabID)]),
        "root_pane": .object(["pane_id": .string(paneID)]),
    ])
}

private func tabResult(_ tabID: String, _ paneID: String) -> JSONValue {
    .object([
        "type": .string("tab_created"),
        "tab": .object(["tab_id": .string(tabID)]),
        "root_pane": .object(["pane_id": .string(paneID)]),
    ])
}

private func paneResult(_ paneID: String) -> JSONValue {
    infoResult(type: "pane_info", key: "pane", idKey: "pane_id", id: paneID)
}

private func infoResult(type: String, key: String, idKey: String, id: String) -> JSONValue {
    .object(["type": .string(type), key: .object([idKey: .string(id)])])
}

private func paneRead(_ text: String) -> JSONValue {
    .object([
        "type": .string("pane_read"),
        "read": .object(["pane_id": .string("runtime-pane"), "text": .string(text)]),
    ])
}

private func ok() -> JSONValue { .object(["type": .string("ok")]) }

private func snapshotsForMaterialization(
    directory: String,
    project: BessieProject,
    workspaceID: String = "runtime-workspace",
    runtimeTabs: [String],
    runtimePanes: [String],
    paneDirectories: [String]? = nil,
    finalCopies: Int = 10
) -> [HerdrSnapshot] {
    var runningPaneOffset = 0
    let layouts = runtimeTabs.enumerated().map { tabIndex, runtimeTabID -> JSONValue in
        let tab = project.tabs[tabIndex]
        let availableCount = min(tab.panes.count, runtimePanes.count - runningPaneOffset)
        let runtimePaneIDs = Array(runtimePanes[runningPaneOffset..<(runningPaneOffset + availableCount)])
        runningPaneOffset += availableCount
        let availablePanes = Array(tab.panes.prefix(availableCount))
        let recipeIndex = Dictionary(uniqueKeysWithValues: availablePanes.enumerated().map { ($0.element.id, $0.offset) })
        let placements = availablePanes.map { pane -> (parentIndex: Int, direction: SplitDirection, ratio: Double)? in
            guard case .split(let parentID, let direction, let ratio) = pane.placement,
                  let parentIndex = recipeIndex[parentID] else { return nil }
            return (parentIndex, direction, ratio)
        }
        return testLayout(
            workspaceID: workspaceID,
            tabID: runtimeTabID,
            panes: runtimePaneIDs,
            placements: placements
        )
    }
    let complete = snapshot(
        directory: directory,
        workspaceID: workspaceID,
        workspaceLabel: project.name,
        tabs: runtimeTabs.enumerated().map { ($0.element, workspaceID, project.tabs[$0.offset].name) },
        panes: runtimePanes.enumerated().map { offset, id in
            var running = 0
            for (tabIndex, tab) in project.tabs.enumerated() {
                if offset < running + tab.panes.count {
                    return (id, workspaceID, runtimeTabs[tabIndex], tab.panes[offset - running].label)
                }
                running += tab.panes.count
            }
            return (id, workspaceID, runtimeTabs.last!, nil)
        },
        paneDirectories: paneDirectories,
        layouts: layouts
    )
    return Array(repeating: complete, count: finalCopies)
}

private func snapshot(
    directory: String,
    workspaceID: String,
    workspaceLabel: String,
    tabs: [(String, String, String)],
    panes: [(String, String, String, String?)],
    paneDirectories: [String]? = nil,
    layouts suppliedLayouts: [JSONValue]? = nil
) -> HerdrSnapshot {
    let layouts = suppliedLayouts ?? tabs.map { tab -> JSONValue in
        let tabPanes = panes.filter { $0.2 == tab.0 }
        return testLayout(
            workspaceID: tab.1,
            tabID: tab.0,
            panes: tabPanes.map(\.0),
            placements: Array(tabPanes.indices).map { index in
                index == 0 ? nil : (parentIndex: max(0, index - 1), direction: SplitDirection.right, ratio: 0.5)
            }
        )
    }
    return HerdrSnapshot(
        version: "0.8.0",
        protocolVersion: 19,
        focusedWorkspaceID: workspaceID,
        focusedTabID: tabs.first?.0,
        focusedPaneID: panes.first?.0,
        workspaces: [.object(["workspace_id": .string(workspaceID), "label": .string(workspaceLabel)])],
        tabs: tabs.map { .object(["tab_id": .string($0.0), "workspace_id": .string($0.1), "label": .string($0.2)]) },
        panes: panes.enumerated().map { index, pane in
            .object([
                "pane_id": .string(pane.0), "workspace_id": .string(pane.1), "tab_id": .string(pane.2),
                "label": pane.3.map(JSONValue.string) ?? .null,
                "cwd": .string(paneDirectories?[index] ?? directory),
            ])
        },
        layouts: layouts,
        agents: []
    )
}

private indirect enum TestLayoutNode {
    case pane(Int)
    case split(SplitDirection, Double, TestLayoutNode, TestLayoutNode)

    mutating func replace(_ target: Int, with replacement: TestLayoutNode) -> Bool {
        switch self {
        case .pane(let index) where index == target:
            self = replacement
            return true
        case .pane:
            return false
        case .split(let direction, let ratio, var first, var second):
            if first.replace(target, with: replacement) {
                self = .split(direction, ratio, first, second)
                return true
            }
            if second.replace(target, with: replacement) {
                self = .split(direction, ratio, first, second)
                return true
            }
            return false
        }
    }
}

private func testLayout(
    workspaceID: String,
    tabID: String,
    panes: [String],
    placements: [(parentIndex: Int, direction: SplitDirection, ratio: Double)?]
) -> JSONValue {
    var root = TestLayoutNode.pane(0)
    for index in panes.indices.dropFirst() {
        let placement = placements[index]!
        _ = root.replace(
            placement.parentIndex,
            with: .split(placement.direction, placement.ratio, .pane(placement.parentIndex), .pane(index))
        )
    }
    var paneValues: [JSONValue] = []
    var splitValues: [JSONValue] = []
    func render(_ node: TestLayoutNode, path: [Bool], rect: LayoutRect) {
        switch node {
        case .pane(let index):
            paneValues.append(.object([
                "pane_id": .string(panes[index]), "focused": .bool(index == 0), "rect": rect.json,
            ]))
        case .split(let direction, let ratio, let first, let second):
            let id = path.isEmpty ? "split_root" : "split_\(path.map { $0 ? "1" : "0" }.joined())"
            splitValues.append(.object([
                "id": .string(id), "direction": .string(direction.rawValue),
                "ratio": .number(ratio), "rect": rect.json,
            ]))
            if direction == .right {
                let firstWidth = Int((Double(rect.width) * ratio).rounded())
                render(first, path: path + [false], rect: .init(x: rect.x, y: rect.y, width: firstWidth, height: rect.height))
                render(second, path: path + [true], rect: .init(x: rect.x + firstWidth, y: rect.y, width: rect.width - firstWidth, height: rect.height))
            } else {
                let firstHeight = Int((Double(rect.height) * ratio).rounded())
                render(first, path: path + [false], rect: .init(x: rect.x, y: rect.y, width: rect.width, height: firstHeight))
                render(second, path: path + [true], rect: .init(x: rect.x, y: rect.y + firstHeight, width: rect.width, height: rect.height - firstHeight))
            }
        }
    }
    render(root, path: [], rect: .init(x: 0, y: 0, width: 10_000, height: 10_000))
    return .object([
        "workspace_id": .string(workspaceID), "tab_id": .string(tabID),
        "panes": .array(paneValues), "splits": .array(splitValues),
    ])
}

private extension LayoutRect {
    var json: JSONValue {
        .object([
            "x": .number(Double(x)), "y": .number(Double(y)),
            "width": .number(Double(width)), "height": .number(Double(height)),
        ])
    }
}
