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

    func testSyncBoundaryWaitsForTriggersMappedReleasesAndPersistentLayers() {
        var harness = Harness()
        XCTAssertTrue(harness.engine.isQuiescent)
        harness.capsDown()
        XCTAssertFalse(harness.engine.isQuiescent)
        harness.keyDown(KeyCode.h)
        harness.capsUp(at: 500 * milliseconds)
        XCTAssertFalse(harness.engine.isQuiescent)
        harness.keyUp(KeyCode.h)
        XCTAssertTrue(harness.engine.isQuiescent)
        var profile = Presets.navigation
        profile.layers[1].tapAction = .toggleLayer(.current)
        harness = Harness(profile: profile)
        harness.capsDown()
        harness.capsUp(at: 50 * milliseconds)
        XCTAssertFalse(harness.engine.isQuiescent)
        harness.reset()
        XCTAssertTrue(harness.engine.isQuiescent)
        profile.layers[1].tapAction = .oneShotLayer(.current)
        harness = Harness(profile: profile)
        harness.capsDown()
        harness.capsUp(at: 50 * milliseconds)
        XCTAssertFalse(harness.engine.isQuiescent)
        harness.keyDown(KeyCode.h)
        XCTAssertFalse(harness.engine.isQuiescent)
        harness.keyUp(KeyCode.h)
        XCTAssertTrue(harness.engine.isQuiescent)
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
        XCTAssertTrue(harness.emitted.isEmpty)
        XCTAssertEqual(rewrittenKey(harness.keyUp(KeyCode.h)), KeyCode.leftArrow)
        harness.modifiers([])
        XCTAssertFalse(harness.engine.isLayerActive)
        XCTAssertTrue(harness.engine.activeLayerStates.isEmpty)
        XCTAssertEqual(harness.keyDown(KeyCode.h), .passThrough)

        let binding = KeyBinding(key: "b", modifiers: [.control, .option, .command])
        var modifierLayout = layout
        modifierLayout.layers[1].mappings["function"] = .action(.sendKey(binding))
        harness = Harness(profile: modifierLayout)
        harness.capsDown()
        harness.capsUp(at: 50 * milliseconds)
        XCTAssertEqual(
            harness.send(
                InputEvent(kind: .flagsChanged, keyCode: KeyCode.function, flags: [.secondaryFn])),
            .replace(kind: .keyDown, keyCode: KeyCode.b, flags: binding.flags))
        XCTAssertTrue(harness.emitted.isEmpty)
        XCTAssertFalse(harness.engine.isLayerActive)
        XCTAssertEqual(
            harness.send(InputEvent(kind: .flagsChanged, keyCode: KeyCode.function)),
            .replace(kind: .keyUp, keyCode: KeyCode.b, flags: binding.flags))
        XCTAssertTrue(harness.engine.isQuiescent)
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

    func testModifierMappingsProduceKeyEventsAndConsumeOnlyTheirOwnSide() throws {
        let pairs: [(TriggerKey, TriggerKey?)] = [
            (.leftControl, .rightControl), (.rightControl, .leftControl),
            (.leftOption, .rightOption), (.rightOption, .leftOption),
            (.leftCommand, .rightCommand), (.rightCommand, .leftCommand),
            (.leftShift, .rightShift), (.rightShift, .leftShift), (.function, nil),
        ]
        for (source, opposite) in pairs {
            let code = try XCTUnwrap(source.physicalKeyCode)
            let sourceFlags = source.modifierFlag!.union(source.deviceFlag ?? [])
            let oppositeFlags = opposite.map { $0.modifierFlag!.union($0.deviceFlag ?? []) } ?? []
            let profile = Profile(
                name: "Modifiers",
                layers: [
                    Layer(
                        name: "Base",
                        mappings: [source.rawValue: .action(.sendKey(KeyBinding(key: "a")))])
                ])
            var harness = Harness(profile: profile)
            let down = InputEvent(kind: .flagsChanged, keyCode: code, flags: sourceFlags)
            XCTAssertEqual(
                harness.send(down), .replace(kind: .keyDown, keyCode: KeyCode.a, flags: []))
            XCTAssertEqual(harness.send(down), .suppress)
            XCTAssertEqual(
                harness.keyDown(KeyCode.h, flags: sourceFlags.union(oppositeFlags)),
                .rewrite(keyCode: KeyCode.h, flags: oppositeFlags))
            if let oppositeCode = opposite?.physicalKeyCode {
                XCTAssertEqual(
                    harness.send(
                        InputEvent(
                            kind: .flagsChanged, keyCode: oppositeCode,
                            flags: sourceFlags.union(oppositeFlags))),
                    .rewrite(keyCode: oppositeCode, flags: oppositeFlags))
            }
            XCTAssertEqual(
                harness.send(InputEvent(kind: .flagsChanged, keyCode: code, flags: oppositeFlags)),
                .replace(
                    kind: .keyUp, keyCode: KeyCode.a,
                    flags: oppositeFlags.subtracting(.allDeviceBits)))
            XCTAssertTrue(harness.emitted.isEmpty)
            XCTAssertFalse(harness.engine.hasPendingReleases)
        }
    }

    func testModifierMappingsUseLayerPrecedenceAndRawTriggerRequirements() {
        let shortcut = KeyBinding(key: "b", modifiers: [.control, .option, .command])
        let flags: EventFlags = [.control, .deviceLeftControl]
        let profile = Profile(
            name: "Layers",
            layers: [
                Layer(
                    name: "Base", mappings: ["leftControl": .action(.sendKey(KeyBinding(key: "a")))]
                ),
                Layer(
                    name: "Dictation", trigger: LayerTrigger(key: .key("t")),
                    mappings: ["leftControl": .action(.sendKey(shortcut))]),
                Layer(
                    name: "Chord", trigger: LayerTrigger(key: .key("h"), modifiers: [.leftControl]),
                    mappings: ["c": .action(.sendKey(KeyBinding(key: "escape")))]),
            ])
        var harness = Harness(profile: profile)
        XCTAssertEqual(harness.keyDown(KeyCode.t), .suppress)
        XCTAssertEqual(
            harness.send(
                InputEvent(kind: .flagsChanged, keyCode: KeyCode.leftControl, flags: flags)),
            .replace(kind: .keyDown, keyCode: KeyCode.b, flags: shortcut.flags))
        // The consumed modifier still participates in physical trigger matching.
        XCTAssertEqual(harness.keyDown(KeyCode.h, flags: flags), .suppress)
        XCTAssertTrue(harness.engine.isActive(layerIndex: 2))
        XCTAssertEqual(
            harness.emitted,
            [SyntheticKey(keyCode: KeyCode.b, flags: shortcut.flags, isKeyDown: false)])
        XCTAssertEqual(harness.keyUp(KeyCode.h, flags: flags), .suppress)
        XCTAssertEqual(harness.keyUp(KeyCode.t, flags: flags), .suppress)
        XCTAssertEqual(
            harness.send(InputEvent(kind: .flagsChanged, keyCode: KeyCode.leftControl)), .suppress)
        XCTAssertEqual(harness.emitted.count, 1)
        XCTAssertEqual(
            harness.send(
                InputEvent(kind: .flagsChanged, keyCode: KeyCode.leftControl, flags: flags)),
            .replace(kind: .keyDown, keyCode: KeyCode.a, flags: []))
        XCTAssertEqual(
            harness.send(InputEvent(kind: .flagsChanged, keyCode: KeyCode.leftControl)),
            .replace(kind: .keyUp, keyCode: KeyCode.a, flags: []))

        // A consumed release must still update chords which depend on this
        // physical modifier's state after a profile change.
        _ = harness.send(
            InputEvent(kind: .flagsChanged, keyCode: KeyCode.leftControl, flags: flags))
        harness.reset()
        harness.engine.apply(profile: profile)
        harness.keyDown(KeyCode.h, flags: flags)
        XCTAssertTrue(harness.engine.isActive(layerIndex: 2))
        let c = KeyCatalog.code(for: "c")!
        XCTAssertEqual(rewrittenKey(harness.keyDown(c, flags: flags)), KeyCode.escape)
        XCTAssertEqual(
            harness.send(InputEvent(kind: .flagsChanged, keyCode: KeyCode.leftControl)), .suppress)
        XCTAssertFalse(harness.engine.isActive(layerIndex: 2))
        XCTAssertEqual(
            harness.emitted.last, SyntheticKey(keyCode: KeyCode.escape, flags: [], isKeyDown: false)
        )
        XCTAssertEqual(harness.keyUp(c), .suppress)
    }

    func testCleanupBalancesOutputsAndDrainsSourcesAcrossProfileDisableAndRecovery() throws {
        let sources: [TriggerKey] = [.key("a"), .capsLock, .leftControl, .function]
        for source in sources {
            for cleanup in ["profile", "disable", "recovery"] {
                let code = try XCTUnwrap(source.observedKeyCode)
                let flags = (source.modifierFlag ?? []).union(source.deviceFlag ?? [])
                let kind: InputEvent.Kind = source.isModifier ? .flagsChanged : .keyDown
                let binding = KeyBinding(key: "b", modifiers: [.command])
                let profile = Profile(
                    name: "Mapped",
                    layers: [
                        Layer(name: "Base", mappings: [source.rawValue: .action(.sendKey(binding))])
                    ])
                var harness = Harness(profile: profile)
                let press = InputEvent(kind: kind, keyCode: code, flags: flags)
                _ = harness.send(press)
                harness.reset()
                XCTAssertEqual(
                    harness.emitted,
                    [SyntheticKey(keyCode: KeyCode.b, flags: binding.flags, isKeyDown: false)])
                XCTAssertTrue(harness.engine.hasPendingReleases)
                if cleanup == "profile" {
                    harness.engine.apply(
                        profile: Profile(
                            name: "Trigger",
                            layers: [
                                Layer(name: "Base"),
                                Layer(
                                    name: "Layer", trigger: LayerTrigger(key: source),
                                    tapAction: .toggleLayer(.current)),
                            ]))
                } else if cleanup == "disable" {
                    harness.engine.isEnabled = false
                } else {
                    harness.engine.reconcilePhysicalState(keysDown: [code])
                }
                var repeated = press
                repeated.isRepeat = true
                XCTAssertEqual(harness.send(repeated), .suppress)
                if source.isModifier {
                    XCTAssertEqual(
                        harness.keyDown(KeyCode.h, flags: flags),
                        .rewrite(keyCode: KeyCode.h, flags: []))
                }
                if cleanup == "recovery" {
                    harness.engine.reconcilePhysicalState()
                } else {
                    XCTAssertEqual(
                        harness.send(
                            InputEvent(
                                kind: source.isModifier ? .flagsChanged : .keyUp, keyCode: code)),
                        .suppress)
                    XCTAssertFalse(harness.engine.isLayerActive)
                }
                XCTAssertFalse(harness.engine.hasPendingReleases)
                harness.reset()
                XCTAssertEqual(harness.emitted.count, 1)
            }
        }
    }

    func testCapsLockUsesMappingsOverridesAndNativeFallbackUntilBridgeIsRemoved() {
        let binding = KeyBinding(key: "b", modifiers: [.control, .option, .command])
        var layer = Layer(
            name: "Dictation", trigger: LayerTrigger(key: .key("t")),
            mappings: ["capsLock": .action(.sendKey(binding))])
        layer.applications["com.apple.Safari"] = ApplicationOverride(
            name: "Safari", mappings: ["capsLock": .transparent])
        let profile = Profile(name: "Caps Lock", layers: [Layer(name: "Base"), layer])
        var harness = Harness(profile: profile)
        // Interpret bridge events correctly before installation's callback.
        harness.engine.isCapsLockRemapped = false
        XCTAssertEqual(harness.capsDown(), .toggleCapsLock)
        XCTAssertEqual(harness.keyDown(KeyCode.f18, isRepeat: true), .suppress)
        XCTAssertEqual(harness.capsUp(), .suppress)
        harness.keyDown(KeyCode.t)
        XCTAssertEqual(
            harness.capsDown(flags: [.secondaryFn]),
            .rewrite(keyCode: KeyCode.b, flags: binding.flags))
        harness.engine.updateApplication("com.apple.Safari")
        XCTAssertEqual(
            harness.capsUp(flags: [.secondaryFn]),
            .rewrite(keyCode: KeyCode.b, flags: binding.flags))
        XCTAssertEqual(harness.capsDown(), .toggleCapsLock)
        XCTAssertEqual(harness.capsUp(), .suppress)
        harness.engine.updateApplication(nil)
        _ = harness.send(
            InputEvent(kind: .flagsChanged, keyCode: KeyCode.function, flags: [.secondaryFn]))
        XCTAssertEqual(
            harness.capsDown(flags: [.secondaryFn]),
            .rewrite(keyCode: KeyCode.b, flags: binding.flags.union(.secondaryFn)))
        XCTAssertEqual(
            harness.capsUp(flags: [.secondaryFn]),
            .rewrite(keyCode: KeyCode.b, flags: binding.flags.union(.secondaryFn)))
        _ = harness.send(InputEvent(kind: .flagsChanged, keyCode: KeyCode.function))
        harness.keyUp(KeyCode.t)
        harness.reset()
        harness.engine.isCapsLockRemapped = true
        harness.engine.apply(
            profile: Profile(name: "No Caps mapping", layers: [Layer(name: "Base")]))
        harness.engine.isEnabled = false
        XCTAssertEqual(harness.capsDown(), .toggleCapsLock)
        XCTAssertEqual(harness.capsUp(), .suppress)
        harness.engine.isCapsLockRemapped = false
        XCTAssertEqual(harness.capsDown(), .passThrough)
        XCTAssertEqual(harness.capsUp(), .passThrough)
    }
}

