import XCTest

private let ms: UInt64 = 1_000_000

private let leftShiftHeld: EventFlags = [.shift, .deviceLeftShift]
private let rightShiftHeld: EventFlags = [.shift, .deviceRightShift]

private struct Harness {
    var engine: LayerEngine
    private(set) var emitted: [SyntheticKey] = []
    private let capsCode = TriggerKey.capsLock.observedKeyCode!

    init(layout: Layout = Presets.navigation, isEnabled: Bool = true) {
        engine = LayerEngine(layout: layout, isEnabled: isEnabled)
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
    _ d: Disposition, file: StaticString = #filePath,
    line: UInt = #line
) -> UInt16? {
    guard case let .rewrite(keyCode, _) = d else {
        XCTFail("expected rewrite, got \(d)", file: file, line: line); return nil
    }
    return keyCode
}

private func rewrittenFlags(
    _ d: Disposition, file: StaticString = #filePath,
    line: UInt = #line
) -> EventFlags? {
    guard case let .rewrite(_, flags) = d else {
        XCTFail("expected rewrite, got \(d)", file: file, line: line); return nil
    }
    return flags
}

final class LayerEngineBasicsTests: XCTestCase {
    func testHeldTriggerMapsKeys() {
        var h = Harness()
        h.capsDown()
        XCTAssertEqual(rewrittenKey(h.keyDown(KeyCode.h)), KeyCode.leftArrow)
        XCTAssertEqual(rewrittenKey(h.keyDown(KeyCode.j)), KeyCode.downArrow)
    }

    func testKeysPassThroughWhenNothingHeld() {
        var h = Harness()
        XCTAssertEqual(h.keyDown(KeyCode.h), .passThrough)
        XCTAssertEqual(h.keyUp(KeyCode.h), .passThrough)
    }

    func testBaseLayerAloneLeavesKeysAlone() {
        var h = Harness(layout: Layout(name: "t", layers: [Layer(name: "Base")]))
        XCTAssertEqual(h.keyDown(KeyCode.h), .passThrough)
    }

    func testKeyDownAndUpBothRewritten() {
        var h = Harness()
        h.capsDown()
        XCTAssertEqual(rewrittenKey(h.keyDown(KeyCode.j)), KeyCode.downArrow)
        XCTAssertEqual(rewrittenKey(h.keyUp(KeyCode.j)), KeyCode.downArrow)
        XCTAssertFalse(h.engine.hasKeysHeld)
    }

    func testRepeatsAreEachRewrittenWithoutSynthesising() {
        var h = Harness()
        h.capsDown()
        _ = h.keyDown(KeyCode.j)
        for _ in 0..<10 {
            XCTAssertEqual(rewrittenKey(h.keyDown(KeyCode.j, isRepeat: true)), KeyCode.downArrow)
        }
        XCTAssertTrue(h.emitted.isEmpty)
    }

    func testShiftPassesThroughForSelection() {
        var h = Harness()
        h.capsDown()
        XCTAssertEqual(
            rewrittenFlags(h.keyDown(KeyCode.h, flags: [.shift]))?.contains(.shift), true)
    }

    func testAlphaShiftAndDeviceBitsAreCleared() {
        var h = Harness()
        h.capsDown()
        let flags = rewrittenFlags(
            h.keyDown(KeyCode.h, flags: [.alphaShift, .deviceLeftShift, .shift]))
        XCTAssertEqual(flags?.contains(.alphaShift), false)
        XCTAssertEqual(
            flags?.contains(.deviceLeftShift), false,
            "synthetic output must not claim a physical side")
    }

    func testBindingModifiersAreAdded() {
        var h = Harness(layout: Presets.vim)
        h.capsDown()
        let d = h.keyDown(KeyCode.w)
        XCTAssertEqual(rewrittenKey(d), KeyCode.rightArrow)
        XCTAssertEqual(rewrittenFlags(d)?.contains(.option), true)
    }
}

final class LayerEngineHoldModeTests: XCTestCase {
    func testInjectAddsHyperToUnmappedKeys() {
        var h = Harness(layout: Presets.hyperOnly)
        h.capsDown()
        let d = h.keyDown(KeyCode.t)
        XCTAssertEqual(rewrittenKey(d), KeyCode.t)
        for flag in [EventFlags.command, .option, .control, .shift] {
            XCTAssertEqual(rewrittenFlags(d)?.contains(flag), true)
        }
    }

