import XCTest

private let milliseconds: UInt64 = 1_000_000
private let leftShiftHeld: EventFlags = [.shift, .deviceLeftShift]
private let rightShiftHeld: EventFlags = [.shift, .deviceRightShift]

private struct Harness {
    var engine: LayerEngine
    private(set) var emitted: [SyntheticKey] = []
    private let capsCode = TriggerKey.capsLock.observedKeyCode!

    init(profile: Profile = Presets.navigation, isEnabled: Bool = true) {
        engine = LayerEngine(
            profile: profile,
            isEnabled: isEnabled,
            actionAvailability: AllActionsAvailability())
    }

    mutating func send(_ event: InputEvent) -> Disposition {
        var captured: [SyntheticKey] = []
        let disposition = engine.handle(event) { captured.append($0) }
        emitted.append(contentsOf: captured)
        return disposition
    }

    @discardableResult
    mutating func capsDown(at timestamp: UInt64 = 0, flags: EventFlags = []) -> Disposition {
        send(InputEvent(kind: .keyDown, keyCode: capsCode, flags: flags, timestamp: timestamp))
    }

    @discardableResult
    mutating func capsUp(at timestamp: UInt64 = 0, flags: EventFlags = []) -> Disposition {
        send(InputEvent(kind: .keyUp, keyCode: capsCode, flags: flags, timestamp: timestamp))
    }

    @discardableResult
    mutating func modifiers(_ flags: EventFlags) -> Disposition {
        send(InputEvent(kind: .flagsChanged, keyCode: KeyCode.leftShift, flags: flags))
    }

    @discardableResult
    mutating func keyDown(_ code: UInt16, flags: EventFlags = [], isRepeat: Bool = false)
        -> Disposition
    {
        send(InputEvent(kind: .keyDown, keyCode: code, flags: flags, isRepeat: isRepeat))
    }

    @discardableResult
    mutating func keyUp(_ code: UInt16, flags: EventFlags = []) -> Disposition {
        send(InputEvent(kind: .keyUp, keyCode: code, flags: flags))
    }

    mutating func reset() { engine.reset { emitted.append($0) } }
}

private func rewrittenKey(
    _ disposition: Disposition,
    file: StaticString = #filePath,
    line: UInt = #line
) -> UInt16? {
    guard case let .rewrite(keyCode, _) = disposition else {
        XCTFail("expected rewrite, got \(disposition)", file: file, line: line)
        return nil
    }
    return keyCode
}

private func rewrittenFlags(
    _ disposition: Disposition,
    file: StaticString = #filePath,
    line: UInt = #line
) -> EventFlags? {
    guard case let .rewrite(_, flags) = disposition else {
        XCTFail("expected rewrite, got \(disposition)", file: file, line: line)
        return nil
    }
    return flags
}

final class LayerEngineTests: XCTestCase {
    func testHeldTriggerMapsKeyDownAndUp() {
        var harness = Harness()
        harness.capsDown()

        XCTAssertEqual(rewrittenKey(harness.keyDown(KeyCode.h)), KeyCode.leftArrow)
        XCTAssertEqual(rewrittenKey(harness.keyUp(KeyCode.h)), KeyCode.leftArrow)
        XCTAssertFalse(harness.engine.hasKeysHeld)
    }

    func testOrdinaryKeysPassThroughWithoutAnActiveLayer() {
        var harness = Harness()

        XCTAssertEqual(harness.keyDown(KeyCode.h), .passThrough)
        XCTAssertEqual(harness.keyUp(KeyCode.h), .passThrough)
    }

    func testBaseMappingRemainsAvailableUnderAHeldLayer() {
        let layout = Profile(
            name: "Test",
            layers: [
                Layer(
                    name: "Base",
                    mappings: ["a": .action(.sendKey(KeyBinding(key: "escape")))]),
                Layer(
                    name: "Navigation",
                    trigger: LayerTrigger(key: .capsLock),
                    mappings: ["j": .action(.sendKey(KeyBinding(key: "downArrow")))]),
            ])
        var harness = Harness(profile: layout)

        XCTAssertEqual(rewrittenKey(harness.keyDown(KeyCode.a)), KeyCode.escape)
        harness.capsDown()
        XCTAssertEqual(rewrittenKey(harness.keyDown(KeyCode.j)), KeyCode.downArrow)
        XCTAssertEqual(rewrittenKey(harness.keyDown(KeyCode.a)), KeyCode.escape)
    }

