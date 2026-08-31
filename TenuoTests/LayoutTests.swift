import XCTest

final class KeyCatalogTests: XCTestCase {
    func testNamesAndCodesRoundTrip() {
        for key in KeyCatalog.all {
            XCTAssertEqual(KeyCatalog.code(for: key.name), key.code, key.name)
            XCTAssertEqual(KeyCatalog.name(for: key.code), key.name, key.name)
        }
    }

    func testNamesAreUnique() {
        let names = KeyCatalog.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "duplicate key name in the catalog")
    }

    func testLookupIsCaseInsensitive() {
        XCTAssertEqual(KeyCatalog.code(for: "LeftArrow"), KeyCatalog.code(for: "leftarrow"))
    }

    func testUnknownCodeStillProducesALabel() {
        XCTAssertFalse(KeyCatalog.label(for: 250).isEmpty)
    }
}

final class ModifierRequirementTests: XCTestCase {
    func testSidelessModifierAcceptsEitherSide() {
        XCTAssertTrue(ModifierRequirement.shift.isSatisfied(by: [.shift, .deviceLeftShift]))
        XCTAssertTrue(ModifierRequirement.shift.isSatisfied(by: [.shift, .deviceRightShift]))
    }

    func testLeftShiftRejectsRightShift() {
        XCTAssertTrue(ModifierRequirement.leftShift.isSatisfied(by: [.shift, .deviceLeftShift]))
        XCTAssertFalse(ModifierRequirement.leftShift.isSatisfied(by: [.shift, .deviceRightShift]))
    }

    func testModifierNotHeldIsNeverSatisfied() {
        XCTAssertFalse(ModifierRequirement.shift.isSatisfied(by: []))
        XCTAssertFalse(ModifierRequirement.leftShift.isSatisfied(by: [.deviceLeftShift]))
    }

    func testTriggerRequiresEveryModifier() {
        let trigger = LayerTrigger(key: .capsLock, modifiers: [.leftShift, .option])
        XCTAssertFalse(trigger.matches(flags: [.shift, .deviceLeftShift]))
        XCTAssertTrue(trigger.matches(flags: [.shift, .deviceLeftShift, .option]))
    }

    func testSpecificityCountsModifiers() {
        XCTAssertEqual(LayerTrigger(key: .capsLock).specificity, 0)
        XCTAssertEqual(LayerTrigger(key: .capsLock, modifiers: [.leftShift]).specificity, 1)
    }
}