final class MacActionEngineTests: XCTestCase {
    func testActionFiresOnceAndConsumesReleaseAfterApplicationAndLicenseChange() {
        let action = MacAction.application(
            NamedActionTarget(id: "com.apple.Safari", name: "Safari"))
        for source in [TriggerKey.key("a"), .capsLock, .leftControl, .function] {
            let entitlement = LicenseEntitlement()
            entitlement.setProAccess(true)
            let code = source.observedKeyCode!
            let flags = (source.modifierFlag ?? []).union(source.deviceFlag ?? [])
            let down = InputEvent(
                kind: source.isModifier ? .flagsChanged : .keyDown, keyCode: code, flags: flags)
            let up = InputEvent(kind: source.isModifier ? .flagsChanged : .keyUp, keyCode: code)
            var profile = Profile(name: "Actions", layers: [Layer(name: "Base")])
            profile.layers[0].mappings[source.rawValue] = .action(.macAction(action))
            profile.layers[0].applications["com.apple.Safari"] = ApplicationOverride(
                name: "Safari", mappings: [source.rawValue: .action(.sendKey(KeyBinding(key: "b")))]
            )
            var engine = LayerEngine(profile: profile, actionAvailability: entitlement)
            XCTAssertEqual(engine.handle(down) { _ in }, .suppress)
            XCTAssertEqual(engine.takePendingActions(), [action])
            engine.updateApplication("com.apple.Safari")
            entitlement.setProAccess(false)
            var repeatDown = down
            repeatDown.isRepeat = true
            XCTAssertEqual(engine.handle(repeatDown) { _ in }, .suppress)
            XCTAssertTrue(engine.takePendingActions().isEmpty)
            XCTAssertEqual(engine.handle(up) { _ in }, .suppress)
            engine.updateApplication(nil)
            XCTAssertEqual(engine.handle(down) { _ in }, .suppress)
            XCTAssertTrue(engine.takePendingActions().isEmpty)
            XCTAssertEqual(engine.handle(up) { _ in }, .suppress)
            engine.isEnabled = false
            XCTAssertEqual(
                engine.handle(down) { _ in }, source == .capsLock ? .toggleCapsLock : .passThrough)
            if source == .capsLock { XCTAssertEqual(engine.handle(up) { _ in }, .suppress) }
        }
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

final class TrackpadTests: XCTestCase {
    private var profile: Profile {
        var profile = Presets.navigation
        profile.layers[1].gestures["up"] = .action(
            .sendKey(KeyBinding(key: "s", modifiers: [.command])))
        return profile
    }

    func testGestureUsesLayerAndCancelsTapWhileBalancingShortcut() throws {
        var engine = LayerEngine(profile: profile, actionAvailability: AllActionsAvailability())
        let trigger = try XCTUnwrap(profile.layers[1].trigger?.key.observedKeyCode)
        _ = engine.handle(InputEvent(kind: .keyDown, keyCode: trigger)) { _ in }
        let assignments = engine.beginTrackpadGesture()
        var output: [SyntheticKey] = []
        engine.performGesture(try XCTUnwrap(assignments["up"]), flags: []) { output.append($0) }
        _ = engine.handle(InputEvent(kind: .keyUp, keyCode: trigger, timestamp: 50_000_000)) {
            output.append($0)
        }
        XCTAssertEqual(
            output,
            [
                SyntheticKey(keyCode: KeyCode.s, flags: .command, isKeyDown: true),
                SyntheticKey(keyCode: KeyCode.s, flags: .command, isKeyDown: false),
            ])
        XCTAssertTrue(engine.isQuiescent)
    }

    func testGestureRequiresProAndActiveLayerAndHonorsAppOverride() throws {
        var profile = profile
        profile.layers[1].applications["test.app"] = ApplicationOverride(
            name: "Test", mappings: [:], gestures: ["up": .blocked])
        let trigger = try XCTUnwrap(profile.layers[1].trigger?.key.observedKeyCode)
        var free = LayerEngine(profile: profile, actionAvailability: FreeActionsAvailability())
        _ = free.handle(InputEvent(kind: .keyDown, keyCode: trigger)) { _ in }
        XCTAssertTrue(free.beginTrackpadGesture().isEmpty)
        var engine = LayerEngine(profile: profile, actionAvailability: AllActionsAvailability())
        XCTAssertTrue(engine.beginTrackpadGesture().isEmpty)
        _ = engine.handle(InputEvent(kind: .keyDown, keyCode: trigger)) { _ in }
        engine.updateApplication("test.app")
        XCTAssertEqual(engine.beginTrackpadGesture()["up"]?.mapping, .blocked)
        engine.updateApplication(nil)
        let assignment = try XCTUnwrap(engine.beginTrackpadGesture()["up"])
        _ = engine.handle(InputEvent(kind: .keyUp, keyCode: trigger)) { _ in }
        var output: [SyntheticKey] = []
        engine.performGesture(assignment, flags: []) { output.append($0) }
        XCTAssertTrue(output.isEmpty)

        let entitlement = LicenseEntitlement()
        entitlement.setProAccess(true)
        var licensed = LayerEngine(profile: profile, actionAvailability: entitlement)
        _ = licensed.handle(InputEvent(kind: .keyDown, keyCode: trigger)) { _ in }
        let licensedAssignment = try XCTUnwrap(licensed.beginTrackpadGesture()["up"])
        entitlement.setProAccess(false)
        licensed.performGesture(licensedAssignment, flags: []) { output.append($0) }
        XCTAssertTrue(output.isEmpty)
        XCTAssertTrue(licensed.beginTrackpadGesture().isEmpty)
    }

    func testHeldLayerSurvivesFocusChangesWithoutLeavingKeysPressed() throws {
        var profile = profile
        profile.layers[1].applications["other.app"] = ApplicationOverride(
            name: "Other", mappings: [:], gestures: ["up": .blocked])
        var engine = LayerEngine(profile: profile, actionAvailability: AllActionsAvailability())
        let trigger = try XCTUnwrap(profile.layers[1].trigger?.key.observedKeyCode)
        let h = try XCTUnwrap(KeyCatalog.code(for: "h"))
        _ = engine.handle(InputEvent(kind: .keyDown, keyCode: trigger)) { _ in }
        _ = engine.handle(InputEvent(kind: .keyDown, keyCode: h)) { _ in }
        var output: [SyntheticKey] = []
        engine.reset(preservingHeldTriggers: true) { output.append($0) }
        XCTAssertEqual(output.count, 1)
        XCTAssertFalse(try XCTUnwrap(output.first).isKeyDown)
        XCTAssertTrue(engine.isLayerActive)
        engine.updateApplication("other.app")
        XCTAssertEqual(engine.beginTrackpadGesture()["up"]?.mapping, .blocked)
        engine.reset(preservingHeldTriggers: true) { output.append($0) }
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(
            engine.handle(InputEvent(kind: .keyUp, keyCode: h)) { output.append($0) }, .suppress)
        _ = engine.handle(InputEvent(kind: .keyUp, keyCode: trigger, timestamp: 30_000_000)) {
            output.append($0)
        }
        XCTAssertEqual(output.count, 1)  // No stray tap action in the new app.
        XCTAssertTrue(engine.isQuiescent)
    }

    func testGestureConsumesOneShotAndLeavesToggleActive() throws {
        for tap in [Action.oneShotLayer(.current), .toggleLayer(.current)] {
            var profile = profile
            profile.layers[1].tapAction = tap
            var engine = LayerEngine(profile: profile, actionAvailability: AllActionsAvailability())
            let key = try XCTUnwrap(profile.layers[1].trigger?.key.observedKeyCode)
            _ = engine.handle(InputEvent(kind: .keyDown, keyCode: key)) { _ in }
            _ = engine.handle(InputEvent(kind: .keyUp, keyCode: key, timestamp: 30_000_000)) { _ in
            }
            let assignment = try XCTUnwrap(engine.beginTrackpadGesture()["up"])
            engine.performGesture(assignment, flags: []) { _ in }
            XCTAssertEqual(engine.isLayerActive, tap == .toggleLayer(.current))
        }
    }

    func testSequenceCapturesOnceDrainsMomentumAndDoesNotStealExistingScroll() {
        // AppKit's horizontal scroll axis points left; its vertical axis points up.
        let swipes: [(Double, Double, Bool, TrackpadGesture)] = [
            (40, 0, false, .left), (-40, 0, false, .right),
            (0, 40, false, .up), (0, -40, false, .down),
            (-40, 0, true, .left), (40, 0, true, .right),
            (0, -40, true, .up), (0, 40, true, .down),
        ]
        for (x, y, inverted, direction) in swipes {
            var sequence = TrackpadSequence()
            let result = sequence.handle(
                phase: .began, x: x, y: y, time: 1,
                canCapture: true, isDirectionInvertedFromDevice: inverted)
            XCTAssertEqual(result.gesture, direction)
        }
        var sequence = TrackpadSequence()
        XCTAssertFalse(
            sequence.handle(phase: .began, x: 0, y: 2, time: 10, canCapture: false).suppress)
        XCTAssertFalse(
            sequence.handle(phase: .changed, x: 0, y: 40, time: 10.1, canCapture: true).suppress)
        XCTAssertTrue(
            sequence.handle(phase: .began, x: 0, y: 3, time: 11, canCapture: true).suppress)
        XCTAssertNil(
            sequence.handle(phase: .changed, x: 22, y: 23, time: 11.1, canCapture: true).gesture)
        // Contact reports can change before the native scroll sequence ends.
        // Eligibility is decided at the start; an owned swipe must still finish.
        XCTAssertEqual(
            sequence.handle(phase: .changed, x: 0, y: 25, time: 11.2, canCapture: false).gesture,
            .up
        )
        XCTAssertNil(
            sequence.handle(phase: .changed, x: 0, y: 100, time: 11.3, canCapture: true).gesture)
        XCTAssertTrue(
            sequence.handle(phase: .ended, x: 0, y: 0, time: 11.4, canCapture: false).suppress)
        XCTAssertTrue(
            sequence.handle(phase: .momentum, x: 0, y: 100, time: 11.5, canCapture: false).suppress)
        XCTAssertTrue(
            sequence.handle(phase: .momentumEnded, x: 0, y: 0, time: 11.6, canCapture: false)
                .suppress)
        XCTAssertFalse(
            sequence.handle(phase: .began, x: 0, y: 50, time: 12, canCapture: false).suppress)
    }

    func testSequenceRecoversFromMissingEndAndCancellation() {
        var sequence = TrackpadSequence()
        _ = sequence.handle(phase: .began, x: 0, y: 0, time: 10, canCapture: true)
        XCTAssertFalse(
            sequence.handle(phase: .changed, x: 0, y: 50, time: 13, canCapture: true).suppress)
        _ = sequence.handle(phase: .began, x: 0, y: 40, time: 14, canCapture: true)
        XCTAssertTrue(
            sequence.handle(phase: .cancelled, x: 0, y: 0, time: 14.1, canCapture: true).suppress)
        XCTAssertFalse(
            sequence.handle(phase: .momentum, x: 0, y: 50, time: 14.2, canCapture: true).suppress)
    }

    func testUnmappedSwipeReplaysItsStartAndPassesThroughRemainder() {
        var sequence = TrackpadSequence()
        let start = sequence.handle(
            phase: .began, x: 0, y: 3, time: 1, canCapture: true, mappedGestures: [.left])
        XCTAssertTrue(start.suppress)
        XCTAssertTrue(sequence.isPending)
        let decision = sequence.handle(
            phase: .changed, x: 0, y: 35, time: 1.1, canCapture: true)
        XCTAssertFalse(decision.suppress)
        XCTAssertTrue(decision.replayBuffered)
        XCTAssertNil(decision.gesture)
        // Even if the direction changes, this is now ordinary scrolling.
        let changed = sequence.handle(
            phase: .changed, x: 50, y: 0, time: 1.2, canCapture: true)
        XCTAssertFalse(changed.suppress)
        XCTAssertFalse(changed.replayBuffered)
        XCTAssertNil(changed.gesture)
        for phase in [TrackpadSequence.Phase.ended, .momentum, .momentumEnded] {
            XCTAssertFalse(
                sequence.handle(
                    phase: phase, x: 0, y: 10, time: 1.3, canCapture: true
                ).suppress)
        }
        let mapped = sequence.handle(
            phase: .began, x: 40, y: 0, time: 2, canCapture: true, mappedGestures: [.left])
        XCTAssertTrue(mapped.suppress)
        XCTAssertFalse(mapped.replayBuffered)
        XCTAssertEqual(mapped.gesture, .left)
    }

    func testShortScrollIsReplayedButCancelledMappingCannotReplayIntoNewContext() {
        var sequence = TrackpadSequence()
        _ = sequence.handle(phase: .began, x: 0, y: 3, time: 1, canCapture: true)
        let end = sequence.handle(phase: .ended, x: 0, y: 0, time: 1.1, canCapture: true)
        XCTAssertTrue(end.replayBuffered)
        XCTAssertFalse(end.suppress)
        XCTAssertFalse(
            sequence.handle(
                phase: .momentum, x: 0, y: 5, time: 1.2, canCapture: true
            ).suppress)

        _ = sequence.handle(phase: .began, x: 0, y: 3, time: 2, canCapture: true)
        sequence.cancelRecognition()
        let cancelled = sequence.handle(
            phase: .changed, x: 0, y: 40, time: 2.1, canCapture: false)
        XCTAssertTrue(cancelled.suppress)
        XCTAssertFalse(cancelled.replayBuffered)
        XCTAssertNil(cancelled.gesture)
        let cancelledEnd = sequence.handle(
            phase: .ended, x: 0, y: 0, time: 2.2, canCapture: false)
        XCTAssertTrue(cancelledEnd.suppress)
        XCTAssertFalse(cancelledEnd.replayBuffered)
    }
}