    func testMappedKeysKeepInputModifiersAndAddBindingModifiers() {
        var harness = Harness(profile: Presets.vim)
        harness.capsDown()

        let disposition = harness.keyDown(KeyCode.w, flags: [.shift])
        XCTAssertEqual(rewrittenKey(disposition), KeyCode.rightArrow)
        XCTAssertEqual(rewrittenFlags(disposition)?.contains(.shift), true)
        XCTAssertEqual(rewrittenFlags(disposition)?.contains(.option), true)
    }

    func testOutputModesDefineWhatHappensToUnmappedKeys() {
        var legacyHyper = Presets.hyperOnly
        legacyHyper.layers[1].outputMode = .inject
        legacyHyper.layers[1].mappings["h"] = .action(.sendKey(KeyBinding(key: "leftArrow")))
        var legacy = Harness(profile: legacyHyper)
        legacy.capsDown()
        XCTAssertEqual(rewrittenKey(legacy.keyDown(KeyCode.h)), KeyCode.leftArrow)

        var injecting = Harness(profile: Presets.hyperOnly)
        injecting.capsDown()
        let injected = injecting.keyDown(KeyCode.t)
        XCTAssertEqual(rewrittenKey(injected), KeyCode.t)
        for flag in [EventFlags.command, .option, .control, .shift] {
            XCTAssertEqual(rewrittenFlags(injected)?.contains(flag), true)
        }

        var mapping = Presets.navigation
        mapping.layers[1].outputMode = .layer
        var layerOnly = Harness(profile: mapping)
        layerOnly.capsDown()
        XCTAssertEqual(layerOnly.keyDown(KeyCode.t), .passThrough)
    }

    func testModifierSpecificLayerRequiresTheCorrectSide() {
        var left = Harness(profile: Presets.stacked)
        left.capsDown(flags: leftShiftHeld)
        left.modifiers(leftShiftHeld)
        let leftDisposition = left.keyDown(KeyCode.h, flags: leftShiftHeld)
        XCTAssertEqual(rewrittenFlags(leftDisposition)?.contains(.shift), true)

        var right = Harness(profile: Presets.stacked)
        right.capsDown(flags: rightShiftHeld)
        right.modifiers(rightShiftHeld)
        XCTAssertEqual(right.keyDown(KeyCode.w, flags: rightShiftHeld), .passThrough)
    }

    func testChangingLayersReleasesHeldOutput() {
        var harness = Harness(profile: Presets.stacked)
        harness.capsDown()
        _ = harness.keyDown(KeyCode.h)
        harness.modifiers(leftShiftHeld)

        XCTAssertEqual(harness.emitted.count, 1)
        XCTAssertEqual(harness.emitted.first?.keyCode, KeyCode.leftArrow)
        XCTAssertFalse(harness.emitted.first?.isKeyDown ?? true)
        XCTAssertEqual(harness.keyUp(KeyCode.h, flags: leftShiftHeld), .suppress)
    }

    func testTransparentAndBlockedActionsHaveDifferentSemantics() {
        let transparentLayout = Profile(
            name: "Transparent",
            layers: [
                Layer(name: "Base"),
                Layer(
                    name: "Navigation",
                    trigger: LayerTrigger(key: .capsLock),
                    mappings: ["a": .action(.sendKey(KeyBinding(key: "home")))]),
                Layer(
                    name: "Override",
                    trigger: LayerTrigger(key: .capsLock, modifiers: [.leftShift]),
                    outputMode: .layer,
                    mappings: ["a": .transparent]),
            ])
        var transparent = Harness(profile: transparentLayout)
        transparent.capsDown(flags: leftShiftHeld)
        transparent.modifiers(leftShiftHeld)
        XCTAssertEqual(transparent.keyDown(KeyCode.a, flags: leftShiftHeld), .passThrough)

        let blockedLayout = Profile(
            name: "Blocked",
            layers: [
                Layer(name: "Base"),
                Layer(
                    name: "Navigation",
                    trigger: LayerTrigger(key: .capsLock),
                    outputMode: .layer,
                    mappings: ["a": .blocked]),
            ])
        var blocked = Harness(profile: blockedLayout)
        blocked.capsDown()
        XCTAssertEqual(blocked.keyDown(KeyCode.a), .suppress)
        XCTAssertEqual(blocked.keyUp(KeyCode.a), .suppress)
    }

    func testTapAndHoldHaveDifferentResults() {
        var tap = Harness()
        tap.capsDown(at: 0)
        tap.capsUp(at: 50 * milliseconds)
        XCTAssertEqual(tap.emitted.map(\.keyCode), [KeyCode.escape, KeyCode.escape])

        var hold = Harness()
        hold.capsDown(at: 0)
        hold.capsUp(at: 500 * milliseconds)
        XCTAssertTrue(hold.emitted.isEmpty)
    }

