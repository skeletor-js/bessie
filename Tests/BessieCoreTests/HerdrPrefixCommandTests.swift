import XCTest
@testable import BessieCore

final class HerdrPrefixCommandTests: XCTestCase {
    func testPinnedRuntimeIdentityAndBindingCatalogAreExact() {
        XCTAssertEqual(HerdrPrefixCommandCatalog.runtimeIdentity.herdrVersion, "0.8.0")
        XCTAssertEqual(HerdrPrefixCommandCatalog.runtimeIdentity.protocolVersion, 19)
        XCTAssertEqual(
            HerdrPrefixCommandCatalog.runtimeIdentity.sourceRevision,
            "346411fa21afd297f5ed3b3fa56f9e3fbf7654b7"
        )

        let definitions = HerdrPrefixCommandCatalog.definitions
        XCTAssertEqual(Set(definitions.map(\.normalizedBinding)).count, definitions.count)

        let commands = Dictionary(uniqueKeysWithValues: definitions.compactMap { definition in
            switch definition.availability {
            case .supported(let command), .graphicalEquivalent(let command):
                return (definition.normalizedBinding, command)
            case .unavailable:
                return nil
            }
        })
        let expected: [String: HerdrPrefixCommand] = [
            "c": .newTab,
            "n": .nextTab,
            "p": .previousTab,
            "1": .focusTab(1), "2": .focusTab(2), "3": .focusTab(3),
            "4": .focusTab(4), "5": .focusTab(5), "6": .focusTab(6),
            "7": .focusTab(7), "8": .focusTab(8), "9": .focusTab(9),
            "shift+t": .renameTab,
            "shift+x": .closeTab,
            "v": .splitPane(.right),
            "-": .splitPane(.down),
            "h": .focusPane(.left), "j": .focusPane(.down),
            "k": .focusPane(.up), "l": .focusPane(.right),
            "shift+h": .swapPane(.left), "shift+j": .swapPane(.down),
            "shift+k": .swapPane(.up), "shift+l": .swapPane(.right),
            "tab": .cyclePane(.next),
            "shift+tab": .cyclePane(.previous),
            "x": .closePane,
            "z": .toggleZoom,
            "r": .enterResize,
            "shift+p": .renamePane,
            "shift+n": .newWorkspace,
            "shift+w": .renameWorkspace,
            "shift+d": .closeWorkspace,
            "?": .showKeyboardReference,
            "w": .showWorkspacePicker,
            "g": .showCommandPalette,
            "q": .quitBessie,
            "b": .toggleSidebar,
        ]
        XCTAssertEqual(commands, expected)

        let unavailable = Dictionary(uniqueKeysWithValues: definitions.compactMap { definition in
            if case .unavailable(let reason) = definition.availability {
                return (definition.normalizedBinding, reason)
            }
            return nil
        })
        XCTAssertEqual(Set(unavailable.keys), ["[", "e", "s", "o", "shift+r", "shift+g"])
        XCTAssertTrue(unavailable.values.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(definitions.allSatisfy { $0.displaySequence.hasPrefix("Ctrl-B ") })
    }

    func testEveryAvailableBindingReducesToItsTypedCommand() {
        for definition in HerdrPrefixCommandCatalog.definitions {
            let expected: HerdrPrefixReducerOutcome
            switch definition.availability {
            case .supported(.enterResize):
                expected = .enterResize
            case .supported(let command), .graphicalEquivalent(let command):
                expected = .execute(command)
            case .unavailable:
                continue
            }

            var reducer = HerdrPrefixReducer()
            XCTAssertEqual(reducer.handle(Self.prefix), .consume)
            XCTAssertEqual(
                reducer.handle(Self.stroke(for: definition.normalizedBinding)),
                expected,
                "Unexpected reduction for \(definition.normalizedBinding)"
            )
        }
    }

    func testUnavailableAndUnknownSequencesConsumeAndDisarmSilently() {
        let unavailable = HerdrPrefixCommandCatalog.definitions.filter {
            if case .unavailable = $0.availability { return true }
            return false
        }
        for definition in unavailable {
            var reducer = HerdrPrefixReducer()
            XCTAssertEqual(reducer.handle(Self.prefix), .consume)
            XCTAssertEqual(reducer.handle(Self.stroke(for: definition.normalizedBinding)), .consume)
            XCTAssertEqual(reducer.mode, .idle)
        }

        for stroke in [
            BessieShortcutStroke(key: .character("0")),
            BessieShortcutStroke(key: .character("u")),
            BessieShortcutStroke(key: .function(12)),
        ] {
            var reducer = HerdrPrefixReducer()
            _ = reducer.handle(Self.prefix)
            XCTAssertEqual(reducer.handle(stroke), .consume)
            XCTAssertEqual(reducer.mode, .idle)
        }
    }

    func testPrefixEscapeModifierReleaseAndNoTimeoutTransitions() {
        var reducer = HerdrPrefixReducer()
        XCTAssertEqual(reducer.mode, .idle)
        XCTAssertEqual(reducer.handle(Self.prefix), .consume)
        XCTAssertEqual(reducer.mode, .armed)

        XCTAssertEqual(
            reducer.handle(.init(key: .character(""), phase: .modifierOnly)),
            .consume
        )
        XCTAssertEqual(reducer.mode, .armed)
        XCTAssertEqual(
            reducer.handle(.init(key: .character("b"), control: true, phase: .keyUp)),
            .passThrough
        )
        XCTAssertEqual(reducer.mode, .armed)

        // There is deliberately no clock/deadline API. State changes only on input.
        XCTAssertEqual(reducer.mode, .armed)
        XCTAssertEqual(reducer.handle(.init(key: .escape)), .consume)
        XCTAssertEqual(reducer.mode, .idle)
    }

    func testDoubledPrefixAndRepeatSuppressionRemainDistinct() {
        var reducer = HerdrPrefixReducer()
        XCTAssertEqual(reducer.handle(Self.prefix), .consume)
        XCTAssertEqual(reducer.handle(Self.prefix.withRepeat(true)), .consume)
        XCTAssertEqual(reducer.mode, .armed)
        XCTAssertEqual(reducer.handle(Self.prefix), .sendLiteralPrefix)
        XCTAssertEqual(reducer.mode, .idle)
        XCTAssertEqual(reducer.handle(Self.prefix.withRepeat(true)), .consume)

        XCTAssertEqual(reducer.handle(Self.prefix), .consume)
        let create = BessieShortcutStroke(key: .character("c"))
        XCTAssertEqual(reducer.handle(create), .execute(.newTab))
        XCTAssertEqual(reducer.handle(create.withRepeat(true)), .consume)
        XCTAssertEqual(reducer.handle(create), .passThrough)
    }

    func testShiftPunctuationTabBacktabAndMinusNormalization() {
        var reducer = HerdrPrefixReducer()
        _ = reducer.handle(Self.prefix)
        XCTAssertEqual(
            reducer.handle(.init(
                key: .character("/"),
                shift: true,
                layoutCharacter: "?"
            )),
            .execute(.showKeyboardReference)
        )

        reducer = HerdrPrefixReducer()
        _ = reducer.handle(Self.prefix)
        XCTAssertEqual(
            reducer.handle(.init(key: .character("t"), shift: true, layoutCharacter: "T")),
            .execute(.renameTab)
        )

        for (stroke, command) in [
            (BessieShortcutStroke(key: .tab), HerdrPrefixCommand.cyclePane(.next)),
            (BessieShortcutStroke(key: .tab, shift: true), .cyclePane(.previous)),
            (BessieShortcutStroke(key: .backtab), .cyclePane(.previous)),
            (BessieShortcutStroke(key: .minus), .splitPane(.down)),
            (BessieShortcutStroke(key: .keypadMinus), .splitPane(.down)),
        ] {
            reducer = HerdrPrefixReducer()
            _ = reducer.handle(Self.prefix)
            XCTAssertEqual(reducer.handle(stroke), .execute(command))
        }
    }

    func testResizeModeStaysModalAndAllowsOnlyDirectionalExecution() {
        var reducer = HerdrPrefixReducer()
        _ = reducer.handle(Self.prefix)
        XCTAssertEqual(reducer.handle(.init(key: .character("r"))), .enterResize)
        XCTAssertEqual(reducer.mode, .resize)

        // Holding the RHS that entered resize must not immediately exit it.
        XCTAssertEqual(
            reducer.handle(.init(key: .character("r"), isRepeat: true)),
            .consume
        )
        XCTAssertEqual(reducer.mode, .resize)

        let directions: [(BessieShortcutStroke, PaneDirection)] = [
            (.init(key: .character("h")), .left),
            (.init(key: .character("j")), .down),
            (.init(key: .character("k")), .up),
            (.init(key: .character("l")), .right),
            (.init(key: .leftArrow), .left),
            (.init(key: .downArrow, isRepeat: true), .down),
            (.init(key: .upArrow), .up),
            (.init(key: .rightArrow), .right),
        ]
        for (stroke, direction) in directions {
            XCTAssertEqual(reducer.handle(stroke), .execute(.resizePane(direction)))
            XCTAssertEqual(reducer.mode, .resize)
        }

        XCTAssertEqual(reducer.handle(Self.prefix), .consume)
        XCTAssertEqual(reducer.handle(.init(key: .character("u"))), .consume)
        XCTAssertEqual(reducer.mode, .resize)
        XCTAssertEqual(reducer.handle(.init(key: .enter)), .consume)
        XCTAssertEqual(reducer.mode, .idle)

        for exit in [
            BessieShortcutStroke(key: .escape),
            BessieShortcutStroke(key: .enter),
            BessieShortcutStroke(key: .character("r")),
        ] {
            reducer = HerdrPrefixReducer()
            _ = reducer.handle(Self.prefix)
            _ = reducer.handle(.init(key: .character("r")))
            XCTAssertEqual(reducer.handle(exit), .consume)
            XCTAssertEqual(reducer.mode, .idle)
        }
    }

    func testResizePendingQueueIsOrderedBoundedAndResumesAfterDrain() {
        var queue = HerdrResizePendingQueue()
        let pattern: [PaneDirection] = [.left, .down, .up, .right]
        for index in 0..<HerdrResizePendingQueue.capacity {
            XCTAssertTrue(queue.enqueue(pattern[index % pattern.count]))
        }
        XCTAssertEqual(queue.count, 32)
        XCTAssertFalse(queue.enqueue(.left))
        XCTAssertEqual(queue.count, 32)

        XCTAssertEqual(queue.dequeue(), .left)
        XCTAssertEqual(queue.dequeue(), .down)
        XCTAssertEqual(queue.count, 30)
        XCTAssertTrue(queue.enqueue(.right))
        XCTAssertEqual(queue.count, 31)

        var drained: [PaneDirection] = []
        while let direction = queue.dequeue() { drained.append(direction) }
        XCTAssertEqual(drained.last, .right)
        XCTAssertTrue(queue.isEmpty)
    }

    func testResizePendingQueueClearsOnCancellationOrFailure() {
        var queue = HerdrResizePendingQueue()
        XCTAssertTrue(queue.enqueue(.left))
        XCTAssertTrue(queue.enqueue(.right))
        queue.clear()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.dequeue())
    }

