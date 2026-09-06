import XCTest

final class ProfileSelectionTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TenuoTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testManualSourceFollowsTheStoreWithoutChangingItsRole() {
        let store = UserDefaultsProfileStore(defaults: defaults)
        let source = ManualProfileSelectionSource(store: store)
        var changes: [EffectiveProfile] = []
        source.onChange = { changes.append($0) }
        source.start()

        let selected = store.profiles[1]
        XCTAssertTrue(store.selectManualProfile(selected.id))

        XCTAssertEqual(source.current.profile, selected)
        XCTAssertEqual(source.current.profileID, selected.id)
        XCTAssertEqual(source.current.reason, .manual)
        XCTAssertEqual(changes.map(\.profileID), [selected.id])
        XCTAssertEqual(store.manualProfileID, selected.id)

        source.stop()
    }
}

final class ApplicationOverrideTests: XCTestCase {
    func testOverridesInheritDefaultsAndRoundTrip() throws {
        var profile = Presets.default
        let index = try XCTUnwrap(profile.layers.firstIndex { !$0.isBase })
        let original = profile.layers[index].mappings
        profile.layers[index].applications["com.apple.Safari"] = ApplicationOverride(
            name: "Safari",
            mappings: ["t": .action(.sendKey(KeyBinding(key: "t", modifiers: [.command])))])
        let safari = profile.layers[index].mappings(for: "com.apple.Safari")
        XCTAssertEqual(safari["h"], original["h"])
        XCTAssertEqual(safari["t"]?.binding?.modifiers, [.command])
        XCTAssertEqual(profile.layers[index].mappings(for: "com.apple.finder"), original)
        XCTAssertEqual(profile.layers[index].mappings(for: nil), original)
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
        try decoded.validate()
        let changes = ProfileHistoryComparison.changes(from: Presets.default, to: profile)
        XCTAssertTrue(changes.contains { $0.applicationID == "com.apple.Safari" && $0.key == "t" })
    }

    func testSwitchingAppsKeepsHeldKeyReleasePaired() {
        var base = Layer(
            name: "Base", mappings: ["h": .action(.sendKey(KeyBinding(key: "leftArrow")))])
        base.applications["safari"] = ApplicationOverride(
            name: "Safari", mappings: ["h": .action(.sendKey(KeyBinding(key: "rightArrow")))])
        var engine = LayerEngine(profile: Profile(name: "Apps", layers: [base]))
        let down = engine.handle(InputEvent(kind: .keyDown, keyCode: KeyCode.h), emit: { _ in })
        if case let .rewrite(keyCode, _) = down {
            XCTAssertEqual(keyCode, KeyCode.leftArrow)
        } else {
            XCTFail("The default mapping must apply")
        }
        engine.updateApplication("safari")
        let release = engine.handle(InputEvent(kind: .keyUp, keyCode: KeyCode.h), emit: { _ in })
        if case let .rewrite(keyCode, _) = release {
            XCTAssertEqual(keyCode, KeyCode.leftArrow)
        } else {
            XCTFail("The original output must be released")
        }
        let next = engine.handle(InputEvent(kind: .keyDown, keyCode: KeyCode.h), emit: { _ in })
        if case let .rewrite(keyCode, _) = next {
            XCTAssertEqual(keyCode, KeyCode.rightArrow)
        } else {
            XCTFail("New presses must use the new app")
        }
    }

    func testCopiesRemapTargetsInsideAppOverridesAndRejectInvalidMappings() throws {
        var profile = Presets.default
        let target = try XCTUnwrap(profile.triggeredLayers.first?.id)
        profile.layers[0].applications["safari"] = ApplicationOverride(
            name: "Safari", mappings: ["t": .action(.toggleLayer(.layer(target)))])
        let copy = profile.copy(named: "Copy")
        XCTAssertEqual(
            copy.layers[0].applications["safari"]?.mappings["t"]?.action?.target,
            .layer(try XCTUnwrap(copy.triggeredLayers.first?.id)))
        profile.layers[0].applications["safari"]?.mappings["not-a-key"] = .blocked
        XCTAssertThrowsError(try profile.validate())
    }
}