    func testModifierSpecificTapActionWinsAtTriggerDown() {
        let layout = Profile(
            name: "Tap actions",
            layers: [
                Layer(name: "Base"),
                Layer(
                    name: "General",
                    trigger: LayerTrigger(key: .capsLock),
                    tapAction: .sendKey(KeyBinding(key: "escape"))),
                Layer(
                    name: "Shift",
                    trigger: LayerTrigger(key: .capsLock, modifiers: [.leftShift]),
                    tapAction: .sendKey(KeyBinding(key: "tab"))),
            ])
        var harness = Harness(profile: layout)

        harness.capsDown(at: 0, flags: leftShiftHeld)
        XCTAssertEqual(
            harness.capsUp(at: 50 * milliseconds, flags: leftShiftHeld),
            .suppress)
        let tabCode = KeyCatalog.code(for: "tab")!
        XCTAssertEqual(harness.emitted.map(\.keyCode), [tabCode, tabCode])
    }

    func testToggleTapKeepsLayerActiveUntilToggledAgain() {
        let layout = Profile(
            name: "Toggle",
            layers: [
                Layer(name: "Base"),
                Layer(
                    name: "Navigation",
                    trigger: LayerTrigger(key: .capsLock),
                    outputMode: .layer,
                    tapAction: .toggleLayer(.current),
                    mappings: ["h": .action(.sendKey(KeyBinding(key: "leftArrow")))]),
            ])
        var harness = Harness(profile: layout)

        harness.capsDown(at: 0)
        harness.capsUp(at: 50 * milliseconds)
        XCTAssertTrue(harness.engine.isLayerActive)
        XCTAssertEqual(
            harness.engine.activeLayerStates,
            [LayerActivity(index: 1, isHeld: false, isToggled: true, isOneShot: false)])
        XCTAssertEqual(rewrittenKey(harness.keyDown(KeyCode.h)), KeyCode.leftArrow)
        _ = harness.keyUp(KeyCode.h)

        harness.capsDown(at: 100 * milliseconds)
        harness.capsUp(at: 150 * milliseconds)
        XCTAssertFalse(harness.engine.isLayerActive)
        XCTAssertTrue(harness.engine.activeLayerStates.isEmpty)
        XCTAssertEqual(harness.keyDown(KeyCode.h), .passThrough)
    }

    func testOneShotTapAppliesToOneOrdinaryKeypress() {
        let layout = Profile(
            name: "One-shot",
            layers: [
                Layer(name: "Base"),
                Layer(
                    name: "Navigation",
                    trigger: LayerTrigger(key: .capsLock),
                    outputMode: .layer,
                    tapAction: .oneShotLayer(.current),
                    mappings: ["h": .action(.sendKey(KeyBinding(key: "leftArrow")))]),
            ])
        var harness = Harness(profile: layout)

        harness.capsDown(at: 0)
        harness.capsUp(at: 50 * milliseconds)
        XCTAssertTrue(harness.engine.isLayerActive)
        XCTAssertEqual(
            harness.engine.activeLayerStates,
            [LayerActivity(index: 1, isHeld: false, isToggled: false, isOneShot: true)])
        harness.modifiers(leftShiftHeld)
        let disposition = harness.keyDown(KeyCode.h, flags: leftShiftHeld)
        XCTAssertEqual(rewrittenKey(disposition), KeyCode.leftArrow)
        XCTAssertTrue(rewrittenFlags(disposition)?.contains(.shift) == true)
        _ = harness.keyUp(KeyCode.h)
        harness.modifiers([])
        XCTAssertFalse(harness.engine.isLayerActive)
        XCTAssertTrue(harness.engine.activeLayerStates.isEmpty)
        XCTAssertEqual(harness.keyDown(KeyCode.h), .passThrough)
    }

    func testResetClearsPersistentTapActionState() {
        let layout = Profile(
            name: "Reset",
            layers: [
                Layer(name: "Base"),
                Layer(
                    name: "Navigation",
                    trigger: LayerTrigger(key: .capsLock),
                    outputMode: .layer,
                    tapAction: .toggleLayer(.current),
                    mappings: ["h": .action(.sendKey(KeyBinding(key: "leftArrow")))]),
            ])
        var harness = Harness(profile: layout)

        harness.capsDown(at: 0)
        harness.capsUp(at: 50 * milliseconds)
        XCTAssertTrue(harness.engine.isLayerActive)
        harness.reset()

        XCTAssertFalse(harness.engine.isLayerActive)
        XCTAssertEqual(harness.keyDown(KeyCode.h), .passThrough)
    }

