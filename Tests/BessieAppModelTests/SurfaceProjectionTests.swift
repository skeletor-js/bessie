import Combine
import Foundation
import XCTest
@testable import BessieApp
@testable import BessieCore

final class SurfaceProjectionTests: XCTestCase {
    @MainActor
    func testProductShortcutsDoNotRequireTerminalResponder() {
        for command in [
            BessieShortcutCommand.projectsPicker, .previousPane, .nextPane,
            .previousRailPane, .nextRailPane, .splitPane(.right), .splitPane(.down),
            .closePane, .toggleSidebar, .closeTab, .showCommandPalette, .newTab,
        ] {
            XCTAssertFalse(
                BessieKeyboardShortcutCoordinator.requiresWorkspaceTerminalResponder(command),
                "\(command) must not depend on terminal first-responder"
            )
        }
    }

    @MainActor
    func testTopologyShortcutsYieldOnlyToTextEditing() {
        for command in [
            BessieShortcutCommand.projectsPicker, .previousPane, .nextPane,
            .previousRailPane, .nextRailPane, .splitPane(.right), .splitPane(.down),
            .closePane, .toggleSidebar, .newTab, .closeTab, .newWorkspace,
        ] {
            XCTAssertTrue(
                BessieKeyboardShortcutCoordinator.blocksDuringTextEditing(command),
                "\(command) should yield while typing in a text field"
            )
            XCTAssertTrue(BessieKeyboardShortcutCoordinator.shouldRoute(
                command,
                hasMarkedText: false,
                firstResponderIsEditableText: false
            ))
            XCTAssertFalse(BessieKeyboardShortcutCoordinator.shouldRoute(
                command,
                hasMarkedText: false,
                firstResponderIsEditableText: true
            ))
        }
        XCTAssertFalse(BessieKeyboardShortcutCoordinator.blocksDuringTextEditing(.showCommandPalette))
        XCTAssertTrue(BessieKeyboardShortcutCoordinator.shouldRoute(
            .showCommandPalette,
            hasMarkedText: false,
            firstResponderIsEditableText: true
        ))
    }

    @MainActor
    func testEscapeOnlyExitsWhileZenIsActive() {
        XCTAssertTrue(BessieKeyboardShortcutCoordinator.shouldExitZen(keyCode: 53, isZenActive: true))
        XCTAssertFalse(BessieKeyboardShortcutCoordinator.shouldExitZen(keyCode: 53, isZenActive: false))
        XCTAssertFalse(BessieKeyboardShortcutCoordinator.shouldExitZen(keyCode: 36, isZenActive: true))
    }

    @MainActor
    func testPalettePolicySuppressesShellMutationAndKeepsExplicitPassThroughs() {
        for (character, option, shift) in [
            ("n", true, false), ("z", false, true), ("d", false, false),
            (",", false, false), ("w", false, false),
        ] {
            XCTAssertEqual(palettePolicy(character, command: true, option: option, shift: shift), .consume)
        }
        for character in ["a", "c", "v", "x", "z", "q", "h", "m"] {
            XCTAssertEqual(palettePolicy(character, command: true), .passThrough)
        }
        for character in ["a", "c", "x", "z"] {
            XCTAssertEqual(
                palettePolicy(character, command: true, isSearchFocused: false),
                .consume
            )
        }
        XCTAssertEqual(
            palettePolicy("v", command: true, isSearchFocused: false, pasteboardText: "pasted"),
            .buffer("pasted")
        )
        for character in ["q", "h", "m"] {
            XCTAssertEqual(
                palettePolicy(character, command: true, isSearchFocused: false),
                .passThrough
            )
        }
        XCTAssertEqual(
            palettePolicy("p", command: true, shift: true),
            .action(.dismiss)
        )
    }

    @MainActor
    func testPalettePolicyHonorsIMEAndBuffersUntilSearchActuallyHasFocus() {
        XCTAssertEqual(
            BessieKeyboardShortcutCoordinator.paletteEventPolicy(
                keyCode: CommandPaletteKeyboard.returnKey,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                command: false,
                option: false,
                control: false,
                shift: false,
                hasMarkedText: true,
                isSearchFocused: true,
                pasteboardText: nil
            ),
            .passThrough
        )
        XCTAssertEqual(
            BessieKeyboardShortcutCoordinator.paletteEventPolicy(
                keyCode: 13,
                characters: "w",
                charactersIgnoringModifiers: "w",
                command: true,
                option: false,
                control: false,
                shift: false,
                hasMarkedText: true,
                isSearchFocused: true,
                pasteboardText: nil
            ),
            .consume
        )
        XCTAssertEqual(
            BessieKeyboardShortcutCoordinator.paletteEventPolicy(
                keyCode: CommandPaletteKeyboard.downArrow,
                characters: nil,
                charactersIgnoringModifiers: nil,
                command: false,
                option: false,
                control: false,
                shift: false,
                hasMarkedText: true,
                isSearchFocused: true,
                pasteboardText: nil
            ),
            .passThrough
        )
        XCTAssertEqual(
            BessieKeyboardShortcutCoordinator.paletteEventPolicy(
                keyCode: CommandPaletteKeyboard.escape,
                characters: nil,
                charactersIgnoringModifiers: nil,
                command: false,
                option: false,
                control: false,
                shift: false,
                hasMarkedText: false,
                isSearchFocused: true,
                pasteboardText: nil
            ),
            .action(.dismiss)
        )
        XCTAssertEqual(palettePolicy("x", isSearchFocused: false), .buffer("x"))
        XCTAssertEqual(palettePolicy("x", isSearchFocused: true), .passThrough)
    }

    @MainActor
    private func palettePolicy(
        _ character: String,
        command: Bool = false,
        option: Bool = false,
        shift: Bool = false,
        isSearchFocused: Bool = true,
        pasteboardText: String? = nil
    ) -> BessieKeyboardShortcutCoordinator.PaletteEventPolicy {
        BessieKeyboardShortcutCoordinator.paletteEventPolicy(
            keyCode: 0,
            characters: character,
            charactersIgnoringModifiers: character,
            command: command,
            option: option,
            control: false,
            shift: shift,
            hasMarkedText: false,
            isSearchFocused: isSearchFocused,
            pasteboardText: pasteboardText
        )
    }

    func testTerminalSurfaceReattachmentKeepsTheExistingHerdrStream() {
        var lifecycle = TerminalSurfaceStreamLifecycle()

        XCTAssertEqual(lifecycle.attach(), .startStream)
        lifecycle.detach()
        XCTAssertEqual(lifecycle.attach(), .keepStream)
    }

