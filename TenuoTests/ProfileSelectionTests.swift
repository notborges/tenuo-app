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
