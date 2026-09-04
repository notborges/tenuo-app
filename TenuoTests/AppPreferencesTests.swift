import XCTest

final class AppPreferencesTests: XCTestCase {
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

    func testFreshPreferencesHaveTheExpectedDefaults() {
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertTrue(preferences.isEnabled)
        XCTAssertTrue(preferences.showsCheatSheet)
        XCTAssertFalse(preferences.checksForUpdates)
    }

    func testPreferencesPersistAcrossInstances() {
        let preferences = AppPreferences(defaults: defaults)
        preferences.isEnabled = false
        preferences.checksForUpdates = true
        preferences.showsCheatSheet = false

        let reopened = AppPreferences(defaults: defaults)
        XCTAssertFalse(reopened.isEnabled)
        XCTAssertTrue(reopened.checksForUpdates)
        XCTAssertFalse(reopened.showsCheatSheet)
    }
}