    @MainActor
    func testUnfocusedTerminalDoesNotConsumeTerminalShortcuts() throws {
        let controller = PaneTerminalController(
            paneID: "p1",
            endpoint: .init(connectionID: "test", executablePath: "/usr/bin/false", socketPath: "/tmp/missing")
        )
        var operations: [TerminalInputOperation] = []
        controller.terminalView.sendOperation = { operations.append($0) }
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "c",
            charactersIgnoringModifiers: "c",
            isARepeat: false,
            keyCode: 8
        ))

        XCTAssertFalse(controller.terminalView.performKeyEquivalent(with: event))
        XCTAssertTrue(operations.isEmpty)
        controller.release()
    }

    @MainActor
    func testWarmTerminalStoreRetainsControllerIdentityAcrossSwitches() {
        let store = makeWarmStore(capacity: 1)

        store.reconcile(presentedPaneIDs: ["p1"], availablePaneIDs: ["p1", "p2"])
        let original = store.controllers["p1"]
        store.reconcile(presentedPaneIDs: ["p2"], availablePaneIDs: ["p1", "p2"])
        store.reconcile(presentedPaneIDs: ["p1"], availablePaneIDs: ["p1", "p2"])

        XCTAssertTrue(store.controllers["p1"] === original)
        XCTAssertEqual(store.presentedPaneIDs, ["p1"])
        XCTAssertEqual(store.warmPaneIDs, ["p2"])
    }

    @MainActor
    func testZenPresentationReusesTheFocusedTerminalController() {
        let store = makeWarmStore(capacity: 1)

        store.reconcile(presentedPaneIDs: ["p1"], availablePaneIDs: ["p1", "p2"])
        let workspaceController = store.controllers["p1"]
        store.reconcile(presentedPaneIDs: ["p1"], availablePaneIDs: ["p1", "p2"])
        let zenController = store.controllers["p1"]
        store.reconcile(presentedPaneIDs: ["p1"], availablePaneIDs: ["p1", "p2"])

        XCTAssertTrue(zenController === workspaceController)
        XCTAssertTrue(store.controllers["p1"] === workspaceController)
        XCTAssertEqual(store.presentedPaneIDs, ["p1"])
    }

    @MainActor
    func testWarmTerminalStoreBoundsEvictionAndNeverEvictsPresentedControllers() {
        let store = makeWarmStore(capacity: 1)

        store.reconcile(presentedPaneIDs: ["p1", "p2"], availablePaneIDs: ["p1", "p2", "p3"])
        let first = store.controllers["p1"]
        let second = store.controllers["p2"]
        store.reconcile(presentedPaneIDs: ["p3"], availablePaneIDs: ["p1", "p2", "p3"])

        XCTAssertNotNil(store.controllers["p3"])
        XCTAssertTrue(first?.released == true)
        XCTAssertFalse(second?.released == true)
        XCTAssertEqual(Set(store.controllers.keys), ["p2", "p3"])
    }

    @MainActor
    func testWarmTerminalStorePrecreatesRequestedPanesWithinCapacity() {
        let store = makeWarmStore(capacity: 2)

        store.reconcile(
            presentedPaneIDs: ["p1"],
            availablePaneIDs: ["p1", "p2", "p3", "p4"],
            prewarmPaneIDs: ["p2", "p3", "p4"]
        )

        XCTAssertEqual(Set(store.controllers.keys), ["p1", "p2", "p3"])
        XCTAssertEqual(store.presentedPaneIDs, ["p1"])
        XCTAssertEqual(store.warmPaneIDs, ["p2", "p3"])
    }

    @MainActor
    func testWarmTerminalStoreDoesNotDuplicateLeavingPaneWhenItIsAlsoPrewarmed() {
        let store = makeWarmStore(capacity: 2)
        store.reconcile(presentedPaneIDs: ["p1"], availablePaneIDs: ["p1", "p2", "p3"])
        let original = store.controllers["p1"]

        store.reconcile(
            presentedPaneIDs: ["p2"],
            availablePaneIDs: ["p1", "p2", "p3"],
            prewarmPaneIDs: ["p1", "p3"]
        )

        XCTAssertEqual(store.warmPaneIDs, ["p1", "p3"])
        XCTAssertTrue(store.controllers["p1"] === original)
        XCTAssertEqual(Set(store.controllers.keys), ["p1", "p2", "p3"])
    }

    @MainActor
    func testRegistryPrewarmsThenParksHiddenSurfaceWithoutTreatingItAsInteractive() {
        let registry = TerminalControllerRegistry()
        let endpoint = HerdrTerminalEndpoint(
            connectionID: "test",
            executablePath: "/usr/bin/false",
            socketPath: "/tmp/missing"
        )

        registry.reconcile(
            presentedPaneIDs: ["p1"],
            availablePaneIDs: ["p1", "p2"],
            prewarmPaneIDs: ["p2"],
            endpoint: endpoint
        )

        let warm = registry.controllers["p2"]
        XCTAssertNotNil(warm)
        XCTAssertTrue(warm?.hasStartedStream == true)
        XCTAssertNil(warm?.terminalView.window, "Hidden warm surfaces must not keep libghostty display links active")
        XCTAssertNil(warm?.terminalView.superview)

        registry.reconcile(
            presentedPaneIDs: ["p1"],
            availablePaneIDs: ["p1", "p2"],
            prewarmPaneIDs: ["p2"],
            endpoint: endpoint
        )
        XCTAssertTrue(registry.controllers["p2"] === warm)
        XCTAssertNil(warm?.terminalView.window, "An already-started warm stream must not be reattached offscreen")

        registry.reconcile(
            presentedPaneIDs: ["p2"],
            availablePaneIDs: ["p1", "p2"],
            prewarmPaneIDs: ["p1"],
            endpoint: endpoint
        )
        XCTAssertTrue(registry.controllers["p2"] === warm)
        XCTAssertTrue(registry.controllers["p2"]?.session === warm?.session)
        XCTAssertTrue(registry.controllers["p2"]?.terminalView === warm?.terminalView)
        registry.recordSwitchRequested(paneID: "p2")
        registry.focusWhenPresented(paneID: "p2")
        XCTAssertFalse(warm?.terminalView.window?.firstResponder === warm?.terminalView)
        registry.releaseAll()
    }

    @MainActor
    func testRegistryPrewarmsReplacementControllerWithSamePaneID() {
        let registry = TerminalControllerRegistry()
        let firstEndpoint = HerdrTerminalEndpoint(
            connectionID: "first",
            executablePath: "/usr/bin/false",
            socketPath: "/tmp/missing-first"
        )
        registry.reconcile(
            presentedPaneIDs: [],
            availablePaneIDs: ["p1"],
            prewarmPaneIDs: ["p1"],
            endpoint: firstEndpoint
        )
        let first = registry.controllers["p1"]

        registry.reconcile(
            presentedPaneIDs: [],
            availablePaneIDs: ["p1"],
            prewarmPaneIDs: ["p1"],
            endpoint: HerdrTerminalEndpoint(
                connectionID: "second",
                executablePath: "/usr/bin/false",
                socketPath: "/tmp/missing-second"
            )
        )

        let replacement = registry.controllers["p1"]
        XCTAssertNotNil(first)
        XCTAssertNotNil(replacement)
        XCTAssertFalse(replacement === first)
        XCTAssertTrue(replacement?.hasStartedStream == true)
        XCTAssertNil(replacement?.terminalView.window)
        registry.releaseAll()
    }

    @MainActor
    func testWarmTerminalStoreImmediatelyReleasesAuthoritativelyRemovedPane() {
        let store = makeWarmStore(capacity: 2)
        store.reconcile(presentedPaneIDs: ["p1"], availablePaneIDs: ["p1", "p2"])
        store.reconcile(presentedPaneIDs: ["p2"], availablePaneIDs: ["p1", "p2"])
        let warm = store.controllers["p1"]

        store.reconcile(presentedPaneIDs: ["p2"], availablePaneIDs: ["p2"])

        XCTAssertTrue(warm?.released == true)
        XCTAssertNil(store.controllers["p1"])
        XCTAssertEqual(store.presentedPaneIDs, ["p2"])
    }

    @MainActor
    func testWarmTerminalStoreReleaseAllIsIdempotent() {
        let released = NSMutableArray()
        let store = WarmTerminalControllerStore<TestWarmController>(
            warmCapacity: 2,
            create: { TestWarmController(id: $0) },
            release: { controller in
                controller.release()
                released.add(controller.id)
            }
        )
        store.reconcile(presentedPaneIDs: ["p1", "p2"], availablePaneIDs: ["p1", "p2"])

        store.removeAll()
        store.removeAll()

        XCTAssertEqual(released.count, 2)
        XCTAssertTrue(store.controllers.isEmpty)
        XCTAssertTrue(store.presentedPaneIDs.isEmpty)
        XCTAssertTrue(store.warmPaneIDs.isEmpty)
    }

    @MainActor
    func testTerminalPresentationTrackerRunsOncePerAttachmentAndSize() {
        var tracker = TerminalSurfacePresentationTracker()
        let first = UUID()
        let second = UUID()

        XCTAssertFalse(tracker.requiresFullPresentation(
            attachmentToken: first,
            width: 0,
            height: 60
        ))
        XCTAssertTrue(tracker.requiresFullPresentation(
            attachmentToken: first,
            width: 120,
            height: 60
        ))
        XCTAssertFalse(tracker.requiresFullPresentation(
            attachmentToken: first,
            width: 120,
            height: 60
        ), "Repeated SwiftUI layout at the same size must not refit or resize the terminal")
        XCTAssertTrue(tracker.requiresFullPresentation(
            attachmentToken: first,
            width: 121,
            height: 60
        ), "A real size change needs one full presentation")
        XCTAssertTrue(tracker.requiresFullPresentation(
            attachmentToken: second,
            width: 121,
            height: 60
        ), "A new attachment needs one full presentation even at the same size")
        XCTAssertFalse(tracker.requiresFullPresentation(
            attachmentToken: second,
            width: 121,
            height: 60
        ))

        tracker.reset()
        XCTAssertTrue(tracker.requiresFullPresentation(
            attachmentToken: second,
            width: 121,
            height: 60
        ))
    }

    @MainActor
    func testOldTerminalHostCannotDetachSurfaceFromNewHost() {
        let controller = PaneTerminalController(
            paneID: "p1",
            endpoint: .init(connectionID: "test", executablePath: "/usr/bin/false", socketPath: "/tmp/missing")
        )
        let first = TerminalSurfaceHostView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
        let second = TerminalSurfaceHostView(frame: NSRect(x: 0, y: 0, width: 80, height: 40))
        first.attach(controller: controller, fontSize: 13, requestFocus: {}, responderChanged: { _ in })
        let terminalView = controller.terminalView
        let session = controller.session
        second.attach(controller: controller, fontSize: 14, requestFocus: {}, responderChanged: { _ in })

        first.detach()

        XCTAssertTrue(controller.terminalView.superview === second)
        XCTAssertTrue(second.paneController === controller)
        XCTAssertTrue(controller.terminalView === terminalView)
        XCTAssertTrue(controller.session === session)
        XCTAssertFalse(controller.hasStartedStream, "Herdr output must wait for libghostty's native surface attachment")
        controller.release()
    }

    @MainActor
    func testHostControllerSwapParksPreviousTerminalAndShowsOnlyNewSurface() {
        // SwiftUI reuses NSViewRepresentable hosts across pane/tab switches. If attach
        // only points at the new controller without parking the old terminal, the prior
        // surface stays as a host subview and the UI looks stuck until a full destination
        // teardown (e.g. Projects) dismantles every host.
        let firstController = PaneTerminalController(
            paneID: "p1",
            endpoint: .init(connectionID: "test", executablePath: "/usr/bin/false", socketPath: "/tmp/missing")
        )
        let secondController = PaneTerminalController(
            paneID: "p2",
            endpoint: .init(connectionID: "test", executablePath: "/usr/bin/false", socketPath: "/tmp/missing")
        )
        let host = TerminalSurfaceHostView(frame: NSRect(x: 0, y: 0, width: 120, height: 60))
        host.attach(controller: firstController, fontSize: 13, requestFocus: {}, responderChanged: { _ in })
        let firstTerminal = firstController.terminalView

        host.attach(controller: secondController, fontSize: 13, requestFocus: {}, responderChanged: { _ in })

        XCTAssertTrue(host.paneController === secondController)
        XCTAssertTrue(secondController.terminalView.superview === host)
        XCTAssertNil(firstTerminal.superview, "Previous pane terminal must leave the reused host")
        XCTAssertEqual(host.subviews.count, 1)
        XCTAssertTrue(host.subviews.first === secondController.terminalView)
        // isSurfacePresented also requires a live window; unit tests only assert hierarchy.
        XCTAssertFalse(firstTerminal.superview is TerminalSurfaceHostView)
        XCTAssertTrue(secondController.terminalView.superview is TerminalSurfaceHostView)

        firstController.release()
        secondController.release()
    }

    @MainActor
    func testTerminalRegistryDoesNotRepublishUnchangedControllers() {
        XCTAssertEqual(TerminalControllerRegistry.defaultWarmCapacity, 12)
        let registry = TerminalControllerRegistry()
        let endpoint = HerdrTerminalEndpoint(
            connectionID: "test",
            executablePath: "/usr/bin/false",
            socketPath: "/tmp/missing"
        )
        var publications = 0
        let subscription = registry.objectWillChange.sink { publications += 1 }

        registry.reconcile(presentedPaneIDs: ["p1"], availablePaneIDs: ["p1"], endpoint: endpoint)
        let publicationsAfterCreation = publications
        registry.reconcile(presentedPaneIDs: ["p1"], availablePaneIDs: ["p1"], endpoint: endpoint)

        XCTAssertGreaterThan(publicationsAfterCreation, 0)
        XCTAssertEqual(publications, publicationsAfterCreation)
        withExtendedLifetime(subscription) {}
        registry.releaseAll()
    }

    @MainActor
    func testActiveConnectionRouteKeepsControllersReconciledToTargetConnection() {
        let registry = TerminalControllerRegistry()
        let endpoint = HerdrTerminalEndpoint(
            connectionID: "target",
            executablePath: "/usr/bin/false",
            socketPath: "/tmp/missing"
        )
        registry.reconcile(presentedPaneIDs: ["shared-pane"], availablePaneIDs: ["shared-pane"], endpoint: endpoint)
        let controller = registry.controllers["shared-pane"]

        XCTAssertFalse(BessieActiveConnectionSelection.shouldRestore(
            selectedConnectionID: "target",
            activeConnectionID: "target"
        ))
        registry.releaseAll(unlessConnectedTo: "target")
        XCTAssertTrue(registry.controllers["shared-pane"] === controller)

        XCTAssertTrue(BessieActiveConnectionSelection.shouldRestore(
            selectedConnectionID: "source",
            activeConnectionID: "target"
        ))
        registry.releaseAll(unlessConnectedTo: "other")
        XCTAssertTrue(registry.controllers.isEmpty)
    }

    @MainActor
    func testFleetStartsOnlyLaunchEnabledConnections() {
        let suite = "bessie.tests.fleet.launch.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fleet = ConnectionFleetViewModel(defaults: defaults)
        let remote = BessieConnectionDefinition(
            id: "remote",
            name: "Remote",
            kind: .ssh,
            sshHost: "127.0.0.1",
            connectAtLaunch: true
        )
        let localOff = BessieConnectionDefinition(
            id: BessieConnectionDefinition.localBessie.id,
            name: "This Mac",
            kind: .local,
            session: BessieCompatibility.sessionName,
            connectAtLaunch: false
        )

        fleet.start(
            connections: [localOff, remote],
            selectedConnectionID: remote.id,
            runtimeSelection: .bundled,
            bundledRuntimeURL: nil
        )

        XCTAssertEqual(fleet.startedConnectionIDs, [remote.id])
        XCTAssertEqual(fleet.activeConnectionID, remote.id)
        XCTAssertEqual(fleet.connectionHealth.count, 2)
        XCTAssertEqual(fleet.connectionHealth.first(where: { $0.connectionID == localOff.id })?.phase, "Not started")
        fleet.stop()
    }

    @MainActor
    func testRemoteOnlyFleetExcludesDisabledLocalFromRuntimeAndHealth() {
        let suite = "bessie.tests.fleet.remote-only.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fleet = ConnectionFleetViewModel(defaults: defaults)
        var local = BessieConnectionDefinition.localBessie
        local.enabled = false
        let remote = BessieConnectionDefinition(
            id: "remote",
            name: "Remote",
            kind: .ssh,
            sshHost: "127.0.0.1",
            connectAtLaunch: true
        )

        fleet.start(
            connections: [local, remote],
            selectedConnectionID: remote.id,
            runtimeSelection: .bundled,
            bundledRuntimeURL: nil
        )

        XCTAssertEqual(fleet.connectionDefinitions.map(\.id), [remote.id])
        XCTAssertEqual(fleet.startedConnectionIDs, [remote.id])
        XCTAssertEqual(fleet.activeConnectionID, remote.id)
        XCTAssertEqual(fleet.connectionHealth.map(\.connectionID), [remote.id])
        XCTAssertNil(fleet.activate(connectionID: local.id))
        XCTAssertEqual(fleet.notificationConnectionState(connectionID: local.id), .unavailable)
        fleet.stop()
    }

    @MainActor
    func testRemoteOnlyOnDemandFleetStartsNothingUntilActivated() {
        let fleet = ConnectionFleetViewModel()
        var local = BessieConnectionDefinition.localBessie
        local.enabled = false
        let remote = BessieConnectionDefinition(
            id: "remote",
            name: "Remote",
            kind: .ssh,
            sshHost: "127.0.0.1",
            connectAtLaunch: false
        )

        fleet.start(
            connections: [local, remote],
            selectedConnectionID: remote.id,
            runtimeSelection: .bundled,
            bundledRuntimeURL: nil
        )

        XCTAssertTrue(fleet.startedConnectionIDs.isEmpty)
        XCTAssertNil(fleet.activeConnectionID)
        XCTAssertNotNil(fleet.activate(connectionID: remote.id))
        XCTAssertEqual(fleet.startedConnectionIDs, [remote.id])
        fleet.stop()
    }

    @MainActor
    func testProjectLaunchReadinessStartsConfiguredOnDemandHerdOnlyOnce() async {
        let suite = "bessie.tests.fleet.project-on-demand.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fleet = ConnectionFleetViewModel(defaults: defaults)
        var localOnDemand = BessieConnectionDefinition.localBessie
        localOnDemand.connectAtLaunch = false
        fleet.sync(
            connections: [localOnDemand],
            runtimeSelection: .bundled,
            bundledRuntimeURL: nil
        )
        XCTAssertTrue(fleet.startedConnectionIDs.isEmpty)

        let first = Task { @MainActor in
            do {
                _ = try await fleet.waitForProjectLaunchTarget(
                    connectionID: localOnDemand.id,
                    timeout: 1,
                    pollInterval: 0.005
                )
                return nil as ProjectLaunchTargetReadinessError?
            } catch {
                return error as? ProjectLaunchTargetReadinessError
            }
        }
        let second = Task { @MainActor in
            do {
                _ = try await fleet.waitForProjectLaunchTarget(
                    connectionID: localOnDemand.id,
                    timeout: 1,
                    pollInterval: 0.005
                )
                return nil as ProjectLaunchTargetReadinessError?
            } catch {
                return error as? ProjectLaunchTargetReadinessError
            }
        }

        let firstFailure = await first.value
        let secondFailure = await second.value
        XCTAssertEqual(fleet.startedConnectionIDs, [localOnDemand.id])
        if case .unavailable(let connectionName, _) = firstFailure {
            XCTAssertEqual(connectionName, "This Mac")
        } else {
            XCTFail("Expected the intentionally missing test runtime to be unavailable")
        }
        XCTAssertEqual(secondFailure, firstFailure)
        fleet.stop()
    }

    @MainActor
    func testFleetCoalescesModelRefreshBursts() async {
        let fleet = ConnectionFleetViewModel()
        let initialPasses = fleet.refreshPassCount

        let refresh = fleet.scheduleRefresh()
        fleet.scheduleRefresh()
        fleet.scheduleRefresh()
        await refresh.value

        XCTAssertEqual(fleet.refreshPassCount, initialPasses + 1)
    }

    func testDefaultOffFeaturesHideFileDestinationsAndDeveloperFlagsRevealThem() {
        XCTAssertEqual(ProductDestination.visible(flags: .v1), [.herd, .projects])
        XCTAssertFalse(ProductDestination.visible(flags: .v1).contains(.workspace))
        XCTAssertEqual(
            ProductDestination.visible(flags: BessieFeatureFlags(enabled: [.fileBrowserEditor])),
            [.herd, .projects, .files]
        )
        XCTAssertFalse(ProductDestination.allCases.map(\.rawValue).contains("Attention"))
        XCTAssertTrue(ProductDestination.allCases.contains(.workspaces))
        XCTAssertTrue(ProductDestination.allCases.contains(.tabs))
    }

    @MainActor
    private func makeWarmStore(capacity: Int) -> WarmTerminalControllerStore<TestWarmController> {
        WarmTerminalControllerStore(
            warmCapacity: capacity,
            create: { TestWarmController(id: $0) },
            release: { $0.release() }
        )
    }

    func testSidebarUsesPersistentDestinationsAndRichSessionTree() throws {
        XCTAssertEqual(BessieSidebarSection.allCases, [.herd, .projects, .sessions])
        XCTAssertEqual(BessieSidebarSection.herd.destination, .herd)
        XCTAssertEqual(BessieSidebarSection.projects.destination, .projects)
        XCTAssertNil(BessieSidebarSection.sessions.destination)
        XCTAssertTrue(BessieSidebarAttentionPolicy.isProminent(needsYouCount: 1))
        XCTAssertFalse(BessieSidebarAttentionPolicy.isProminent(needsYouCount: 0))
        XCTAssertEqual(BessieSidebarSessionSummary.text(tabCount: 2, paneCount: 6), "2 tabs · 6 panes")
        XCTAssertEqual(BessieSidebarSessionSummary.text(tabCount: 1, paneCount: 1), "1 tab · 1 pane")

        var disclosure = BessieSidebarDisclosureState()
        XCTAssertTrue(BessieSidebarSection.allCases.allSatisfy(disclosure.isExpanded))
        disclosure.toggle(.sessions)
        XCTAssertFalse(disclosure.isExpanded(.sessions))
        XCTAssertTrue(disclosure.isExpanded(.herd))

        let topology = ScopedTopologyProjection(
            connections: [.init(connection: .localBessie, projection: try HerdrSessionProjection(snapshot: .surfaceFixture))],
            scope: .all
        )
        XCTAssertEqual(Set(topology.panes.map(\.pane.id)), ["p1", "p2", "p3"])
        XCTAssertEqual(BessieActionSurfaceContract.workspaceGroups.last, ["close"])
        XCTAssertEqual(BessieActionSurfaceContract.paneGroups, [
            ["focus", "zen"],
            ["split-right", "split-down", "zoom"],
            ["resize", "move", "take-over", "rename"],
            ["close"],
        ])
    }

    func testAppearanceIconTogglesEffectiveDarkAndLightWithoutCyclingSystem() {
        XCTAssertEqual(BessieAppearanceToggle.target(current: .dark, effectiveSystemIsDark: true), .light)
        XCTAssertEqual(BessieAppearanceToggle.target(current: .light, effectiveSystemIsDark: false), .dark)
        XCTAssertEqual(BessieAppearanceToggle.target(current: .system, effectiveSystemIsDark: true), .light)
        XCTAssertEqual(BessieAppearanceToggle.target(current: .system, effectiveSystemIsDark: false), .dark)
        XCTAssertEqual(BessieAppearanceToggle.target(current: .catppuccinMocha, effectiveSystemIsDark: false), .light)
        XCTAssertEqual(BessieAppearanceToggle.target(current: .catppuccinLatte, effectiveSystemIsDark: true), .dark)

        XCTAssertTrue(BessieAppearanceToggle.isVisible(for: .system))
        XCTAssertTrue(BessieAppearanceToggle.isVisible(for: .dark))
        XCTAssertTrue(BessieAppearanceToggle.isVisible(for: .light))
        XCTAssertFalse(BessieAppearanceToggle.isVisible(for: .catppuccinLatte))
        XCTAssertFalse(BessieAppearanceToggle.isVisible(for: .catppuccinFrappe))
        XCTAssertFalse(BessieAppearanceToggle.isVisible(for: .catppuccinMacchiato))
        XCTAssertFalse(BessieAppearanceToggle.isVisible(for: .catppuccinMocha))
    }

    func testZenLayoutIsolatesOnlyTheRequestedPane() throws {
        let rect = LayoutRect(x: 0, y: 0, width: 100, height: 100)
        let layout = RecursivePaneLayout.split(.init(
            id: "root",
            direction: .right,
            ratio: 0.5,
            rect: rect,
            path: [],
            first: .pane(.init(paneID: "p1", focused: false, rect: rect)),
            second: .pane(.init(paneID: "p2", focused: true, rect: rect))
        ))

        XCTAssertEqual(layout.isolatedPane("p1")?.paneIDs, ["p1"])
        XCTAssertEqual(layout.isolatedPane("p2")?.paneIDs, ["p2"])
        XCTAssertNil(layout.isolatedPane("missing"))
    }

    func testCloseResolutionUsesExactActionsAndExplicitFinalTabWorkspaceFallback() throws {
        let projection = try HerdrSessionProjection(snapshot: .surfaceFixture)
        XCTAssertEqual(PendingClose.workspace("w1").resolvedAction(in: projection), .workspaceClose(id: "w1"))
        XCTAssertEqual(PendingClose.pane("p2").resolvedAction(in: projection), .paneClose(id: "p2"))

        let multiTabProjection = try HerdrSessionProjection(snapshot: .paneMoveFixture)
        XCTAssertEqual(PendingClose.tab("t1").resolvedAction(in: multiTabProjection), .tabClose(id: "t1"))

        let finalTabProjection = try HerdrSessionProjection(snapshot: .singleTabFixture)
        XCTAssertEqual(
            PendingClose.tab("only-tab").resolvedAction(in: finalTabProjection),
            .workspaceClose(id: "only-workspace")
        )
        XCTAssertTrue(PendingClose.tab("only-tab").requiresIntentConfirmation(in: finalTabProjection))
        XCTAssertEqual(
            PendingClose.pane("only-pane").resolvedAction(in: finalTabProjection),
            .workspaceClose(id: "only-workspace")
        )
        XCTAssertTrue(PendingClose.pane("only-pane").requiresIntentConfirmation(in: finalTabProjection))
    }

    func testScopedTopologyFiltersAllLocalAndRemoteConnections() throws {
        let local = ConnectionTopologyProjection(
            connection: .localBessie,
            projection: try HerdrSessionProjection(snapshot: .surfaceFixture)
        )
        let remoteConnection = try BessieConnectionDefinition(
            id: "remote", name: "Build Mac", kind: .ssh, sshHost: "build-mac", session: "main"
        ).validated()
        let remote = ConnectionTopologyProjection(
            connection: remoteConnection,
            projection: try HerdrSessionProjection(snapshot: .duplicateIDRemoteFixture)
        )

        XCTAssertEqual(ScopedTopologyProjection(connections: [local, remote], scope: .all).workspaces.map(\.id.connectionID), ["local-bessie", "local-bessie", "remote"])
        XCTAssertEqual(ScopedTopologyProjection(connections: [local, remote], scope: .connection(id: "local-bessie")).workspaces.map(\.id.connectionID), ["local-bessie", "local-bessie"])
        XCTAssertEqual(ScopedTopologyProjection(connections: [local, remote], scope: .connection(id: "remote")).workspaces.map(\.id.connectionID), ["remote"])
    }

    func testScopedTopologyKeepsDuplicatePaneIDsBoundToOwningConnection() throws {
        let local = ConnectionTopologyProjection(
            connection: .localBessie,
            projection: try HerdrSessionProjection(snapshot: .surfaceFixture)
        )
        let remoteConnection = try BessieConnectionDefinition(
            id: "remote", name: "Build Mac", kind: .ssh, sshHost: "build-mac", session: "main"
        ).validated()
        let remote = ConnectionTopologyProjection(
            connection: remoteConnection,
            projection: try HerdrSessionProjection(snapshot: .duplicateIDRemoteFixture)
        )
        let topology = ScopedTopologyProjection(connections: [local, remote], scope: .all)
        let duplicatePanes = topology.panes.filter { $0.id.paneID == "p1" }

        XCTAssertEqual(Set(duplicatePanes.map(\.id.connectionID)), ["local-bessie", "remote"])
        XCTAssertEqual(
            topology.openTarget(for: .init(connectionID: "remote", paneID: "p1")),
            RoutedPaneTarget(connectionID: "remote", workspaceID: "remote-w", tabID: "remote-t", paneID: "p1")
        )
        XCTAssertEqual(
            topology.openTarget(for: .init(connectionID: "local-bessie", paneID: "p1")),
            RoutedPaneTarget(connectionID: "local-bessie", workspaceID: "w1", tabID: "t1", paneID: "p1")
        )
        XCTAssertEqual(
            topology.openTarget(for: TopologyTabID(connectionID: "remote", tabID: "remote-t")),
            RoutedPaneTarget(connectionID: "remote", workspaceID: "remote-w", tabID: "remote-t", paneID: "p1")
        )
    }

    func testWorkspaceScopesFilterOrdinaryPaneRowsWithExactRoutesAndOrder() throws {
        let local = ConnectionTopologyProjection(
            connection: .localBessie,
            projection: try HerdrSessionProjection(snapshot: .paneMoveFixture)
        )
        let remoteConnection = try BessieConnectionDefinition(
            id: "remote", name: "Build Mac", kind: .ssh, sshHost: "build-mac", session: "main"
        ).validated()
        let remote = ConnectionTopologyProjection(
            connection: remoteConnection,
            projection: try HerdrSessionProjection(snapshot: .duplicateIDRemoteFixture)
        )
        let rail = HerdRailProjection(connections: [
            HerdRailConnectionInput(connection: local.connection, projection: local.projection, isFresh: true),
            HerdRailConnectionInput(connection: remote.connection, projection: remote.projection, isFresh: true),
        ])

        let selectedTab = WorkspaceScopeReducer.filtered(
            rail,
            scope: .selectedTab(connectionID: "local-bessie", workspaceID: "w1", tabID: "t1")
        )
        XCTAssertEqual(
            selectedTab.rows.map(\.target),
            [RoutedPaneTarget(connectionID: "local-bessie", workspaceID: "w1", tabID: "t1", paneID: "p1")]
        )

        let allTabs = WorkspaceScopeReducer.filtered(
            rail,
            scope: .allTabs(connectionID: "local-bessie", workspaceID: "w1")
        )
        XCTAssertEqual(allTabs.rows.map(\.target.paneID), ["p1", "p2"])
        XCTAssertTrue(allTabs.rows.allSatisfy {
            $0.target.connectionID == "local-bessie" && $0.target.workspaceID == "w1"
        })

        let allWorkspaces = WorkspaceScopeReducer.filtered(
            rail,
            scope: .allWorkspaces(connectionID: "local-bessie")
        )
        XCTAssertEqual(allWorkspaces.rows.map(\.target.paneID), ["p1", "p2", "p3"])
        XCTAssertTrue(allWorkspaces.rows.allSatisfy { $0.target.connectionID == "local-bessie" })

        let allHerds = WorkspaceScopeReducer.filtered(rail, scope: .allHerds)
        XCTAssertEqual(
            Set(allHerds.rows.filter { $0.target.paneID == "p1" }.map(\.target.connectionID)),
            ["local-bessie", "remote"]
        )
    }

    func testWorkspaceScopeSelectionRetainsVisiblePaneThenUsesFocusedOrFirstFallback() throws {
        let projection = try HerdrSessionProjection(snapshot: .paneMoveFixture)
        let rail = HerdRailProjection(connections: [
            HerdRailConnectionInput(connection: .localBessie, projection: projection, isFresh: true),
        ])
        let allTabs = WorkspaceScopeReducer.filtered(
            rail,
            scope: .allTabs(connectionID: "local-bessie", workspaceID: "w1")
        )

        XCTAssertEqual(
            WorkspaceScopeReducer.selection(
                in: allTabs,
                retaining: HerdPaneIdentity(connectionID: "local-bessie", paneID: "p2"),
                focused: [HerdPaneIdentity(connectionID: "local-bessie", paneID: "p1")]
            )?.paneID,
            "p2"
        )
        XCTAssertEqual(
            WorkspaceScopeReducer.selection(
                in: allTabs,
                retaining: HerdPaneIdentity(connectionID: "remote", paneID: "p1"),
                focused: [HerdPaneIdentity(connectionID: "local-bessie", paneID: "p1")]
            )?.paneID,
            "p1"
        )

        let reviewTab = WorkspaceScopeReducer.filtered(
            rail,
            scope: .selectedTab(connectionID: "local-bessie", workspaceID: "w1", tabID: "t2")
        )
        XCTAssertEqual(
            WorkspaceScopeReducer.selection(
                in: reviewTab,
                retaining: nil,
                focused: [HerdPaneIdentity(connectionID: "local-bessie", paneID: "p1")]
            ),
            RoutedPaneTarget(connectionID: "local-bessie", workspaceID: "w1", tabID: "t2", paneID: "p2")
        )
    }

    func testRoutedPaneRecognizesOnlyItsExactAuthoritativeFocus() throws {
        let projection = try HerdrSessionProjection(snapshot: .surfaceFixture)
        let focused = RoutedPaneTarget(
            connectionID: "local-bessie", workspaceID: "w1", tabID: "t1", paneID: "p2"
        )

        XCTAssertTrue(focused.isAuthoritativelyFocused(connectionID: "local-bessie", projection: projection))
        XCTAssertFalse(focused.isAuthoritativelyFocused(connectionID: "remote", projection: projection))
        XCTAssertFalse(
            RoutedPaneTarget(
                connectionID: "local-bessie", workspaceID: "w2", tabID: "t2", paneID: "p2"
            ).isAuthoritativelyFocused(connectionID: "local-bessie", projection: projection)
        )
    }

    func testRoutedPaneCanPresentImmediatelyOnlyFromItsOwningCurrentProjection() throws {
        let projection = try HerdrSessionProjection(snapshot: .surfaceFixture)
        let routed = RoutedPaneTarget(
            connectionID: "local-bessie", workspaceID: "w1", tabID: "t1", paneID: "p1"
        )

        XCTAssertEqual(
            routed.currentTarget(connectionID: "local-bessie", projection: projection),
            PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        )
        XCTAssertFalse(routed.isAuthoritativelyFocused(connectionID: "local-bessie", projection: projection))
        XCTAssertNil(routed.currentTarget(connectionID: "remote", projection: projection))
        XCTAssertNil(
            RoutedPaneTarget(
                connectionID: "local-bessie", workspaceID: "w1", tabID: "t1", paneID: "missing"
            ).currentTarget(connectionID: "local-bessie", projection: projection)
        )
    }

    func testCloseReconciliationClearsFinalSelectionAndReturnsToHerd() throws {
        let empty = try HerdrSessionProjection(snapshot: .emptyFixture)
        let result = BessieCloseReconciliation(
            connectionID: "local-bessie",
            projection: empty,
            preferredWorkspaceID: "removed"
        )

        XCTAssertEqual(result.connectionID, "local-bessie")
        XCTAssertNil(result.workspaceID)
        XCTAssertNil(result.paneID)
        XCTAssertEqual(result.destination, .herd)
        XCTAssertTrue(result.exitsZen)
    }

    func testCloseReconciliationUsesFreshAuthoritativeFallbackWhenWorkRemains() throws {
        let projection = try HerdrSessionProjection(snapshot: .surfaceFixture)
        let result = BessieCloseReconciliation(
            connectionID: "local-bessie",
            projection: projection,
            preferredWorkspaceID: "w2"
        )

        XCTAssertEqual(result.workspaceID, "w2")
        XCTAssertEqual(result.paneID, "p3")
        XCTAssertEqual(result.destination, .workspace)
        XCTAssertFalse(result.exitsZen)
    }

    func testTopologyCreationControlsUseOrdinaryHerdrActions() {
        XCTAssertEqual(TopologyCreation.workspace.action, .workspaceCreate(cwd: nil, label: nil, focus: true))
        XCTAssertEqual(
            TopologyCreation.tab(workspaceID: "w1", name: " tests ").action,
            .tabCreate(workspaceID: "w1", cwd: nil, label: "tests", focus: true)
        )
        XCTAssertEqual(
            TopologyCreation.pane(targetPaneID: "p1", direction: .right, name: " logs ").action,
            .paneSplit(targetPaneID: "p1", direction: .right, ratio: 0.5, cwd: nil, focus: true)
        )
        XCTAssertEqual(
            TopologyCreation.pane(targetPaneID: "p1", direction: .right, name: " logs ")
                .followUpAction(createdPaneID: "p2"),
            .paneRename(id: "p2", label: "logs")
        )
        XCTAssertNil(TopologyCreation.tab(workspaceID: "w1", name: "tests").followUpAction(createdPaneID: "p2"))
    }

    func testOnboardingNavigationHandoffRequiresExactOwningProjection() throws {
        let projection = try HerdrSessionProjection(snapshot: .surfaceFixture)
        let request = ProductNavigationRequest(
            connectionID: "local-bessie", workspaceID: "w1", tabID: "t1", paneID: "p2"
        )

        XCTAssertEqual(
            request.target(connectionID: "local-bessie", projection: projection),
            PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p2")
        )
        XCTAssertNil(request.target(connectionID: "remote", projection: projection))
    }

    func testMainWindowPolicyUsesOneControllerOwningScene() {
        XCTAssertEqual(BessieWindowPolicy.controllerSceneID, "main")
        XCTAssertEqual(BessieWindowPolicy.maximumControllerWindowCount, 1)
    }

    func testConnectedAgentsRemainDistinctWhenSessionsReusePaneIDs() throws {
        let agent = AgentProjection(
            id: "p1", terminalID: "term-1", workspaceID: "w1", tabID: "t1",
            focused: false, label: "Hermes", agent: "hermes", displayAgent: "Hermes",
            name: nil, title: nil, agentStatus: "working", revision: 1, launchPending: false
        )

        let local = ConnectedAgentProjection(connection: .localBessie, agent: agent)
        let remote = ConnectedAgentProjection(
            connection: try BessieConnectionDefinition(
                id: "remote", name: "Hermes VPS", kind: .ssh, sshHost: "hermes", session: nil
            ).validated(),
            agent: agent
        )

        XCTAssertNotEqual(local.id, remote.id)
        XCTAssertEqual(local.paneID, "p1")
        XCTAssertEqual(remote.paneID, "p1")
        XCTAssertEqual(remote.connectionName, "Hermes VPS")
    }

    func testHerdUsesAuthoritativeAgentRosterAcrossWorkspacesAndEveryState() throws {
        let projection = try HerdrSessionProjection(snapshot: .surfaceFixture)

        XCTAssertEqual(projection.agents.map(\.id), ["p1", "p3"])
        XCTAssertEqual(projection.agents.map(\.workspaceID), ["w1", "w2"])
        XCTAssertEqual(projection.agents.map(\.agentStatus), ["idle", "unknown"])
        XCTAssertEqual(projection.agents.map(\.identity), ["Codex one", "Claude two"])
    }

    func testWorkspaceNeedsYouCountUsesOnlyAuthoritativeBlockedAgents() throws {
        let projection = try HerdrSessionProjection(snapshot: .surfaceFixture)
        let surfaces = BessieSurfaceProjection(projection: projection)

        XCTAssertEqual(surfaces.workspaces.map(\.label), ["alpha", "beta"])
        XCTAssertEqual(surfaces.workspaces[0].rolledState, .blocked)
        XCTAssertEqual(surfaces.workspaces[0].requiresUserActionCount, 0)
        XCTAssertEqual(surfaces.workspaces[1].rolledState, .idle)
        XCTAssertEqual(surfaces.notificationPanes.map(\.paneID), ["p1", "p3"])
        XCTAssertEqual(surfaces.notificationPanes.map(\.state), [.idle, .unknown])
        XCTAssertEqual(surfaces.notificationPanes[0].target, PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1"))
    }

    func testPanePresentationTitleUsesCWDThenShellInsteadOfUntitledPlaceholder() {
        let cwdPane = PaneProjection(
            id: "p1", terminalID: "term-1", workspaceID: "w1", tabID: "t1", focused: false,
            label: nil, cwd: "/Users/jordan/Projects/bessie", foregroundCWD: nil,
            agent: nil, title: nil, agentStatus: "idle", revision: 1
        )
        let shellPane = PaneProjection(
            id: "p2", terminalID: "term-2", workspaceID: "w1", tabID: "t1", focused: false,
            label: nil, cwd: nil, foregroundCWD: nil,
            agent: nil, title: nil, agentStatus: "idle", revision: 1
        )

        XCTAssertEqual(cwdPane.presentationTitle, "bessie")
        XCTAssertEqual(shellPane.presentationTitle, "Shell")
    }

    func testPreferencesRoundTripEveryApprovedV1SettingAndDecodeLegacyValues() throws {
        let preferences = BessiePreferences(
            appearance: .light,
            density: .compact,
            appIcon: .light,
            cowprintEnabled: false,
            terminalFontSize: 15,
            paneGap: 6,
            notifications: .blockedAndDone,
            startupBehavior: .lastWorkspace
        )
        XCTAssertEqual(try JSONDecoder().decode(BessiePreferences.self, from: JSONEncoder().encode(preferences)), preferences)

        let legacy = Data(#"{"terminalFontSize":14,"paneGap":7}"#.utf8)
        let decoded = try JSONDecoder().decode(BessiePreferences.self, from: legacy)
        XCTAssertEqual(decoded.terminalFontSize, 14)
        XCTAssertEqual(decoded.paneGap, 7)
        XCTAssertEqual(decoded.appearance, .dark)
        XCTAssertEqual(decoded.density, .comfortable)
        XCTAssertEqual(decoded.appIcon, .dark)
        XCTAssertTrue(decoded.cowprintEnabled)
        XCTAssertEqual(decoded.notifications, .blockedOnly)
        XCTAssertEqual(decoded.startupBehavior, .workspaceChooser)

        let oldPresentation = Data(#"{"appearance":"light","cowprintEnabled":false,"cowPrintIntensity":0.08,"cowPrintMotion":true,"terminalFontSize":15,"paneGap":6}"#.utf8)
        let migrated = try JSONDecoder().decode(BessiePreferences.self, from: oldPresentation)
        XCTAssertEqual(migrated.appearance, .light)
        XCTAssertFalse(migrated.cowprintEnabled)
        XCTAssertEqual(migrated.terminalFontSize, 15)
        XCTAssertEqual(migrated.paneGap, 6)
        let reencoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(migrated)) as? [String: Any])
        XCTAssertNil(reencoded["cowPrintIntensity"])
        XCTAssertNil(reencoded["cowPrintMotion"])
    }

    func testOpenPaneTargetComesFromCurrentProjection() throws {
        let projection = try HerdrSessionProjection(snapshot: .surfaceFixture)
        let target = try XCTUnwrap(BessieSurfaceProjection(projection: projection).openTarget(paneID: "p2"))

        XCTAssertEqual(target.workspaceID, "w1")
        XCTAssertEqual(target.tabID, "t1")
        XCTAssertEqual(target.paneID, "p2")
        XCTAssertNil(BessieSurfaceProjection(projection: projection).openTarget(paneID: "missing"))
    }

    func testPaneMoveChoicesUseCurrentTopologyWithoutGuessingDestinations() throws {
        let projection = try HerdrSessionProjection(snapshot: .paneMoveFixture)
        let choices = try XCTUnwrap(PaneMoveChoices(projection: projection, paneID: "p1"))

        XCTAssertEqual(choices.tabs.map(\.title), ["review"])
        XCTAssertEqual(
            choices.tabs.first?.destination,
            .tab(tabID: "t2", targetPaneID: "p2", split: .right, ratio: 0.5)
        )
        XCTAssertEqual(choices.workspaces.map(\.title), ["beta"])
        XCTAssertEqual(choices.workspaces.first?.destination, .newTab(workspaceID: "w2", label: nil))
        XCTAssertEqual(choices.newTab, .newTab(workspaceID: "w1", label: nil))
        XCTAssertEqual(choices.newWorkspace, .newWorkspace(label: nil, tabLabel: nil))
        XCTAssertNil(PaneMoveChoices(projection: projection, paneID: "missing"))
    }

    func testNotificationPlannerSeedsThenEmitsOnlyNewAllowedTransitions() {
        var planner = BessieNotificationPlanner()
        let blocked = BessieNotificationPane(
            paneID: "p1", state: .blocked, revision: 1,
            identity: "Claude", location: "alpha / build / Claude",
            target: PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        )
        let done = BessieNotificationPane(
            paneID: "p2", state: .done, revision: 1,
            identity: "Codex", location: "alpha / review / Codex",
            target: PaneOpenTarget(workspaceID: "w1", tabID: "t2", paneID: "p2")
        )

        XCTAssertEqual(planner.events(for: [blocked, done], policy: .blockedAndDone, activePaneID: nil), [])

        // blocked → idle is Settled completion (Hermes-style) and must notify.
        let idle = BessieNotificationPane(
            paneID: "p1", state: .idle, revision: 2,
            identity: blocked.identity, location: blocked.location, target: blocked.target
        )
        // done → working is not a notify-worthy settled transition.
        let working = BessieNotificationPane(
            paneID: "p2", state: .working, revision: 2,
            identity: done.identity, location: done.location, target: done.target
        )
        let settledEvents = planner.events(for: [idle, working], policy: .blockedAndDone, activePaneID: nil)
        XCTAssertEqual(settledEvents.count, 1)
        XCTAssertEqual(settledEvents.first?.title, "Claude is settled")
        XCTAssertEqual(settledEvents.first?.target, blocked.target)

        let blockedAgain = BessieNotificationPane(
            paneID: "p1", state: .blocked, revision: 3,
            identity: blocked.identity, location: blocked.location, target: blocked.target
        )
        let doneAgain = BessieNotificationPane(
            paneID: "p2", state: .done, revision: 3,
            identity: done.identity, location: done.location, target: done.target
        )
        let events = planner.events(
            for: [blockedAgain, doneAgain],
            policy: .blockedAndDone,
            activePaneID: "p2",
            connectionLabel: "Hermes VPS"
        )

        // p1 idle→blocked notifies; p2 working→done suppressed by activePaneID.
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Claude needs you")
        XCTAssertEqual(events.first?.body, "alpha / build / Claude · Hermes VPS")
        XCTAssertEqual(events.first?.target, blocked.target)
        XCTAssertEqual(planner.events(for: [blockedAgain, doneAgain], policy: .blockedAndDone, activePaneID: nil), [])
    }

    func testNotificationPlannerEmitsSettledOnWorkingToDoneAndSkipsIdleDoneChurn() {
        var planner = BessieNotificationPlanner()
        let working = BessieNotificationPane(
            paneID: "p1", state: .working, revision: 1,
            identity: "Hermes", location: "alpha / tab / Hermes",
            target: PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        )
        _ = planner.events(for: [working], policy: .blockedAndDone, activePaneID: nil)

        let done = BessieNotificationPane(
            paneID: "p1", state: .done, revision: 2,
            identity: working.identity, location: working.location, target: working.target
        )
        let doneEvents = planner.events(for: [done], policy: .blockedAndDone, activePaneID: nil)
        XCTAssertEqual(doneEvents.count, 1)
        XCTAssertEqual(doneEvents.first?.title, "Hermes is done")

        let idle = BessieNotificationPane(
            paneID: "p1", state: .idle, revision: 3,
            identity: working.identity, location: working.location, target: working.target
        )
        // Settled → Settled (done ↔ idle) must not re-notify.
        XCTAssertEqual(planner.events(for: [idle], policy: .blockedAndDone, activePaneID: nil), [])
    }

    func testNotificationDeepLinkRoundTripsFrozenFleetSchema() throws {
        let target = RoutedPaneTarget(
            connectionID: "remote",
            workspaceID: "w1",
            tabID: "t1",
            paneID: "p1"
        )
        let deepLink = BessieNotificationDeepLink(target: target)

        XCTAssertEqual(deepLink.userInfo, [
            "connection_id": "remote",
            "workspace_id": "w1",
            "tab_id": "t1",
            "pane_id": "p1",
        ])
        XCTAssertEqual(BessieNotificationDeepLink(userInfo: deepLink.userInfo)?.target, target)
        XCTAssertNil(BessieNotificationDeepLink(userInfo: [
            "workspace_id": "w1",
            "tab_id": "t1",
            "pane_id": "p1",
        ]))
    }

    func testNotificationRouteQueueUsesTapIdentity() {
        let target = RoutedPaneTarget(
            connectionID: "remote",
            workspaceID: "w1",
            tabID: "t1",
            paneID: "p1"
        )
        let first = PendingNotificationRoute(id: UUID(), target: target)
        let second = PendingNotificationRoute(id: UUID(), target: target)
        var queue = NotificationRouteQueue()

        queue.enqueue(first)
        queue.enqueue(second)
        queue.consume(first)
        XCTAssertEqual(queue.pending, second)

        let third = PendingNotificationRoute(id: UUID(), target: target)
        queue.enqueue(third)
        XCTAssertEqual(queue.pending, third)
    }

    @MainActor
    func testNotificationConnectionWaitsForFleetInitialization() {
        let fleet = ConnectionFleetViewModel()
        XCTAssertEqual(fleet.notificationConnectionState(connectionID: "remote"), .waiting)
    }

    @MainActor
    func testFleetRetainsRouteFailureWithoutAReadyConnection() {
        let fleet = ConnectionFleetViewModel()

        fleet.reportRouteFailure("Connection unavailable")

        XCTAssertEqual(fleet.routeFailure, "Connection unavailable")
        fleet.clearRouteFailure()
        XCTAssertNil(fleet.routeFailure)
    }

    func testNotificationPlannerHonorsPolicyWithoutRetroactiveDelivery() {
        var planner = BessieNotificationPlanner()
        let idle = BessieNotificationPane(
            paneID: "p1", state: .idle, revision: 1,
            identity: "Claude", location: "alpha / build / Claude",
            target: PaneOpenTarget(workspaceID: "w1", tabID: "t1", paneID: "p1")
        )
        _ = planner.events(for: [idle], policy: .blockedOnly, activePaneID: nil)
        let done = BessieNotificationPane(
            paneID: "p1", state: .done, revision: 2,
            identity: idle.identity, location: idle.location, target: idle.target
        )
        XCTAssertEqual(planner.events(for: [done], policy: .blockedOnly, activePaneID: nil), [])
        XCTAssertEqual(planner.events(for: [done], policy: .blockedAndDone, activePaneID: nil), [])
    }

    func testNotificationRouteRequiresOwningConnectionAndCurrentExactTopology() throws {
        let projection = try HerdrSessionProjection(snapshot: .surfaceFixture)
        let target = RoutedPaneTarget(
            connectionID: "remote",
            workspaceID: "w2",
            tabID: "t2",
            paneID: "p3"
        )
        let current = BessieNotificationRoute.resolve(
            pending: target,
            connectionID: "remote",
            projection: projection
        )

        XCTAssertEqual(current, PaneOpenTarget(workspaceID: "w2", tabID: "t2", paneID: "p3"))
        XCTAssertNil(BessieNotificationRoute.resolve(pending: target, connectionID: "local-bessie", projection: projection))
        XCTAssertNil(
            BessieNotificationRoute.resolve(
                pending: RoutedPaneTarget(
                    connectionID: "remote",
                    workspaceID: "stale",
                    tabID: "t2",
                    paneID: "p3"
                ),
                connectionID: "remote",
                projection: projection
            )
        )
    }

    func testDragPayloadsProduceOnlyValidSameCollectionReorders() throws {
        let projection = try HerdrSessionProjection(snapshot: .paneMoveFixture)

        let workspacePayload = BessieDragPayload.workspace(id: "w2")
        XCTAssertEqual(BessieDragPayload(encoded: workspacePayload.encoded), workspacePayload)
        XCTAssertEqual(BessieReorderDrop.workspaceAction(payload: workspacePayload, over: "w1", projection: projection), .workspaceMove(id: "w2", insertIndex: 0))
        XCTAssertEqual(BessieReorderDrop.workspaceAction(payload: .workspace(id: "w1"), over: "w2", projection: projection), .workspaceMove(id: "w1", insertIndex: 2))
        XCTAssertNil(BessieReorderDrop.workspaceAction(payload: workspacePayload, over: "w2", projection: projection))

        let tabPayload = BessieDragPayload.tab(id: "t2", workspaceID: "w1")
        XCTAssertEqual(BessieDragPayload(encoded: tabPayload.encoded), tabPayload)
        XCTAssertEqual(BessieReorderDrop.tabAction(payload: tabPayload, over: "t1", workspaceID: "w1", projection: projection), .tabMove(id: "t2", insertIndex: 0))
        XCTAssertEqual(BessieReorderDrop.tabAction(payload: .tab(id: "t1", workspaceID: "w1"), over: "t2", workspaceID: "w1", projection: projection), .tabMove(id: "t1", insertIndex: 2))
        XCTAssertNil(BessieReorderDrop.tabAction(payload: tabPayload, over: "t2", workspaceID: "w2", projection: projection))
    }

    func testSplitDragRatioUsesAxisExtentAndStaysUsable() {
        XCTAssertEqual(BessieSplitDrag.ratio(original: 0.5, translation: 100, extent: 500), 0.7, accuracy: 0.0001)
        XCTAssertEqual(BessieSplitDrag.ratio(original: 0.2, translation: -500, extent: 500), 0.1, accuracy: 0.0001)
        XCTAssertEqual(BessieSplitDrag.ratio(original: 0.8, translation: 500, extent: 500), 0.9, accuracy: 0.0001)
        XCTAssertEqual(BessieSplitDrag.ratio(original: 0.5, translation: 100, extent: 0), 0.5, accuracy: 0.0001)
    }

    func testPaneActionTargetNeverEscapesTheVisibleTab() throws {
        let projection = try HerdrSessionProjection(snapshot: .paneMoveFixture)
        let visible = Set(["p1"])

        XCTAssertEqual(
            BessiePaneActionTarget.resolve(selectedPaneID: "p1", visiblePaneIDs: visible, projection: projection),
            "p1"
        )
        XCTAssertEqual(
            BessiePaneActionTarget.resolve(selectedPaneID: "p3", visiblePaneIDs: visible, projection: projection),
            "p1"
        )
        XCTAssertNil(
            BessiePaneActionTarget.resolve(selectedPaneID: "p3", visiblePaneIDs: [], projection: projection)
        )
    }
}