    func testLayerOnlyLeavesUnmappedKeysAlone() {
        var layout = Presets.navigation
        layout.layers[1].holdMode = .layer
        var h = Harness(layout: layout)
        h.capsDown()
        XCTAssertEqual(h.keyDown(KeyCode.t), .passThrough)
    }

    func testMappingWinsOverHyperInjection() {
        var h = Harness()
        h.capsDown()
        XCTAssertEqual(rewrittenFlags(h.keyDown(KeyCode.j))?.contains(.command), false)
        XCTAssertEqual(rewrittenFlags(h.keyDown(KeyCode.t))?.contains(.command), true)
    }
}

final class LayerStackTests: XCTestCase {
    private func stacked() -> Harness { Harness(layout: Presets.stacked) }

    func testBareChordSelectsTheLessSpecificLayer() {
        var h = stacked()
        h.capsDown()
        let d = h.keyDown(KeyCode.h)
        XCTAssertEqual(rewrittenKey(d), KeyCode.leftArrow)
        XCTAssertEqual(rewrittenFlags(d)?.contains(.shift), false)
    }

    func testMoreSpecificChordWins() {
        var h = stacked()
        h.capsDown(flags: leftShiftHeld)
        h.modifiers(leftShiftHeld)
        let d = h.keyDown(KeyCode.h, flags: leftShiftHeld)
        XCTAssertEqual(rewrittenKey(d), KeyCode.leftArrow)
        XCTAssertEqual(
            rewrittenFlags(d)?.contains(.shift), true,
            "the Select layer adds Shift explicitly")
    }

    func testWrongSideDoesNotSelectTheSpecificLayer() {
        var h = stacked()
        h.capsDown(flags: rightShiftHeld)
        h.modifiers(rightShiftHeld)
        let d = h.keyDown(KeyCode.w, flags: rightShiftHeld)
        XCTAssertEqual(rewrittenKey(d), KeyCode.w)
    }

    func testAddingAModifierMidHoldSwitchesLayer() {
        var h = stacked()
        h.capsDown()
        XCTAssertEqual(rewrittenFlags(h.keyDown(KeyCode.h))?.contains(.shift), false)
        _ = h.keyUp(KeyCode.h)

        h.modifiers(leftShiftHeld)
        XCTAssertEqual(
            rewrittenFlags(h.keyDown(KeyCode.h, flags: leftShiftHeld))?
                .contains(.shift), true)
    }

    func testSwitchingLayerMidHoldReleasesHeldOutputs() {
        var h = stacked()
        h.capsDown()
        _ = h.keyDown(KeyCode.h)
        XCTAssertTrue(h.emitted.isEmpty)

        h.modifiers(leftShiftHeld)

        XCTAssertEqual(h.emitted.count, 1)
        XCTAssertEqual(h.emitted.first?.keyCode, KeyCode.leftArrow)
        XCTAssertEqual(h.emitted.first?.isKeyDown, false)
        XCTAssertEqual(h.keyUp(KeyCode.h, flags: leftShiftHeld), .suppress)
    }

    func testHigherLayerWinsAndUnmappedKeysFallThrough() {
        let layout = Layout(
            name: "t",
            layers: [
                Layer(
                    name: "Base", holdMode: .layer,
                    mappings: ["z": .key(KeyBinding(key: "escape"))]),
                Layer(
                    name: "Low", trigger: LayerTrigger(key: .capsLock), holdMode: .layer,
                    mappings: [
                        "a": .key(KeyBinding(key: "home")),
                        "b": .key(KeyBinding(key: "end")),
                    ]),
                Layer(
                    name: "High", trigger: LayerTrigger(key: .capsLock, modifiers: [.leftShift]),
                    holdMode: .layer,
                    mappings: ["a": .key(KeyBinding(key: "pageUp"))]),
            ])
        var h = Harness(layout: layout)
        h.capsDown(flags: leftShiftHeld)
        h.modifiers(leftShiftHeld)

        XCTAssertEqual(rewrittenKey(h.keyDown(KeyCode.a, flags: leftShiftHeld)), KeyCode.pageUp)
        XCTAssertNotEqual(h.keyDown(KeyCode.b, flags: leftShiftHeld), .suppress)
    }

