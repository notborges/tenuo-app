import XCTest

private let milliseconds: UInt64 = 1_000_000
private let leftShiftHeld: EventFlags = [.shift, .deviceLeftShift]
private let rightShiftHeld: EventFlags = [.shift, .deviceRightShift]

private struct Harness {
    var engine: LayerEngine
    private(set) var emitted: [SyntheticKey] = []
    private let capsCode = TriggerKey.capsLock.observedKeyCode!

    init(profile: Profile = Presets.navigation, isEnabled: Bool = true) {
        engine = LayerEngine(profile: profile, isEnabled: isEnabled)
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
                    mappings: ["a": .key(KeyBinding(key: "escape"))]),
                Layer(
                    name: "Navigation",
                    trigger: LayerTrigger(key: .capsLock),
                    mappings: ["j": .key(KeyBinding(key: "downArrow"))]),
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

    func testHoldModesDefineWhatHappensToUnmappedKeys() {
        var injecting = Harness(profile: Presets.hyperOnly)
        injecting.capsDown()
        let injected = injecting.keyDown(KeyCode.t)
        XCTAssertEqual(rewrittenKey(injected), KeyCode.t)
        for flag in [EventFlags.command, .option, .control, .shift] {
            XCTAssertEqual(rewrittenFlags(injected)?.contains(flag), true)
        }

        var mapping = Presets.navigation
        mapping.layers[1].holdMode = .layer
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
        XCTAssertEqual(rewrittenKey(right.keyDown(KeyCode.w, flags: rightShiftHeld)), KeyCode.w)
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
                    mappings: ["a": .key(KeyBinding(key: "home"))]),
                Layer(
                    name: "Override",
                    trigger: LayerTrigger(key: .capsLock, modifiers: [.leftShift]),
                    holdMode: .layer,
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
                    holdMode: .layer,
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
