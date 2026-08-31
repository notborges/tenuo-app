import XCTest

final class SettingsTests: XCTestCase {
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

    func testFreshSettingsHaveTheExpectedDefaults() {
        let settings = Settings(defaults: defaults)

        XCTAssertEqual(settings.profiles.map(\.name), Presets.library.map(\.name))
        XCTAssertEqual(settings.activeProfileID, settings.profiles[0].id)
        XCTAssertFalse(settings.checksForUpdates)
        XCTAssertTrue(settings.showsCheatSheet)
    }

    func testPreferencesPersistAcrossInstances() {
        let settings = Settings(defaults: defaults)
        settings.checksForUpdates = true
        settings.showsCheatSheet = false

        let reopened = Settings(defaults: defaults)
        XCTAssertTrue(reopened.checksForUpdates)
        XCTAssertFalse(reopened.showsCheatSheet)
    }

    func testCorruptProfilesFallBackToTheShippedSet() {
        defaults.set(Data("not json".utf8), forKey: "TenuoProfiles")

        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.profiles.map(\.name), Presets.library.map(\.name))
        XCTAssertEqual(settings.activeProfileID, settings.profiles[0].id)
    }

    func testSelectingAndEditingAProfilePersists() {
        let settings = Settings(defaults: defaults)
        let first = Layout(name: "A", layers: Presets.navigation.layers)
        let second = Layout(name: "B", layers: Presets.vim.layers)
        settings.profiles = [first, second]
        settings.activeProfileID = second.id

        var edited = settings.activeProfile
        edited.name = "B renamed"
        settings.activeProfile = edited

        let reopened = Settings(defaults: defaults)
        XCTAssertEqual(reopened.profiles.map(\.name), ["A", "B renamed"])
        XCTAssertEqual(reopened.activeProfileID, second.id)
    }

    func testImportAddsAProfileAndExportRoundTripsIt() throws {
        let settings = Settings(defaults: defaults)
        let before = settings.profiles.count
        let imported = try settings.importJSON(Settings.encoder.encode(Presets.vim))

        XCTAssertEqual(settings.profiles.count, before + 1)
        XCTAssertEqual(settings.activeProfileID, imported.id)
        XCTAssertEqual(settings.activeProfile.layers, Presets.vim.layers)

        let exported = try JSONDecoder().decode(Layout.self, from: settings.exportJSON())
        XCTAssertEqual(exported, settings.activeProfile)
    }

    func testInvalidImportLeavesProfilesUnchanged() {
        let settings = Settings(defaults: defaults)
        let before = settings.profiles

        XCTAssertThrowsError(try settings.importJSON(Data("{}".utf8)))
        XCTAssertEqual(settings.profiles, before)
    }
}