    func testResizeDispatchRunDrainsFIFOWithoutOverlappingRequests() throws {
        var run = HerdrResizeDispatchRun(owner: "owner-1")
        XCTAssertTrue(run.enqueue(.left))
        XCTAssertTrue(run.enqueue(.right))
        XCTAssertTrue(run.activate(targetPaneID: "p1", currentOwner: "owner-1"))

        let first = try XCTUnwrap(run.nextStep(currentOwner: "owner-1"))
        XCTAssertEqual(first.paneID, "p1")
        XCTAssertEqual(first.direction, .left)
        XCTAssertNil(run.nextStep(currentOwner: "owner-1"), "Only one resize request may be in flight")

        XCTAssertTrue(run.complete(
            first,
            currentOwner: "owner-1",
            targetStillExists: true
        ))
        let second = try XCTUnwrap(run.nextStep(currentOwner: "owner-1"))
        XCTAssertEqual(second.direction, .right)
        XCTAssertTrue(run.complete(
            second,
            currentOwner: "owner-1",
            targetStillExists: true
        ))
        XCTAssertNil(run.nextStep(currentOwner: "owner-1"))
    }

    func testResizeDispatchRunRejectsStaleCompletionAndOwnerInvalidation() throws {
        var oldRun = HerdrResizeDispatchRun(owner: "owner-1")
        XCTAssertTrue(oldRun.activate(targetPaneID: "p1", currentOwner: "owner-1"))
        XCTAssertTrue(oldRun.enqueue(.left))
        let staleStep = try XCTUnwrap(oldRun.nextStep(currentOwner: "owner-1"))

        var replacement = HerdrResizeDispatchRun(owner: "owner-1")
        XCTAssertTrue(replacement.activate(targetPaneID: "p1", currentOwner: "owner-1"))
        XCTAssertTrue(replacement.enqueue(.right))
        XCTAssertFalse(replacement.complete(
            staleStep,
            currentOwner: "owner-1",
            targetStillExists: true
        ))
        XCTAssertEqual(replacement.pendingCount, 1, "A prior run cannot drain replacement input")

        let current = try XCTUnwrap(replacement.nextStep(currentOwner: "owner-1"))
        XCTAssertFalse(replacement.complete(
            current,
            currentOwner: "owner-2",
            targetStillExists: true
        ))
        replacement.cancel()
        XCTAssertEqual(replacement.pendingCount, 0)
        XCTAssertNil(replacement.nextStep(currentOwner: "owner-1"))
    }

    private static let prefix = BessieShortcutStroke(
        key: .character("b"),
        control: true,
        layoutCharacter: "b"
    )

    private static func stroke(for binding: String) -> BessieShortcutStroke {
        switch binding {
        case "?": return .init(key: .character("/"), shift: true, layoutCharacter: "?")
        case "-": return .init(key: .minus, layoutCharacter: "-")
        case "tab": return .init(key: .tab)
        case "shift+tab": return .init(key: .backtab, shift: true)
        default:
            if binding.hasPrefix("shift+") {
                return .init(
                    key: .character(String(binding.dropFirst("shift+".count))),
                    shift: true
                )
            }
            return .init(key: .character(binding))
        }
    }
}

private extension BessieShortcutStroke {
    func withRepeat(_ isRepeat: Bool) -> Self {
        .init(
            key: key,
            control: control,
            option: option,
            command: command,
            shift: shift,
            layoutCharacter: layoutCharacter,
            phase: phase,
            isRepeat: isRepeat
        )
    }
}