    func testTransparentFallsThroughToLowerLayer() {
        let layout = Layout(
            name: "t",
            layers: [
                Layer(name: "Base"),
                Layer(
                    name: "Low", trigger: LayerTrigger(key: .capsLock), holdMode: .layer,
                    mappings: ["a": .key(KeyBinding(key: "home"))]),
                Layer(
                    name: "High", trigger: LayerTrigger(key: .capsLock, modifiers: [.leftShift]),
                    holdMode: .layer,
                    mappings: ["a": .transparent]),
            ])
        var h = Harness(layout: layout)
        h.capsDown(flags: leftShiftHeld)
        h.modifiers(leftShiftHeld)
        XCTAssertEqual(h.keyDown(KeyCode.a, flags: leftShiftHeld), .passThrough)
    }

    func testBlockedKeyIsSwallowedInBothDirections() {
        let layout = Layout(
            name: "t",
            layers: [
                Layer(name: "Base"),
                Layer(
                    name: "L", trigger: LayerTrigger(key: .capsLock), holdMode: .layer,
                    mappings: ["a": .blocked]),
            ])
        var h = Harness(layout: layout)
        h.capsDown()
        XCTAssertEqual(h.keyDown(KeyCode.a), .suppress)
        XCTAssertEqual(h.keyUp(KeyCode.a), .suppress)
    }

    func testIndependentTriggerKeysCoexist() {
        let layout = Layout(
            name: "t",
            layers: [
                Layer(name: "Base"),
                Layer(
                    name: "Caps", trigger: LayerTrigger(key: .capsLock), holdMode: .layer,
                    mappings: ["a": .key(KeyBinding(key: "home"))]),
                Layer(
                    name: "RCmd", trigger: LayerTrigger(key: .rightCommand), holdMode: .layer,
                    mappings: ["b": .key(KeyBinding(key: "end"))]),
            ])
        var h = Harness(layout: layout)
        h.capsDown()
        XCTAssertEqual(rewrittenKey(h.keyDown(KeyCode.a)), KeyCode.home)

        _ = h.send(
            InputEvent(
                kind: .flagsChanged,
                keyCode: KeyCode.rightCommand, flags: [.command]))
        XCTAssertEqual(rewrittenKey(h.keyDown(KeyCode.b, flags: [.command])), KeyCode.end)
    }
}

final class LayerEngineTapTests: XCTestCase {
    func testQuickTapEmitsTapAction() {
        var h = Harness()
        h.capsDown(at: 0)
        h.capsUp(at: 50 * ms)
        XCTAssertEqual(h.emitted.count, 2)
        XCTAssertEqual(h.emitted.first?.keyCode, KeyCode.escape)
    }

    func testLongHoldIsNotATap() {
        var h = Harness()
        h.capsDown(at: 0)
        h.capsUp(at: 500 * ms)
        XCTAssertTrue(h.emitted.isEmpty)
    }

    func testUsingTheLayerSuppressesTheTap() {
        var h = Harness()
        h.capsDown(at: 0)
        _ = h.keyDown(KeyCode.j)
        _ = h.keyUp(KeyCode.j)
        h.capsUp(at: 30 * ms)
        XCTAssertTrue(h.emitted.isEmpty, "a fast Caps+J must not also fire Escape")
    }

    func testTriggerAutorepeatDoesNotRestartTheTimer() {
        var h = Harness()
        h.capsDown(at: 0)
        h.capsDown(at: 300 * ms)
        h.capsUp(at: 600 * ms)
        XCTAssertTrue(h.emitted.isEmpty)
    }

    func testResetPreventsASpuriousTap() {
        var h = Harness()
        h.capsDown(at: 0)
        h.reset()
        h.capsUp(at: 10 * ms)
        XCTAssertTrue(h.emitted.isEmpty)
    }
}

final class LayerEngineRecoveryTests: XCTestCase {
    func testDisabledPassesEverythingThrough() {
        var h = Harness(isEnabled: false)
        XCTAssertEqual(h.capsDown(), .passThrough)
        XCTAssertEqual(h.keyDown(KeyCode.h), .passThrough)
    }

    func testSyntheticEventsAreIgnored() {
        var h = Harness()
        h.capsDown()
        XCTAssertEqual(
            h.send(InputEvent(kind: .keyDown, keyCode: KeyCode.h, isSynthetic: true)),
            .passThrough)
        XCTAssertFalse(h.engine.hasKeysHeld)
    }