    func testUsingALayerSuppressesTheTap() {
        var harness = Harness()
        harness.capsDown(at: 0)
        _ = harness.keyDown(KeyCode.j)
        _ = harness.keyUp(KeyCode.j)
        harness.capsUp(at: 30 * milliseconds)

        XCTAssertTrue(harness.emitted.isEmpty)
    }

    func testReleasingTheTriggerDoesNotLeakTheSourceKey() {
        var harness = Harness()
        harness.capsDown(at: 0)
        _ = harness.keyDown(KeyCode.h)
        XCTAssertEqual(harness.capsUp(at: 400 * milliseconds), .suppress)

        XCTAssertEqual(harness.emitted.count, 1)
        XCTAssertFalse(harness.emitted[0].isKeyDown)
        XCTAssertEqual(harness.keyUp(KeyCode.h), .suppress)
    }

    func testResetReleasesStateAndAllowsTheEngineToBeUsedAgain() {
        var harness = Harness()
        harness.capsDown()
        _ = harness.keyDown(KeyCode.j)
        harness.reset()

        XCTAssertEqual(harness.emitted.map(\.keyCode), [KeyCode.downArrow])
        XCTAssertFalse(harness.emitted[0].isKeyDown)
        XCTAssertFalse(harness.engine.isLayerActive)
        XCTAssertFalse(harness.engine.hasKeysHeld)

        harness.capsDown()
        XCTAssertEqual(rewrittenKey(harness.keyDown(KeyCode.j)), KeyCode.downArrow)
    }

    func testRepeatsDoNotCreateExtraHeldState() {
        var harness = Harness()
        harness.capsDown()
        _ = harness.keyDown(KeyCode.h)
        for _ in 0..<20 {
            XCTAssertEqual(
                rewrittenKey(harness.keyDown(KeyCode.h, isRepeat: true)), KeyCode.leftArrow)
        }

        _ = harness.keyUp(KeyCode.h)
        XCTAssertFalse(harness.engine.hasKeysHeld)
        XCTAssertTrue(harness.emitted.isEmpty)
    }

    func testDisabledAndSyntheticInputPassThrough() {
        var disabled = Harness(isEnabled: false)
        XCTAssertEqual(disabled.capsDown(), .passThrough)
        XCTAssertEqual(disabled.keyDown(KeyCode.h), .passThrough)

        var synthetic = Harness()
        synthetic.capsDown()
        XCTAssertEqual(
            synthetic.send(InputEvent(kind: .keyDown, keyCode: KeyCode.h, isSynthetic: true)),
            .passThrough)
        XCTAssertFalse(synthetic.engine.hasKeysHeld)
    }

    func testCapsLockFlagsEventIsObservedAsTheConfiguredTriggerKey() {
        var harness = Harness()
        XCTAssertEqual(
            harness.send(
                InputEvent(
                    kind: .flagsChanged,
                    keyCode: KeyCode.capsLock,
                    flags: [.alphaShift])),
            .passThrough)
        XCTAssertFalse(harness.engine.isLayerActive)

        XCTAssertEqual(harness.send(InputEvent(kind: .keyDown, keyCode: KeyCode.f18)), .suppress)
        XCTAssertTrue(harness.engine.isLayerActive)
    }
}

final class MacActionEngineTests: XCTestCase {
    func testActionFiresOnceAndConsumesReleaseAfterApplicationAndLicenseChange() {
        let entitlement = LicenseEntitlement()
        entitlement.setProAccess(true)
        let action = MacAction.application(
            NamedActionTarget(id: "com.apple.Safari", name: "Safari"))
        var profile = Presets.navigation
        profile.layers[0].mappings["a"] = .action(.macAction(action))
        profile.layers[0].applications["com.apple.Safari"] = ApplicationOverride(
            name: "Safari", mappings: ["a": .action(.sendKey(KeyBinding(key: "b")))])
        var engine = LayerEngine(profile: profile, actionAvailability: entitlement)
        XCTAssertEqual(
            engine.handle(InputEvent(kind: .keyDown, keyCode: KeyCode.a)) { _ in }, .suppress)
        XCTAssertEqual(engine.takePendingActions(), [action])
        engine.updateApplication("com.apple.Safari")
        entitlement.setProAccess(false)
        XCTAssertEqual(
            engine.handle(InputEvent(kind: .keyDown, keyCode: KeyCode.a, isRepeat: true)) { _ in },
            .suppress)
        XCTAssertTrue(engine.takePendingActions().isEmpty)
        XCTAssertEqual(
            engine.handle(InputEvent(kind: .keyUp, keyCode: KeyCode.a)) { _ in }, .suppress)
        engine.updateApplication(nil)
        XCTAssertEqual(
            engine.handle(InputEvent(kind: .keyDown, keyCode: KeyCode.a)) { _ in }, .suppress)
        XCTAssertTrue(engine.takePendingActions().isEmpty)
        XCTAssertEqual(
            engine.handle(InputEvent(kind: .keyUp, keyCode: KeyCode.a)) { _ in }, .suppress)
        engine.isEnabled = false
        XCTAssertEqual(
            engine.handle(InputEvent(kind: .keyDown, keyCode: KeyCode.a)) { _ in }, .passThrough)
    }