private final class TestWarmController {
    let id: String
    private(set) var released = false

    init(id: String) { self.id = id }
    func release() { released = true }
}

private extension HerdrSnapshot {
    static let emptyFixture = HerdrSnapshot(
        version: "0.8.0", protocolVersion: 19,
        focusedWorkspaceID: nil, focusedTabID: nil, focusedPaneID: nil,
        workspaces: [], tabs: [], panes: [], layouts: [], agents: []
    )

    static let singleTabFixture = HerdrSnapshot(
        version: "0.8.0", protocolVersion: 19,
        focusedWorkspaceID: "only-workspace", focusedTabID: "only-tab", focusedPaneID: "only-pane",
        workspaces: [.object([
            "workspace_id": .string("only-workspace"), "number": .number(1), "label": .string("only"),
            "focused": .bool(true), "pane_count": .number(1), "tab_count": .number(1),
            "active_tab_id": .string("only-tab"), "agent_status": .string("idle"),
        ])],
        tabs: [.object([
            "tab_id": .string("only-tab"), "workspace_id": .string("only-workspace"), "number": .number(1),
            "label": .string("only"), "focused": .bool(true), "pane_count": .number(1), "agent_status": .string("idle"),
        ])],
        panes: [.object([
            "pane_id": .string("only-pane"), "terminal_id": .string("only-terminal"),
            "workspace_id": .string("only-workspace"), "tab_id": .string("only-tab"),
            "focused": .bool(true), "agent_status": .string("idle"), "revision": .number(1),
        ])],
        layouts: [singlePaneLayout(workspaceID: "only-workspace", tabID: "only-tab", paneID: "only-pane")],
        agents: []
    )

