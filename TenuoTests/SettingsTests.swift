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

    func testUpdateCheckingIsOffUntilAskedFor() {
        let settings = Settings(defaults: defaults)
        XCTAssertFalse(settings.checksForUpdates)
    }

    func testUpdateCheckingPersistsOnceEnabled() {
        Settings(defaults: defaults).checksForUpdates = true
        XCTAssertTrue(Settings(defaults: defaults).checksForUpdates)
    }

    func testLayerHintIsOnByDefault() {
        XCTAssertTrue(Settings(defaults: defaults).showsCheatSheet)
    }
    func testFreshInstallGetsEveryShippedProfile() {
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(
            settings.profiles.map(\.name),
            ["Navigation", "Vim", "Stacked", "Hyper Only"])
        XCTAssertEqual(settings.activeProfile.name, "Navigation")
    }

    func testCorruptLibraryFallsBackToTheShippedSet() {
        defaults.set(Data("not json".utf8), forKey: "TenuoProfiles")
        let settings = Settings(defaults: defaults)
        XCTAssertEqual(settings.profiles.map(\.name), Presets.library.map(\.name))
        XCTAssertEqual(settings.activeProfile.name, "Navigation")
    }

    func testTheLibraryIsNeverEmpty() {
        let settings = Settings(defaults: defaults)
        settings.profiles = []
        XCTAssertEqual(settings.profiles.count, Presets.library.count)
    }

    func testADanglingActiveIDFallsBackToTheFirstProfile() {
        let settings = Settings(defaults: defaults)
        let first = Layout(name: "A", layers: Presets.navigation.layers)
        settings.profiles = [first, Layout(name: "B", layers: Presets.vim.layers)]
        defaults.set(UUID().uuidString, forKey: "TenuoActiveProfile")
        XCTAssertEqual(settings.activeProfileID, first.id)
    }

    func testEditingTheActiveProfileWritesBackToItsSlot() {
        let settings = Settings(defaults: defaults)
        let a = Layout(name: "A", layers: Presets.navigation.layers)
        let b = Layout(name: "B", layers: Presets.vim.layers)
        settings.profiles = [a, b]
        settings.activeProfileID = b.id

        var edited = settings.activeProfile
        edited.name = "B renamed"
        settings.activeProfile = edited

        XCTAssertEqual(settings.profiles.map(\.name), ["A", "B renamed"])
        XCTAssertEqual(settings.activeProfileID, b.id)
    }

    func testImportAddsAProfileRatherThanReplacing() throws {
        let settings = Settings(defaults: defaults)
        let before = settings.profiles.count

        let imported = try settings.importJSON(Settings.encoder.encode(Presets.vim))

        XCTAssertEqual(settings.profiles.count, before + 1)
        XCTAssertEqual(settings.activeProfileID, imported.id)
        XCTAssertEqual(settings.activeProfile.layers, Presets.vim.layers)
    }

    func testImportingTwiceGivesTwoDistinctProfiles() throws {
        let settings = Settings(defaults: defaults)
        let data = try Settings.encoder.encode(Presets.vim)

        let first = try settings.importJSON(data)
        let second = try settings.importJSON(data)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.name, second.name)
    }

    func testImportSurfacesABadFileRatherThanSwallowingIt() {
        let settings = Settings(defaults: defaults)
        let before = settings.profiles.count
        XCTAssertThrowsError(try settings.importJSON(Data("{}".utf8)))
        XCTAssertEqual(settings.profiles.count, before)
    }

    func testExportRoundTripsTheActiveProfile() throws {
        let settings = Settings(defaults: defaults)
        let decoded = try JSONDecoder().decode(Layout.self, from: settings.exportJSON())
        XCTAssertEqual(decoded, settings.activeProfile)
    }

}