    func testTapActionOnlyRunsForAnUnusedTapAndResetDiscardsQueuedActions() {
        let action = MacAction.url("https://tenuo.app")
        var profile = Presets.navigation
        profile.layers[1].tapAction = .macAction(action)
        var engine = LayerEngine(profile: profile, actionAvailability: AllActionsAvailability())
        let caps = TriggerKey.capsLock.observedKeyCode!
        _ = engine.handle(InputEvent(kind: .keyDown, keyCode: caps, timestamp: 0)) { _ in }
        _ = engine.handle(InputEvent(kind: .keyUp, keyCode: caps, timestamp: 50_000_000)) { _ in }
        XCTAssertEqual(engine.takePendingActions(), [action])
        _ = engine.handle(InputEvent(kind: .keyDown, keyCode: caps, timestamp: 100_000_000)) { _ in
        }
        _ = engine.handle(InputEvent(kind: .keyDown, keyCode: KeyCode.h, timestamp: 110_000_000)) {
            _ in
        }
        _ = engine.handle(InputEvent(kind: .keyUp, keyCode: caps, timestamp: 150_000_000)) { _ in }
        XCTAssertTrue(engine.takePendingActions().isEmpty)
        _ = engine.handle(InputEvent(kind: .keyDown, keyCode: caps, timestamp: 200_000_000)) { _ in
        }
        _ = engine.handle(InputEvent(kind: .keyUp, keyCode: caps, timestamp: 250_000_000)) { _ in }
        engine.reset { _ in }
        XCTAssertTrue(engine.takePendingActions().isEmpty)
    }

    func testMacActionsSurviveProfileRoundTripAndInvalidTargetsAreRejected() throws {
        let actions: [MacAction] = [
            .application(NamedActionTarget(id: "com.apple.Safari", name: "Safari")),
            .file(FileActionTarget(bookmark: Data([1, 2, 3]), name: "Project")),
            .url("https://tenuo.app/docs"),
            .shortcut(NamedActionTarget(id: UUID().uuidString, name: "Start work")),
        ]
        for action in actions {
            var profile = Presets.navigation
            profile.layers[1].mappings["a"] = .action(.macAction(action))
            profile.layers[1].applications["com.apple.Safari"] = ApplicationOverride(
                name: "Safari", mappings: ["b": .action(.macAction(action))])
            try profile.validate()
            XCTAssertEqual(
                try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile)), profile
            )
        }
        var profile = Presets.navigation
        profile.layers[0].mappings["a"] = .action(.macAction(.url("javascript:alert(1)")))
        XCTAssertThrowsError(try profile.validate())
        profile.layers[0].mappings["a"] = .action(
            .macAction(.shortcut(NamedActionTarget(id: "--help", name: "Invalid"))))
        XCTAssertThrowsError(try profile.validate())
        let legacy = Data(#"{"key":"a","modifiers":[]}"#.utf8)
        XCTAssertEqual(
            try JSONDecoder().decode(Action.self, from: legacy), .sendKey(KeyBinding(key: "a")))
    }

    func testFileBookmarkResolvesAfterRenameAndRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("Original.txt")
        try Data("Tenuo bookmark test".utf8).write(to: original)
        let target = FileActionTarget(
            bookmark: try original.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil, relativeTo: nil),
            name: original.lastPathComponent)
        let restored = try JSONDecoder().decode(
            FileActionTarget.self, from: JSONEncoder().encode(target))
        let renamed = directory.appendingPathComponent("Renamed.txt")
        try FileManager.default.moveItem(at: original, to: renamed)
        var stale = false
        let resolved = try URL(
            resolvingBookmarkData: restored.bookmark,
            options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        XCTAssertEqual(resolved.standardizedFileURL, renamed.standardizedFileURL)
    }
}