    static let duplicateIDRemoteFixture = HerdrSnapshot(
        version: "0.8.0", protocolVersion: 19,
        focusedWorkspaceID: "remote-w", focusedTabID: "remote-t", focusedPaneID: "p1",
        workspaces: [
            .object(["workspace_id": .string("remote-w"), "number": .number(1), "label": .string("remote"), "focused": .bool(true), "pane_count": .number(1), "tab_count": .number(1), "active_tab_id": .string("remote-t"), "agent_status": .string("working")]),
        ],
        tabs: [
            .object(["tab_id": .string("remote-t"), "workspace_id": .string("remote-w"), "number": .number(1), "label": .string("remote tab"), "focused": .bool(true), "pane_count": .number(1), "agent_status": .string("working")]),
        ],
        panes: [
            .object(["pane_id": .string("p1"), "terminal_id": .string("remote-term"), "workspace_id": .string("remote-w"), "tab_id": .string("remote-t"), "focused": .bool(true), "agent_status": .string("working"), "revision": .number(1)]),
        ],
        layouts: [singlePaneLayout(workspaceID: "remote-w", tabID: "remote-t", paneID: "p1")], agents: []
    )

    static let paneMoveFixture = HerdrSnapshot(
        version: "0.8.0", protocolVersion: 19,
        focusedWorkspaceID: "w1", focusedTabID: "t1", focusedPaneID: "p1",
        workspaces: [
            .object(["workspace_id": .string("w1"), "number": .number(1), "label": .string("alpha"), "focused": .bool(true), "pane_count": .number(2), "tab_count": .number(2), "active_tab_id": .string("t1"), "agent_status": .string("idle")]),
            .object(["workspace_id": .string("w2"), "number": .number(2), "label": .string("beta"), "focused": .bool(false), "pane_count": .number(1), "tab_count": .number(1), "active_tab_id": .string("t3"), "agent_status": .string("idle")]),
        ],
        tabs: [
            .object(["tab_id": .string("t1"), "workspace_id": .string("w1"), "number": .number(1), "label": .string("build"), "focused": .bool(true), "pane_count": .number(1), "agent_status": .string("idle")]),
            .object(["tab_id": .string("t2"), "workspace_id": .string("w1"), "number": .number(2), "label": .string("review"), "focused": .bool(false), "pane_count": .number(1), "agent_status": .string("idle")]),
            .object(["tab_id": .string("t3"), "workspace_id": .string("w2"), "number": .number(1), "label": .string("shell"), "focused": .bool(false), "pane_count": .number(1), "agent_status": .string("idle")]),
        ],
        panes: [
            .object(["pane_id": .string("p1"), "terminal_id": .string("term1"), "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(true), "agent_status": .string("idle"), "revision": .number(1)]),
            .object(["pane_id": .string("p2"), "terminal_id": .string("term2"), "workspace_id": .string("w1"), "tab_id": .string("t2"), "focused": .bool(false), "agent_status": .string("idle"), "revision": .number(1)]),
            .object(["pane_id": .string("p3"), "terminal_id": .string("term3"), "workspace_id": .string("w2"), "tab_id": .string("t3"), "focused": .bool(false), "agent_status": .string("idle"), "revision": .number(1)]),
        ],
        layouts: [
            singlePaneLayout(workspaceID: "w1", tabID: "t1", paneID: "p1"),
            singlePaneLayout(workspaceID: "w1", tabID: "t2", paneID: "p2"),
            singlePaneLayout(workspaceID: "w2", tabID: "t3", paneID: "p3"),
        ], agents: []
    )

    static let surfaceFixture = HerdrSnapshot(
        version: "0.8.0", protocolVersion: 19,
        focusedWorkspaceID: "w1", focusedTabID: "t1", focusedPaneID: "p2",
        workspaces: [
            .object(["workspace_id": .string("w1"), "number": .number(1), "label": .string("alpha"), "focused": .bool(true), "pane_count": .number(2), "tab_count": .number(1), "active_tab_id": .string("t1"), "agent_status": .string("blocked")]),
            .object(["workspace_id": .string("w2"), "number": .number(2), "label": .string("beta"), "focused": .bool(false), "pane_count": .number(1), "tab_count": .number(1), "active_tab_id": .string("t2"), "agent_status": .string("idle")]),
        ],
        tabs: [
            .object(["tab_id": .string("t1"), "workspace_id": .string("w1"), "number": .number(1), "label": .string("build"), "focused": .bool(true), "pane_count": .number(2), "agent_status": .string("blocked")]),
            .object(["tab_id": .string("t2"), "workspace_id": .string("w2"), "number": .number(1), "label": .string("shell"), "focused": .bool(false), "pane_count": .number(1), "agent_status": .string("idle")]),
        ],
        panes: [
            .object(["pane_id": .string("p1"), "terminal_id": .string("term1"), "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(false), "label": .string("blocked pane"), "agent": .string("codex"), "agent_status": .string("blocked"), "revision": .number(1)]),
            .object(["pane_id": .string("p2"), "terminal_id": .string("term2"), "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(true), "label": .string("done pane"), "agent": .string("claude"), "agent_status": .string("done"), "revision": .number(2)]),
            .object(["pane_id": .string("p3"), "terminal_id": .string("term3"), "workspace_id": .string("w2"), "tab_id": .string("t2"), "focused": .bool(false), "agent_status": .string("idle"), "revision": .number(1)]),
        ],
        layouts: [
            .object([
                "workspace_id": .string("w1"), "tab_id": .string("t1"), "zoomed": .bool(false),
                "focused_pane_id": .string("p2"),
                "area": rect(x: 0, y: 0, width: 100, height: 40),
                "panes": .array([
                    .object(["pane_id": .string("p1"), "focused": .bool(false), "rect": rect(x: 0, y: 0, width: 49, height: 40)]),
                    .object(["pane_id": .string("p2"), "focused": .bool(true), "rect": rect(x: 51, y: 0, width: 49, height: 40)]),
                ]),
                "splits": .array([.object([
                    "id": .string("split_0_root"), "direction": .string("right"), "ratio": .number(0.5),
                    "rect": rect(x: 0, y: 0, width: 100, height: 40),
                ])]),
            ]),
            singlePaneLayout(workspaceID: "w2", tabID: "t2", paneID: "p3"),
        ],
        agents: [
            .object(["pane_id": .string("p1"), "terminal_id": .string("term1"), "workspace_id": .string("w1"), "tab_id": .string("t1"), "focused": .bool(false), "agent": .string("codex"), "name": .string("Codex one"), "agent_status": .string("idle"), "revision": .number(3)]),
            .object(["pane_id": .string("p3"), "terminal_id": .string("term3"), "workspace_id": .string("w2"), "tab_id": .string("t2"), "focused": .bool(false), "display_agent": .string("Claude"), "name": .string("Claude two"), "agent_status": .string("unknown"), "revision": .number(4)]),
        ]
    )

    private static func singlePaneLayout(workspaceID: String, tabID: String, paneID: String) -> JSONValue {
        .object([
            "workspace_id": .string(workspaceID), "tab_id": .string(tabID), "zoomed": .bool(false),
            "focused_pane_id": .string(paneID),
            "area": rect(x: 0, y: 0, width: 100, height: 40),
            "panes": .array([.object([
                "pane_id": .string(paneID), "focused": .bool(true),
                "rect": rect(x: 0, y: 0, width: 100, height: 40),
            ])]),
            "splits": .array([]),
        ])
    }

    private static func rect(x: Int, y: Int, width: Int, height: Int) -> JSONValue {
        .object([
            "x": .number(Double(x)), "y": .number(Double(y)),
            "width": .number(Double(width)), "height": .number(Double(height)),
        ])
    }
}
