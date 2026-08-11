import Foundation
import XCTest

final class OnboardingStateTests: XCTestCase {
    func testOnboardingStepContinuityIsKeyedAndAccessibilityAware() throws {
        let source = try appSource("OnboardingView.swift")

        XCTAssertTrue(source.contains("OnboardingStepRegion"))
        XCTAssertTrue(source.contains(".id(state.step)"))
        XCTAssertTrue(source.contains("initialOffset: 12"))
        XCTAssertTrue(source.contains("withAnimation(BessieDesign.motionExplanatoryEaseOut)"))
        XCTAssertTrue(source.contains("pathFocused = step == .connect"))
        XCTAssertTrue(source.contains("notification: .announcementRequested"))
        XCTAssertTrue(source.contains("connection: .localBessie"))
        XCTAssertTrue(source.contains("Button(path.isEmpty ? \"Choose Folder…\" : \"Change…\")"))
        XCTAssertTrue(source.contains("panel.prompt = \"Choose\""))
        XCTAssertTrue(source.contains("panel.canCreateDirectories = true"))
        XCTAssertTrue(source.contains("Use the Herdr runtime on this Mac"))
        XCTAssertTrue(source.contains(".padding(.horizontal, 18)"))
        XCTAssertTrue(source.contains(".padding(.vertical, 14)"))
        XCTAssertEqual(source.components(separatedBy: ".frame(height: 76)").count - 1, 2)
        XCTAssertTrue(source.contains("ADD REMOTE HERD"))
        XCTAssertEqual(source.components(separatedBy: "Button(\"Back\")").count - 1, 1)
        XCTAssertTrue(source.contains("if state.canNavigateBack { Button(\"Back\")"))
        XCTAssertFalse(source.contains("the local herd is already running"))
        XCTAssertFalse(source.contains(".move(edge:"))
    }

    func testTopLeftBrandTreatmentsUseOnlyTheCowMark() throws {
        let onboarding = try appSource("OnboardingView.swift")
        let rail = try appSource("HerdRail.swift")
        let designSystem = try appSource("BessieDesignSystem.swift")

        XCTAssertFalse(onboarding.contains("Text(\"Bessie\")"))
        XCTAssertFalse(rail.contains("Text(\"Bessie\")"))
        XCTAssertTrue(designSystem.contains("struct BessieBrandMark: View"))
        XCTAssertFalse(designSystem.contains("Text(\"Bessie\")"))
        XCTAssertTrue(designSystem.contains(".accessibilityLabel(\"Bessie\")"))
    }

    func testOnboardingUsesOnlyTransientSetupStateUntilMaterializationSucceeds() throws {
        let onboarding = try appSource("OnboardingView.swift")
        let app = try appSource("BessieApp.swift")
        let settings = try appSource("BessieSettings.swift")

        XCTAssertFalse(onboarding.contains("settings.connections"))
        XCTAssertFalse(onboarding.contains("settings.selectConnectionForSetup"))
        XCTAssertFalse(onboarding.contains("settings.addConnection"))
        XCTAssertFalse(onboarding.contains("settings.selectedConnectionID"))
        XCTAssertTrue(onboarding.contains("@Binding var setupConnection: BessieConnectionDefinition?"))
        XCTAssertTrue(onboarding.contains("connection: .localBessie"))
        XCTAssertTrue(onboarding.contains("Button { prepareAddRemote() } label: {"))
        XCTAssertFalse(app.contains("onboardingCoordinator.attempt?.connectionID"))
        XCTAssertFalse(app.contains("onboardingCoordinator.attempt?.path"))
        XCTAssertFalse(app.contains("connectionID: settings.selectedConnectionID,\n            path: onboardingPath"))
        XCTAssertTrue(app.contains("connectionID: onboardingConnection?.id ?? \"\""))
        XCTAssertTrue(app.contains("settings.beginIsolatedOnboarding()"))
        XCTAssertTrue(app.contains("connections: [connection]"))
        XCTAssertTrue(app.contains("terminalRegistry.focusWhenPresented(paneID: target.paneID) {"))
        XCTAssertTrue(app.contains("// Durable completion persists only after the terminal surface"))
        XCTAssertTrue(app.contains("onboardingCoordinator.completeAfterTerminalFocus(persistCompletion:"))
        XCTAssertTrue(settings.contains("onboarding = OnboardingState()"))
    }

    func testOnboardingCompletionIsLevelTriggeredAndVisiblyWorking() throws {
        let app = try appSource("BessieApp.swift")
        let onboarding = try appSource("OnboardingView.swift")

        // Completion must reconcile on every readiness input, not a single
        // edge: declaration, projection-identity task, ready-pane task, stage
        // change, and the explicit Finish retry of a materialized attempt.
        XCTAssertTrue(app.contains(".task(id: readyTerminalPaneIDs)"))
        XCTAssertTrue(app.contains(".task(id: onboardingReconcileID(projection: projection))"))
        XCTAssertTrue(app.contains(".onChange(of: onboardingCoordinator.stage) { _, _ in reconcileOnboardingCompletion() }"))
        XCTAssertEqual(app.components(separatedBy: "reconcileOnboardingCompletion()").count - 1, 5)
        XCTAssertFalse(app.contains(".task(id: terminalRegistry.controllers.values.contains(where: { $0.hasReadyFrame }))"))

        // Finish must show working state or an error, never silently no-op.
        XCTAssertTrue(app.contains("working: onboardingWorking"))
        XCTAssertFalse(app.contains("guard let onboardingConnection else { return }"))
        XCTAssertTrue(onboarding.contains("Opening your Herdr terminal…"))
    }

    func testProductShellKeepsDurablePresentationOutOfTransientOnboarding() throws {
        let surfaces = try appSource("ProductSurfaces.swift")
        let app = try appSource("BessieApp.swift")

        // Pane pin/snooze reconciliation prunes ledger records missing from
        // fresh snapshots; during transient onboarding the fleet holds only
        // the setup connection, so pruning would destroy durable records.
        XCTAssertTrue(surfaces.contains(
            "private func reconcilePanePresentationsFromFreshSnapshots() {\n        guard settings.onboarding.completed else { return }"
        ))
        // Completion re-runs reconciliation once durable herds are restored.
        XCTAssertTrue(surfaces.contains("reconcilePanePresentationsFromFreshSnapshots()\n            }"))

        // Switching connections during onboarding must not restore durable
        // last-workspace selection into the transient run.
        XCTAssertTrue(surfaces.contains("guard settings.onboarding.completed else {\n            selectedPaneID = nil"))

        // Re-entering onboarding must reset a previously completed coordinator
        // so Finish can actually submit a new run.
        XCTAssertTrue(app.contains("onboardingCoordinator.beginFreshRun()"))
    }

    private func appSource(_ name: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/BessieApp/\(name)"),
            encoding: .utf8
        )
    }
}