    func testReleasingTriggerFirstReleasesOutputAndSwallowsSourceUp() {
        var h = Harness()
        h.capsDown(at: 0)
        _ = h.keyDown(KeyCode.h)
        XCTAssertEqual(h.capsUp(at: 400 * ms), .suppress)

        XCTAssertEqual(h.emitted.count, 1)
        XCTAssertEqual(h.emitted.first?.isKeyDown, false)
        XCTAssertEqual(h.keyUp(KeyCode.h), .suppress, "no stray 'h' may be typed")
    }

    func testResetReleasesEverything() {
        var h = Harness()
        h.capsDown()
        _ = h.keyDown(KeyCode.k)
        _ = h.keyDown(KeyCode.l)
        h.reset()

        XCTAssertEqual(Set(h.emitted.map(\.keyCode)), [KeyCode.upArrow, KeyCode.rightArrow])
        XCTAssertTrue(h.emitted.allSatisfy { !$0.isKeyDown })
        XCTAssertFalse(h.engine.isLayerActive)
        XCTAssertFalse(h.engine.hasKeysHeld)
    }

    func testEngineWorksAgainAfterReset() {
        var h = Harness()
        h.capsDown()
        _ = h.keyDown(KeyCode.j)
        h.reset()
        h.capsDown()
        XCTAssertEqual(rewrittenKey(h.keyDown(KeyCode.j)), KeyCode.downArrow)
    }

    func testApplyingANewLayoutSwapsBehaviour() {
        var h = Harness()
        h.capsDown()
        XCTAssertEqual(rewrittenKey(h.keyDown(KeyCode.j)), KeyCode.downArrow)
        h.reset()

        h.engine.apply(
            layout: Layout(
                name: "other",
                layers: [
                    Layer(name: "Base"),
                    Layer(
                        name: "L", trigger: LayerTrigger(key: .capsLock), holdMode: .layer,
                        mappings: ["j": .key(KeyBinding(key: "pageDown"))]),
                ]))
        h.capsDown()
        XCTAssertEqual(rewrittenKey(h.keyDown(KeyCode.j)), KeyCode.pageDown)
    }

    func testCapsLockIsObservedAsF18() {
        var h = Harness()
        XCTAssertEqual(
            h.send(
                InputEvent(
                    kind: .flagsChanged, keyCode: KeyCode.capsLock,
                    flags: [.alphaShift])), .passThrough)
        XCTAssertFalse(h.engine.isLayerActive)
        XCTAssertEqual(h.send(InputEvent(kind: .keyDown, keyCode: KeyCode.f18)), .suppress)
        XCTAssertTrue(h.engine.isLayerActive)
    }
}

final class BaseLayerTests: XCTestCase {
    private let a = KeyCatalog.code(for: "a")!
    private let escape = KeyCatalog.code(for: "escape")!
    private let j = KeyCatalog.code(for: "j")!
    private let downArrow = KeyCatalog.code(for: "downArrow")!

    private func layout(
        base: [String: KeyAction],
        baseHoldMode: HoldMode = .layer,
        held: [String: KeyAction] = [:]
    ) -> Layout {
        Layout(
            name: "Test",
            layers: [
                Layer(name: "Base", holdMode: baseHoldMode, mappings: base),
                Layer(
                    name: "Navigation",
                    trigger: LayerTrigger(key: .capsLock),
                    mappings: held),
            ])
    }

    func testBaseMappingAppliesWithNothingHeld() {
        var harness = Harness(layout: layout(base: ["a": .key(KeyBinding(key: "escape"))]))
        XCTAssertEqual(rewrittenKey(harness.keyDown(a)), escape)
    }

    func testBaseMappingRewritesTheKeyUp() {
        var harness = Harness(layout: layout(base: ["a": .key(KeyBinding(key: "escape"))]))
        _ = harness.keyDown(a)
        XCTAssertEqual(rewrittenKey(harness.keyUp(a)), escape)
    }

    func testUnmappedKeysStillPassThrough() {
        var harness = Harness(layout: layout(base: ["a": .key(KeyBinding(key: "escape"))]))
        XCTAssertEqual(harness.keyDown(j), .passThrough)
    }

    func testBaseLayerNeverInjectsHyper() {
        var harness = Harness(layout: layout(base: [:], baseHoldMode: .injectAndLayer))
        XCTAssertEqual(harness.keyDown(j), .passThrough)
    }