final class LayoutTests: XCTestCase {
    func testActionDecodesFromBareBinding() throws {
        let action = try JSONDecoder().decode(
            KeyAction.self,
            from: Data(#"{"key":"leftArrow"}"#.utf8))
        XCTAssertEqual(action, .key(KeyBinding(key: "leftArrow")))
    }

    func testTransparentRoundTrips() throws {
        let data = try Settings.encoder.encode(KeyAction.transparent)
        XCTAssertEqual(try JSONDecoder().decode(KeyAction.self, from: data), .transparent)
    }

    func testLayoutRoundTripsThroughJSON() throws {
        for preset in Presets.all {
            let data = try Settings.encoder.encode(preset)
            XCTAssertEqual(try JSONDecoder().decode(Layout.self, from: data), preset, preset.name)
        }
    }

    func testEveryPresetUsesKnownKeys() {
        for preset in Presets.all {
            for layer in preset.layers {
                for (source, action) in layer.mappings {
                    XCTAssertNotNil(
                        KeyCatalog.code(for: source),
                        "\(preset.name)/\(layer.name): unknown source '\(source)'")
                    if let binding = action.binding {
                        XCTAssertNotNil(
                            binding.keyCode,
                            "\(preset.name)/\(layer.name): unknown destination")
                    }
                }
            }
        }
    }

    func testEveryPresetHasExactlyOneBaseLayer() {
        for preset in Presets.all {
            XCTAssertEqual(preset.layers.filter(\.isBase).count, 1, preset.name)
        }
    }

    func testConflictDetectionFindsDuplicateChords() {
        let trigger = LayerTrigger(key: .capsLock, modifiers: [.leftShift])
        let layout = Layout(
            name: "t",
            layers: [
                Layer(name: "Base"),
                Layer(name: "A", trigger: trigger),
                Layer(name: "B", trigger: trigger),
            ])
        XCTAssertEqual(layout.conflicts().count, 1)
    }

    func testDistinctChordsDoNotConflict() {
        let layout = Layout(
            name: "t",
            layers: [
                Layer(name: "Base"),
                Layer(name: "A", trigger: LayerTrigger(key: .capsLock)),
                Layer(name: "B", trigger: LayerTrigger(key: .capsLock, modifiers: [.leftShift])),
            ])
        XCTAssertTrue(layout.conflicts().isEmpty)
    }
}

final class KeyboardGeometryTests: XCTestCase {
    private func units(_ row: [KeyboardLayout.Element]) -> CGFloat {
        row.reduce(0) { $0 + $1.width }
    }

    private func keyCount(_ element: KeyboardLayout.Element) -> Int {
        if case .arrows = element { return 4 }
        return 1
    }

    func testEveryRowIsTheSameWidth() {
        for (index, row) in KeyboardLayout.rows.enumerated() {
            XCTAssertEqual(
                units(row), 14.5, accuracy: 0.0001,
                "row \(index) is \(units(row))u, so it will not reach both edges")
        }
    }

    func testBoardHasSeventyEightKeys() {
        let count = KeyboardLayout.rows.reduce(0) { total, row in
            total + row.reduce(0) { $0 + keyCount($1) }
        }
        XCTAssertEqual(count, 78)
    }

    func testAppleSymmetries() {
        XCTAssertEqual(KeyboardLayout.rows[1].last?.width, 1.5, "delete")
        XCTAssertEqual(KeyboardLayout.rows[2].first?.width, 1.5, "tab")
        XCTAssertEqual(
            KeyboardLayout.rows[3].first?.width,
            KeyboardLayout.rows[3].last?.width, "caps lock vs return")
        XCTAssertEqual(
            KeyboardLayout.rows[4].first?.width,
            KeyboardLayout.rows[4].last?.width, "left vs right shift")
    }

    func testEveryMappableKeyExistsInTheCatalog() {
        for row in KeyboardLayout.rows {
            for case .key(let key) in row {
                guard let name = key.name else { continue }
                XCTAssertNotNil(
                    KeyCatalog.key(named: name),
                    "\(name) is drawn but is not in the catalog")
            }
        }
    }

    func testEveryShiftedKeyPrintsItsSecondLegend() {
        let expected = [
            "grave": "~", "1": "!", "2": "@", "3": "#", "4": "$", "5": "%",
            "6": "^", "7": "&", "8": "*", "9": "(", "0": ")", "minus": "_",
            "equal": "+", "leftBracket": "{", "rightBracket": "}",
            "backslash": "|", "semicolon": ":", "quote": "\"",
            "comma": "<", "period": ">", "slash": "?",
        ]

        var found: [String: String] = [:]
        for row in KeyboardLayout.rows {
            for case .key(let key) in row {
                guard let name = key.name, let shifted = key.shifted else { continue }
                found[name] = shifted
            }
        }

        XCTAssertEqual(found, expected)
        XCTAssertEqual(KeyboardLayout.shiftedKeyCount, expected.count)
    }

    func testFunctionRowPrintsNumberAndGlyph() {
        let functionRow = KeyboardLayout.rows[0]
        var seen = 0
        for case .key(let key) in functionRow {
            guard let name = key.name, name.hasPrefix("f"), name != "escape" else { continue }
            seen += 1
            XCTAssertEqual(key.label.lowercased(), name, "\(name) should print its own number")
            XCTAssertNotNil(key.glyph, "\(name) should also carry its media glyph")
            XCTAssertNil(key.symbol, "\(name)'s glyph belongs above the number, not in place of it")
        }
        XCTAssertEqual(seen, 12)
        guard case .key(let corner) = functionRow.last else {
            return XCTFail("no corner key")
        }
        XCTAssertEqual(corner.symbol, "touchid")
    }

    func testOnlyCapsLockHasAnIndicator() {
        let indicators = KeyboardLayout.rows.flatMap { row in
            row.compactMap { element -> TriggerKey?? in
                guard case .key(let key) = element, key.hasIndicator else { return nil }
                return key.trigger
            }
        }
        XCTAssertEqual(indicators.count, 1)
        XCTAssertEqual(indicators.first, .capsLock)
    }

    func testEveryTriggerKeyIsDrawn() {
        let drawn = Set(
            KeyboardLayout.rows.flatMap { row in
                row.compactMap { element -> TriggerKey? in
                    guard case .key(let key) = element else { return nil }
                    return key.trigger
                }
            })
        let named = TriggerKey.suggested + TriggerKey.rightModifiers + TriggerKey.leftModifiers
        for trigger in named where trigger != .rightControl {
            XCTAssertTrue(drawn.contains(trigger), "\(trigger) is not on the board")
        }
    }
}

final class TriggerKeyTests: XCTestCase {
    private func roundTrip(_ key: TriggerKey) throws -> TriggerKey {
        try JSONDecoder().decode(
            TriggerKey.self,
            from: Settings.encoder.encode(key))
    }

    func testNamedTriggersRoundTrip() throws {
        let named = TriggerKey.suggested + TriggerKey.rightModifiers + TriggerKey.leftModifiers
        for key in named {
            XCTAssertEqual(try roundTrip(key), key, "\(key)")
        }
    }

    func testOrdinaryKeyTriggersRoundTrip() throws {
        XCTAssertEqual(try roundTrip(.key("f13")), .key("f13"))
        XCTAssertEqual(try roundTrip(.key("grave")), .key("grave"))
    }

    func testNamedTriggerSpellingsDecode() throws {
        for name in [
            "capsLock", "rightCommand", "rightOption",
            "rightControl", "rightShift", "function",
        ] {
            let decoded = try JSONDecoder().decode(
                TriggerKey.self, from: Data("\"\(name)\"".utf8))
            if case .key = decoded {
                XCTFail("\(name) decoded as an ordinary key, not the named case")
            }
        }
    }

    func testNoCatalogNameCollidesWithAReservedName() {
        for key in KeyCatalog.all {
            guard case .key = TriggerKey(rawValue: key.name) else {
                return XCTFail("catalog key '\(key.name)' collides with a named trigger")
            }
        }
    }

    func testOnlyOrdinaryKeysAreConsumedWhileHeld() {
        XCTAssertTrue(TriggerKey.capsLock.isConsumedWhileHeld)
        XCTAssertTrue(TriggerKey.key("f13").isConsumedWhileHeld)
        XCTAssertFalse(TriggerKey.rightCommand.isConsumedWhileHeld)
        XCTAssertFalse(TriggerKey.function.isConsumedWhileHeld)
    }

    func testUnknownKeyNameHasNoKeyCodeRatherThanZero() {
        XCTAssertNil(TriggerKey.key("nonsense").observedKeyCode)
        XCTAssertEqual(TriggerKey.key("f13").observedKeyCode, KeyCatalog.code(for: "f13"))
    }
}

final class LayerLimitTests: XCTestCase {

    private func layout(heldLayers count: Int) -> Layout {
        var layers = [Layer(name: "Base", holdMode: .layer)]
        for index in 0..<count {
            layers.append(
                Layer(
                    name: "Layer \(index)",
                    trigger: LayerTrigger(key: .key("f\(index + 13)"))
                ))
        }
        return Layout(name: "Test", layers: layers)
    }

    func testBaseLayerDoesNotCountTowardTheLimit() {
        let full = layout(heldLayers: Layout.maxTriggeredLayers)
        XCTAssertEqual(full.layers.count, Layout.maxTriggeredLayers + 1)
        XCTAssertFalse(full.canAddLayer)
    }

    func testRoomBelowTheLimit() {
        XCTAssertTrue(layout(heldLayers: Layout.maxTriggeredLayers - 1).canAddLayer)
    }

    func testAProfileWithNoHeldLayersHasRoom() {
        XCTAssertTrue(layout(heldLayers: 0).canAddLayer)
    }

    func testEveryShippedProfileIsWithinTheLimit() {
        for profile in Presets.library {
            XCTAssertLessThanOrEqual(
                profile.triggeredLayers.count, Layout.maxTriggeredLayers,
                "preset '\(profile.name)' exceeds the limit"
            )
        }
    }

    func testImportRejectsAProfileOverTheLimit() throws {
        let oversized = layout(heldLayers: Layout.maxTriggeredLayers + 1)
        let data = try JSONEncoder().encode(oversized)
        let settings = Settings(defaults: UserDefaults(suiteName: "limit-\(UUID())")!)

        XCTAssertThrowsError(try settings.importJSON(data)) { error in
            XCTAssertEqual(
                error as? ProfileError,
                .tooManyLayers(found: Layout.maxTriggeredLayers + 1))
        }
    }

    func testImportAcceptsAProfileAtExactlyTheLimit() throws {
        let exact = layout(heldLayers: Layout.maxTriggeredLayers)
        let data = try JSONEncoder().encode(exact)
        let settings = Settings(defaults: UserDefaults(suiteName: "limit-\(UUID())")!)

        XCTAssertNoThrow(try settings.importJSON(data))
    }
}
