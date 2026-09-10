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

    func testHistoryComparisonShowsDirectionEvenWhenMappingCountsMatch() {
        let current = Presets.navigation
        var saved = current
        saved.layers[1].mappings["h"] = .blocked
        let changes = ProfileHistoryComparison.changes(from: current, to: saved)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.key, "h")
        XCTAssertEqual(changes.first?.before, "←")
        XCTAssertEqual(changes.first?.after, "Block key")
        XCTAssertEqual(
            ProfileHistoryComparison.changes(from: saved, to: current).first?.before, "Block key")
        XCTAssertTrue(ProfileHistoryComparison.changes(from: current, to: current).isEmpty)
    }

    func testHistoryComparisonIncludesProfileAndLayerBehaviorChanges() {
        let current = Presets.stacked
        var saved = current
        saved.name = "Writing"
        saved.tapThresholdMilliseconds = 300
        saved.layers[1].name = "Words"
        saved.layers[1].trigger = LayerTrigger(key: .capsLock, modifiers: [.option])
        saved.layers[1].outputMode = .injectAndLayer
        saved.layers[1].tapAction = .toggleLayer(.layer(saved.layers[2].id))
        saved.layers.swapAt(1, 2)
        let changes = ProfileHistoryComparison.changes(from: current, to: saved)
        XCTAssertEqual(
            Set(changes.map(\.title)),
            Set([
                "Profile name", "Tap window", "Layer name", "Trigger", "Unmapped keys",
                "Tap action", "Layer priority",
            ]))
        XCTAssertEqual(changes.first { $0.title == "Tap action" }?.after, "Toggle layer · Select")
        XCTAssertEqual(Set(changes.map(\.id)).count, changes.count)
    }

    func testHistoryComparisonIncludesRemovedLayersAndTheirMappings() {
        let current = Presets.navigation
        var saved = current
        saved.layers.removeLast()
        let removed = ProfileHistoryComparison.changes(from: current, to: saved)
        XCTAssertEqual(removed.filter { $0.key != nil }.count, 4)
        XCTAssertTrue(removed.contains { $0.title == "Remove layer" })
        XCTAssertFalse(removed.contains { $0.title == "Layer priority" })
        XCTAssertTrue(
            removed.filter { $0.key != nil }.allSatisfy { $0.after == "No direct mapping" })
        let added = ProfileHistoryComparison.changes(from: saved, to: current)
        XCTAssertTrue(added.contains { $0.title == "Add layer" })
        XCTAssertTrue(
            added.filter { $0.key != nil }.allSatisfy { $0.before == "No direct mapping" })
    }

    func testHistoryComparisonDistinguishesPassThroughAndLayerTargets() {
        let current = Presets.stacked
        var saved = current
        saved.layers[1].mappings["h"] = .transparent
        saved.layers[1].mappings["j"] = .action(.oneShotLayer(.layer(saved.layers[2].id)))
        let changes = ProfileHistoryComparison.changes(from: current, to: saved)
        XCTAssertEqual(changes.first { $0.key == "h" }?.after, "Pass through")
        XCTAssertEqual(changes.first { $0.key == "j" }?.after, "One-shot layer · Select")
        XCTAssertEqual(
            changes.map(\.id), ProfileHistoryComparison.changes(from: current, to: saved).map(\.id))
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
        XCTAssertEqual(layer["holdMode"] as? String, "layer")
        XCTAssertNil(layer["outputMode"])
        XCTAssertEqual(
            (layer["tapAction"] as? [String: Any])?["key"] as? String,
            "escape")
        XCTAssertNil(layer["activationMode"])
    }

    func testHistoryPolicyCoalescesDuplicatesRetainsTwentyAcrossReopenAndIgnoresSelection() throws {
        var now = Date(timeIntervalSince1970: 100)
        let history = UserDefaultsProfileHistoryStore(defaults: defaults, now: { now })
        let store = UserDefaultsProfileStore(defaults: defaults, history: history)
        var profile = store.manualProfile

        XCTAssertEqual(try history.entries(for: profile.id).get(), [])
        XCTAssertTrue(history.record(profile, force: false))

        now.addTimeInterval(0.5)
        profile.name = "Coalesced"
        XCTAssertTrue(history.record(profile, force: false))
        XCTAssertEqual(try history.entries(for: profile.id).get().count, 1)

        XCTAssertTrue(history.record(profile, force: true))
        XCTAssertTrue(history.record(profile, force: true))
        XCTAssertEqual(try history.entries(for: profile.id).get().count, 2)

        XCTAssertTrue(store.selectManualProfile(store.profiles[1].id))
        XCTAssertEqual(try history.entries(for: profile.id).get().count, 2)

        for index in 0..<25 {
            now.addTimeInterval(31)
            profile.name = "Version \(index)"
            XCTAssertTrue(history.record(profile, force: false))
        }

        let reopened = UserDefaultsProfileHistoryStore(defaults: defaults, now: { now })
        let entries = try reopened.entries(for: profile.id).get()
        XCTAssertEqual(entries.count, 20)
        XCTAssertEqual(entries.first?.profile.name, "Version 24")
        XCTAssertEqual(entries.last?.profile.name, "Version 5")
    }

    func testUnreadableHistoryAbortsWritesAndPreservesStoredData() throws {
        let history = UserDefaultsProfileHistoryStore(defaults: defaults)
        let store = UserDefaultsProfileStore(defaults: defaults, history: history)
        let before = store.snapshot
        let corrupt = Data("not json".utf8)
        defaults.set(corrupt, forKey: "TenuoProfileHistory")

        guard case .failure(.unreadable) = history.entries(for: before.manualProfileID) else {
            return XCTFail("Expected unreadable history")
        }
        XCTAssertFalse(history.record(before.manualProfile, force: true))
        XCTAssertFalse(history.removeAll(for: before.manualProfileID))
        XCTAssertEqual(defaults.data(forKey: "TenuoProfileHistory"), corrupt)

        var edited = before.manualProfile
        edited.name = "Edited"
        var notifications = 0
        let token = store.addObserver { _ in notifications += 1 }
        defer { store.removeObserver(token) }
        XCTAssertFalse(store.updateProfile(edited))
        XCTAssertFalse(store.restore(ProfileHistoryEntry(profile: edited, savedAt: .now)))
        XCTAssertFalse(
            store.replaceProfiles(
                Array(before.profiles.dropFirst()),
                selecting: before.profiles[1].id))
        XCTAssertEqual(store.snapshot, before)
        XCTAssertEqual(notifications, 0)
        XCTAssertNil(defaults.data(forKey: "TenuoProfiles"))

        defaults.set("wrong type", forKey: "TenuoProfileHistory")
        guard case .failure(.unreadable) = history.entries(for: before.manualProfileID) else {
            return XCTFail("Expected wrong-typed history to be unreadable")
        }
        XCTAssertFalse(history.record(before.manualProfile, force: true))
        XCTAssertFalse(history.removeAll(for: before.manualProfileID))
        XCTAssertEqual(defaults.string(forKey: "TenuoProfileHistory"), "wrong type")

        let failingHistory = StatefulHistoryStore()
        failingHistory.failRecords = true
        let failingStore = UserDefaultsProfileStore(defaults: defaults, history: failingHistory)
        XCTAssertFalse(failingStore.updateProfile(edited))
        XCTAssertEqual(failingStore.snapshot, before)
        XCTAssertNil(defaults.data(forKey: "TenuoProfiles"))
    }

    func testDeletionRemovesOnlyDeletedProfileHistory() throws {
        let history = UserDefaultsProfileHistoryStore(defaults: defaults)
        let store = UserDefaultsProfileStore(defaults: defaults, history: history)
        let first = store.profiles[0]
        let second = store.profiles[1]

        XCTAssertTrue(history.record(first, force: true))
        XCTAssertTrue(history.record(second, force: true))
        XCTAssertTrue(store.replaceProfiles([second], selecting: second.id))

        XCTAssertEqual(try history.entries(for: first.id).get(), [])
        XCTAssertEqual(try history.entries(for: second.id).get().map(\.profile), [second])
        XCTAssertTrue(history.removeAll(for: first.id))
        XCTAssertEqual(UserDefaultsProfileStore(defaults: defaults).snapshot, store.snapshot)
    }

    func testRestoreCapturesCurrentProfileOnceWithForceAndPreservesSelection() throws {
        let history = StatefulHistoryStore()
        let store = UserDefaultsProfileStore(defaults: defaults, history: history)
        let original = store.manualProfile
        var edited = original
        edited.name = "Edited"
        XCTAssertTrue(store.updateProfile(edited))

        let other = store.profiles[1]
        XCTAssertTrue(store.selectManualProfile(other.id))
        let entry = try XCTUnwrap(history.entries(for: original.id).get().first)
        history.records.removeAll()
        history.beforeRecord = { XCTAssertEqual(store.profiles.first, edited) }

        XCTAssertTrue(store.restore(entry))

        XCTAssertEqual(history.records.count, 1)
        XCTAssertEqual(history.records.first?.profile, edited)
        XCTAssertEqual(history.records.first?.force, true)
        XCTAssertEqual(
            try history.entries(for: original.id).get().map(\.profile), [edited, original])
        XCTAssertEqual(store.profiles.first, original)
        XCTAssertEqual(store.manualProfileID, other.id)
    }
}

private final class StatefulHistoryStore: ProfileHistoryStore {
    var records: [(profile: Profile, force: Bool)] = []
    var failRecords = false
    var beforeRecord: (() -> Void)?
    private var saved: [ProfileHistoryEntry] = []

    func entries(for profileID: UUID) -> Result<[ProfileHistoryEntry], ProfileHistoryError> {
        .success(saved.filter { $0.profile.id == profileID })
    }

    func record(_ profile: Profile, force: Bool) -> Bool {
        beforeRecord?()
        records.append((profile, force))
        guard !failRecords, records.count == 1 else { return false }
        saved.insert(ProfileHistoryEntry(profile: profile, savedAt: .now), at: 0)
        return true
    }

    func removeAll(for profileID: UUID) -> Bool {
        saved.removeAll { $0.profile.id == profileID }
        return true
    }
}