    func testHeldLayerWinsOverBase() {
        var harness = Harness(
            layout: layout(
                base: ["j": .key(KeyBinding(key: "escape"))],
                held: ["j": .key(KeyBinding(key: "downArrow"))]
            ))
        XCTAssertEqual(rewrittenKey(harness.keyDown(j)), escape)
        harness.capsDown()
        XCTAssertEqual(rewrittenKey(harness.keyDown(j)), downArrow)
    }

    func testHeldLayerFallsThroughToBase() {
        var harness = Harness(
            layout: layout(
                base: ["a": .key(KeyBinding(key: "escape"))],
                held: ["j": .key(KeyBinding(key: "downArrow"))]
            ))
        harness.capsDown()
        XCTAssertEqual(rewrittenKey(harness.keyDown(a)), escape)
    }

    func testBaseLayerDoesNotCountAsAnActiveLayer() {
        var harness = Harness(layout: layout(base: ["a": .key(KeyBinding(key: "escape"))]))
        XCTAssertFalse(harness.engine.isLayerActive)
        _ = harness.keyDown(a)
        XCTAssertFalse(harness.engine.isLayerActive)
        harness.capsDown()
        XCTAssertTrue(harness.engine.isLayerActive)
    }

    func testBaseMappingSurvivesAReset() {
        var harness = Harness(layout: layout(base: ["a": .key(KeyBinding(key: "escape"))]))
        harness.reset()
        XCTAssertEqual(rewrittenKey(harness.keyDown(a)), escape)
    }
}

final class LayerEngineStrandedStateTests: XCTestCase {

    func testAutorepeatDoesNotAccumulateHeldEntries() {
        var h = Harness()
        h.capsDown()
        XCTAssertEqual(rewrittenKey(h.keyDown(KeyCode.h)), KeyCode.leftArrow)
        for _ in 0..<20 {
            XCTAssertEqual(rewrittenKey(h.keyDown(KeyCode.h, isRepeat: true)), KeyCode.leftArrow)
        }

        h.keyUp(KeyCode.h)
        XCTAssertFalse(h.engine.hasKeysHeld, "one press, one entry, however long it repeats")
    }

    func testReleasingTheTriggerMidRepeatReleasesTheOutputOnce() {
        var h = Harness()
        h.capsDown()
        h.keyDown(KeyCode.h)
        for _ in 0..<10 { h.keyDown(KeyCode.h, isRepeat: true) }

        h.capsUp(at: 5 * ms)

        let releases = h.emitted.filter { $0.keyCode == KeyCode.leftArrow && !$0.isKeyDown }
        XCTAssertEqual(releases.count, 1)
    }

    func testALostKeyUpDoesNotSwallowALaterOrdinaryKeystroke() {
        var h = Harness()
        h.capsDown()
        h.keyDown(KeyCode.h)
        h.capsUp(at: 5 * ms)

        XCTAssertEqual(h.keyDown(KeyCode.h), .passThrough)
        XCTAssertEqual(
            h.keyUp(KeyCode.h), .passThrough,
            "a stranded entry must not eat an unrelated keystroke")
    }

    func testALostTriggerReleaseIsRecoveredByTheNextPress() {
        var h = Harness()
        h.capsDown(at: 0)
        h.keyDown(KeyCode.j)
        h.keyUp(KeyCode.j)

        h.capsDown(at: 10_000 * ms)
        h.capsUp(at: 10_050 * ms)

        let escape = KeyCatalog.code(for: "escape")!
        XCTAssertTrue(
            h.emitted.contains { $0.keyCode == escape && $0.isKeyDown },
            "the trigger should be usable again after a lost release")
        XCTAssertFalse(h.engine.isLayerActive)
    }

    func testTriggerAutorepeatStillDoesNotRearmTheTapTimer() {
        var h = Harness()
        h.capsDown(at: 0)
        for step in 1...5 {
            _ = h.send(
                InputEvent(
                    kind: .keyDown,
                    keyCode: TriggerKey.capsLock.observedKeyCode!,
                    isRepeat: true,
                    timestamp: UInt64(step) * 100 * ms))
        }
        h.capsUp(at: 600 * ms)

        let escape = KeyCatalog.code(for: "escape")!
        XCTAssertFalse(
            h.emitted.contains { $0.keyCode == escape },
            "a long hold is not a tap, however many repeats it sent")
    }
}
