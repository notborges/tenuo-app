import XCTest

final class ProfileStoreTests: XCTestCase {
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

    func testCorruptProfilesFallBackToTheShippedSet() {
        defaults.set(Data("not json".utf8), forKey: "TenuoProfiles")

        let store = UserDefaultsProfileStore(defaults: defaults)
        XCTAssertEqual(store.profiles.map(\.name), Presets.library.map(\.name))
        XCTAssertEqual(store.manualProfileID, store.profiles[0].id)
    }

    func testSelectingAndEditingAProfilePersists() {
        let store = UserDefaultsProfileStore(defaults: defaults)
        let first = Profile(name: "A", layers: Presets.navigation.layers)
        let second = Profile(name: "B", layers: Presets.vim.layers)
        XCTAssertTrue(store.replaceProfiles([first, second], selecting: second.id))

        var edited = store.manualProfile
        edited.name = "B renamed"
        XCTAssertTrue(store.updateProfile(edited))

        let reopened = UserDefaultsProfileStore(defaults: defaults)
        XCTAssertEqual(reopened.profiles.map(\.name), ["A", "B renamed"])
        XCTAssertEqual(reopened.manualProfileID, second.id)
    }

    func testImportAddsAProfileAndExportRoundTripsIt() throws {
        let store = UserDefaultsProfileStore(defaults: defaults)
        let before = store.profiles.count
        let imported = try store.importProfile(ProfileDocument.encoder.encode(Presets.vim))

        XCTAssertEqual(store.profiles.count, before + 1)
        XCTAssertEqual(store.manualProfileID, imported.id)
        XCTAssertEqual(
            store.manualProfile.layers.map(\.name),
            Presets.vim.layers.map(\.name))
        XCTAssertNotEqual(
            store.manualProfile.layers.map(\.id),
            Presets.vim.layers.map(\.id))

        let exported = try JSONDecoder().decode(
            Profile.self,
            from: store.exportProfile(store.manualProfile))
        XCTAssertEqual(exported, store.manualProfile)
    }

    func testInvalidImportLeavesProfilesUnchanged() {
        let store = UserDefaultsProfileStore(defaults: defaults)
        let before = store.snapshot

        XCTAssertThrowsError(try store.importProfile(Data("{}".utf8)))
        XCTAssertEqual(store.snapshot, before)
    }

    func testImportRejectsUnknownKeys() throws {
        let store = UserDefaultsProfileStore(defaults: defaults)
        var invalid = Presets.navigation
        invalid.layers[1].mappings["notAKey"] = .action(.sendKey(KeyBinding(key: "escape")))

        XCTAssertThrowsError(
            try store.importProfile(ProfileDocument.encoder.encode(invalid))
        ) {
            XCTAssertEqual(
                $0 as? ProfileError,
                .unknownSourceKey(layer: "Navigation", key: "notAKey"))
        }
    }

    func testImportRejectsProfilesWithoutExactlyOneBaseLayer() throws {
        let store = UserDefaultsProfileStore(defaults: defaults)
        var invalid = Presets.navigation
        invalid.layers[1].trigger = nil

        XCTAssertThrowsError(
            try store.importProfile(ProfileDocument.encoder.encode(invalid))
        ) {
            XCTAssertEqual($0 as? ProfileError, .invalidBaseLayerCount(found: 2))
        }
    }

    func testStorePublishesACompleteBeforeAndAfterChange() {
        let store = UserDefaultsProfileStore(defaults: defaults)
        var changes: [ProfileStoreChange] = []
        let token = store.addObserver { changes.append($0) }
        defer { store.removeObserver(token) }

        var edited = store.manualProfile
        edited.name = "Renamed"
        XCTAssertTrue(store.updateProfile(edited))

        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].previous.manualProfile.name, Presets.library[0].name)
        XCTAssertEqual(changes[0].current.manualProfile.name, "Renamed")
        XCTAssertTrue(changes[0].didChangeProfiles)
        XCTAssertFalse(changes[0].didChangeManualSelection)
    }

    func testSnapshotRoundTripsAndProfileDataKeepsItsExistingShape() throws {
        let store = UserDefaultsProfileStore(defaults: defaults)
        let snapshot = store.snapshot

        let data = try ProfileDocument.encoder.encode(snapshot)
        let decoded = try JSONDecoder().decode(ProfileStoreSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)

        let profileData = try ProfileDocument.encoder.encode(Presets.navigation)
        let profileObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: profileData) as? [String: Any])
        let layers = try XCTUnwrap(profileObject["layers"] as? [[String: Any]])
        let layer = try XCTUnwrap(layers[1])
        XCTAssertEqual(layer["holdMode"] as? String, "injectAndLayer")
        XCTAssertNil(layer["outputMode"])
        XCTAssertEqual(
            (layer["tapAction"] as? [String: Any])?["key"] as? String,
            "escape")
        XCTAssertNil(layer["activationMode"])
    }

    func testLegacyTapActionDecodesAsSendKeyAction() throws {
        let profileData = try ProfileDocument.encoder.encode(Presets.navigation)
        let decoded = try JSONDecoder().decode(Profile.self, from: profileData)

        XCTAssertEqual(decoded.layers[1].tapAction, .sendKey(KeyBinding(key: "escape")))
    }
}
