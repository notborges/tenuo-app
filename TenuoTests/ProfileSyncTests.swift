import Foundation
import XCTest

final class ProfileSyncTests: XCTestCase {
    private func temporaryStore() throws -> (URL, UserDefaults) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        let name = "app.tenuo.sync-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        return (directory.appendingPathComponent("profiles.sqlite"), defaults)
    }

    func testQuarantinedKeysRecoverAfterUpgradeWithoutDiscardingOfflineEdits() throws {
        let profile = Presets.navigation
        var state = ProfileSyncState(
            snapshot: ProfileStoreSnapshot(
                profiles: [profile], manualProfileID: profile.id))
        var remote = profile
        remote.layers[1].mappings["isoSection"] = .blocked
        let document = SyncedProfile(id: profile.id, revision: UUID(), profile: remote, position: 0)
        state.quarantined[profile.id] = try JSONEncoder().encode(document)
        let unrelatedID = UUID()
        state.quarantined[unrelatedID] = Data("unreadable".utf8)
        var offline = profile
        offline.name = "Offline edit"
        state.pending[profile.id] = SyncedProfile(
            id: profile.id, revision: UUID(),
            profile: offline, position: 0)
        state.retryQuarantinedProfiles()
        try state.reconcile(protectedProfileID: nil)
        XCTAssertNil(state.quarantined[profile.id])
        XCTAssertNotNil(state.quarantined[unrelatedID])
        XCTAssertEqual(state.conflicts[profile.id]?.remote, document)
        XCTAssertEqual(state.pending[profile.id]?.profile, offline)
        XCTAssertEqual(state.snapshot.profiles, [profile])
    }

    func testHistoryCheckpointsFollowEditingSessionsAndSurviveReopen() throws {
        let (url, defaults) = try temporaryStore()
        var clock = Date(timeIntervalSince1970: 1000)
        let store = try SQLiteProfileStore(url: url, defaults: defaults, now: { clock })
        let original = store.manualProfile
        var edited = original
        for index in 0..<12 {
            clock.addTimeInterval(5)
            edited.name = "Edit \(index)"
            XCTAssertTrue(store.updateProfile(edited))
        }
        XCTAssertEqual(try store.history.entries(for: original.id).get().map(\.profile), [original])
        clock.addTimeInterval(31)
        let beforePause = edited
        edited.name = "After pause"
        XCTAssertTrue(store.updateProfile(edited))
        XCTAssertEqual(
            try store.history.entries(for: original.id).get().map(\.profile),
            [beforePause, original])
        let entry = try XCTUnwrap(try store.history.entries(for: original.id).get().last)
        XCTAssertTrue(store.restore(entry))
        XCTAssertEqual(try store.history.entries(for: original.id).get().first?.profile, edited)
        let reopened = try SQLiteProfileStore(url: url, defaults: defaults, now: { clock })
        var next = reopened.manualProfile
        next.name = "After restart"
        XCTAssertTrue(reopened.updateProfile(next))
        XCTAssertEqual(
            try reopened.history.entries(for: original.id).get().first?.profile, original)
        let observer = reopened.addObserver { _ in reopened.history.endSession() }
        next.name = "End session during notification"
        XCTAssertTrue(reopened.updateProfile(next))
        let checkpoint = next
        next.name = "Next session"
        XCTAssertTrue(reopened.updateProfile(next))
        XCTAssertEqual(
            try reopened.history.entries(for: original.id).get().first?.profile, checkpoint)
        reopened.removeObserver(observer)
    }

    func testHistoryLongSessionAndExplicitBoundary() {
        var policy = HistoryCheckpointPolicy()
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(policy.edit(id, at: start))
        for seconds in stride(from: 10, to: 300, by: 10) {
            XCTAssertFalse(policy.edit(id, at: start.addingTimeInterval(Double(seconds))))
        }
        XCTAssertTrue(policy.edit(id, at: start.addingTimeInterval(300)))
        XCTAssertTrue(policy.edit(id, at: start.addingTimeInterval(301), force: true))
        XCTAssertTrue(policy.edit(id, at: start.addingTimeInterval(302)))
    }

    @MainActor
    func testFreeUndoRedoPreservesSelectionAndInvalidatesAfterExternalEdit() throws {
        let (url, defaults) = try temporaryStore()
        let store = try SQLiteProfileStore(url: url, defaults: defaults)
        let edits = ProfileEditSession(store: store)
        edits.undoManager.groupsByEvent = false
        let original = store.manualProfile
        var changed = original
        changed.name = "Edited"
        edits.undoManager.beginUndoGrouping()
        XCTAssertTrue(edits.perform { store.updateProfile(changed) })
        edits.undoManager.endUndoGrouping()
        let otherID = try XCTUnwrap(store.profiles.first { $0.id != original.id }?.id)
        XCTAssertTrue(store.selectManualProfile(otherID))
        edits.undoManager.undo()
        XCTAssertEqual(store.profiles.first { $0.id == original.id }, original)
        XCTAssertEqual(store.manualProfileID, otherID)
        edits.undoManager.redo()
        XCTAssertEqual(store.profiles.first { $0.id == original.id }, changed)
        var external = changed
        external.name = "From another Mac"
        XCTAssertTrue(store.updateProfile(external))
        XCTAssertFalse(edits.undoManager.canUndo)
        XCTAssertFalse(edits.undoManager.canRedo)
        XCTAssertFalse(edits.perform { false })
        XCTAssertFalse(edits.undoManager.canUndo)
    }

    func testMigrationAndRestartKeepLocalTargetsOutOfPendingDocuments() throws {
        let (url, defaults) = try temporaryStore()
        var original = Presets.navigation
        original.layers[1].mappings["a"] = .action(
            .macAction(.file(FileActionTarget(bookmark: Data([1, 2, 3]), name: "Project"))))
        let legacy = try ProfileDocument.encoder.encode([original])
        defaults.set(legacy, forKey: "TenuoProfiles")
        let store = try SQLiteProfileStore(url: url, defaults: defaults)
        XCTAssertEqual(
            store.profiles[0].layers[1].mappings["a"]?.action?.macAction?.displayLabel,
            "Open Project")
        var edited = store.profiles[0]
        edited.name = "Work"
        XCTAssertTrue(store.updateProfile(edited))
        let reopened = try SQLiteProfileStore(url: url, defaults: defaults)
        XCTAssertEqual(reopened.snapshot, store.snapshot)
        XCTAssertEqual(reopened.state.pending, store.state.pending)
        XCTAssertEqual(defaults.data(forKey: "TenuoProfiles"), legacy)
        let document = try XCTUnwrap(reopened.state.pending[edited.id])
        if case let .file(target) = document.profile?.layers[1].mappings["a"]?.action?.macAction {
            XCTAssertTrue(target.bookmark.isEmpty)
            XCTAssertNotNil(target.localID)
        } else {
            XCTFail("File target missing")
        }
        if case let .file(target) = reopened.profiles[0].layers[1].mappings["a"]?.action?.macAction
        {
            XCTAssertEqual(target.bookmark, Data([1, 2, 3]))
        } else {
            XCTFail("Local bookmark missing")
        }
    }

    func testInvalidMigrationAndFailedTransactionDoNotReplaceStoredData() throws {
        let (url, defaults) = try temporaryStore()
        defaults.set(Data("broken".utf8), forKey: "TenuoProfiles")
        XCTAssertThrowsError(try SQLiteProfileStore(url: url, defaults: defaults))
        defaults.removeObject(forKey: "TenuoProfiles")
        let store = try SQLiteProfileStore(url: url, defaults: defaults)
        let original = store.state
        XCTAssertThrowsError(try store.transaction { $0.schema = 99 })
        XCTAssertEqual(store.state, original)
        XCTAssertEqual(try SQLiteProfileStore(url: url, defaults: defaults).state, original)
    }

    func testConcurrentEditsAndDeleteEditConflictsPreserveLocalVersionWithoutDuplicateCopies()
        throws
    {
        var state = ProfileSyncState(
            snapshot: ProfileStoreSnapshot(
                profiles: [Presets.navigation], manualProfileID: Presets.navigation.id))
        state.seedPending()
        let first = try XCTUnwrap(state.pending[Presets.navigation.id])
        state.acknowledge(first)
        let old = state.snapshot
        var local = old.manualProfile
        local.name = "Local edit"
        state.snapshot = ProfileStoreSnapshot(profiles: [local], manualProfileID: local.id)
        state.recordLocalChanges(from: old)
        var remote = first
        remote.revision = UUID()
        remote.profile?.name = "Remote edit"
        for _ in 0..<3 {
            try state.receive(remote)
            try state.reconcile(protectedProfileID: nil)
        }
        XCTAssertEqual(state.snapshot.manualProfile.name, "Local edit")
        XCTAssertEqual(state.conflicts.count, 1)
        XCTAssertEqual(state.conflicts[local.id]?.remote.profile?.name, "Remote edit")
        remote.profile = nil
        remote.revision = UUID()
        try state.receive(remote)
        try state.reconcile(protectedProfileID: nil)
        XCTAssertEqual(state.snapshot.manualProfile.name, "Local edit")
        XCTAssertNil(state.conflicts[local.id]?.remote.profile)
        XCTAssertNotNil(state.pending[local.id])
    }

    func testAcknowledgementDoesNotDiscardAnEditMadeDuringUpload() throws {
        var state = ProfileSyncState(
            snapshot: ProfileStoreSnapshot(
                profiles: [Presets.navigation], manualProfileID: Presets.navigation.id))
        state.seedPending()
        let uploading = try XCTUnwrap(state.pending[Presets.navigation.id])
        let old = state.snapshot
        var edited = old.manualProfile
        edited.name = "Edited during upload"
        state.snapshot = ProfileStoreSnapshot(profiles: [edited], manualProfileID: edited.id)
        state.recordLocalChanges(from: old)
        state.acknowledge(uploading)
        XCTAssertEqual(state.pending[edited.id]?.profile?.name, edited.name)
        XCTAssertEqual(state.acknowledged[edited.id]?.revision, uploading.revision)
    }

    func testRemoteChangesWaitForSafeBoundaryAndSelectedDeletionNeedsReview() throws {
        var state = ProfileSyncState(
            snapshot: ProfileStoreSnapshot(
                profiles: [Presets.navigation], manualProfileID: Presets.navigation.id))
        var remote = SyncedProfile(
            id: Presets.navigation.id, revision: UUID(), profile: Presets.navigation, position: 0)
        remote.profile?.name = "From another Mac"
        try state.receive(remote)
        try state.reconcile(protectedProfileID: Presets.navigation.id)
        XCTAssertEqual(state.snapshot.manualProfile.name, "Navigation")
        XCTAssertEqual(state.incoming.count, 1)
        try state.reconcile(protectedProfileID: nil)
        XCTAssertEqual(state.snapshot.manualProfile.name, "From another Mac")
        XCTAssertEqual(state.history.first?.profile.name, "Navigation")
        remote.profile = nil
        remote.revision = UUID()
        try state.receive(remote)
        try state.reconcile(protectedProfileID: nil)
        XCTAssertEqual(state.snapshot.profiles.count, 1)
        XCTAssertEqual(state.conflicts.count, 1)
    }

    func testRemoteBookmarksAndDuplicateProfileIDsAreRejected() throws {
        var profile = Presets.navigation
        profile.layers[1].mappings["a"] = .action(
            .macAction(.file(FileActionTarget(bookmark: Data([9]), name: "Private file"))))
        XCTAssertThrowsError(
            try SyncedProfile(id: profile.id, revision: UUID(), profile: profile, position: 0)
                .validate())
        let snapshot = ProfileStoreSnapshot(
            profiles: [profile, profile], manualProfileID: profile.id)
        XCTAssertThrowsError(try snapshot.validate())
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                ProfileStoreSnapshot.self, from: ProfileDocument.encoder.encode(snapshot)))
    }
    func testLocalReplacementCopyExportAndHistoryKeepTargetAssociationsIsolated() throws {
        let (url, defaults) = try temporaryStore()
        let store = try SQLiteProfileStore(url: url, defaults: defaults)
        var profile = store.manualProfile
        profile.layers[1].mappings["a"] = .action(
            .macAction(.file(FileActionTarget(bookmark: Data([1]), name: "Original"))))
        XCTAssertTrue(store.updateProfile(profile))
        let saved = store.manualProfile
        try store.transaction { state in
            state.seedPending()
            for document in Array(state.pending.values) { state.acknowledge(document) }
        }
        var replaced = saved
        guard case var .file(target) = saved.layers[1].mappings["a"]?.action?.macAction else {
            return XCTFail("Missing file")
        }
        target.bookmark = Data([2])
        target.name = "Local replacement"
        replaced.layers[1].mappings["a"] = .action(.macAction(.file(target)))
        XCTAssertTrue(store.updateProfile(replaced))
        XCTAssertTrue(store.state.pending.isEmpty)
        XCTAssertEqual(store.manualProfile, replaced)
        let copied = try store.importProfile(store.exportProfile(store.manualProfile))
        XCTAssertNotEqual(copied.id, saved.id)
        var changedCopy = copied
        target.bookmark = Data([3])
        changedCopy.layers[1].mappings["a"] = .action(.macAction(.file(target)))
        XCTAssertTrue(store.updateProfile(changedCopy))
        let original = try XCTUnwrap(store.profiles.first { $0.id == saved.id })
        if case let .file(file) = original.layers[1].mappings["a"]?.action?.macAction {
            XCTAssertEqual(file.bookmark, Data([2]))
        } else {
            XCTFail("Original target lost")
        }
        let portable = try XCTUnwrap(store.state.snapshot.profiles.first { $0.id == saved.id })
        var otherMac = ProfileSyncState(
            snapshot: ProfileStoreSnapshot(profiles: [portable], manualProfileID: portable.id))
        otherMac.seedPending()
        if case let .file(file) = otherMac.resolved(portable).layers[1].mappings["a"]?.action?
            .macAction
        {
            XCTAssertTrue(file.bookmark.isEmpty)
        } else {
            XCTFail("Portable target lost")
        }
        var historical = original
        historical.name = "Restored"
        XCTAssertTrue(store.restore(ProfileHistoryEntry(profile: historical, savedAt: Date())))
        let restarted = try SQLiteProfileStore(url: url, defaults: defaults)
        XCTAssertEqual(restarted.snapshot, store.snapshot)
    }

    func testAccountSwitchPreservesOldOutboxAndRequiresAnExplicitNewMerge() throws {
        var state = ProfileSyncState(
            snapshot: ProfileStoreSnapshot(
                profiles: [Presets.navigation], manualProfileID: Presets.navigation.id))
        try state.connectAccount("first-account")
        state.seedPending()
        let oldPending = state.pending
        state.conflicts[Presets.navigation.id] = ProfileSyncConflict(
            remote: SyncedProfile(
                id: Presets.navigation.id, revision: UUID(), profile: nil, position: 0))
        try state.connectAccount("second-account")
        XCTAssertTrue(state.pending.isEmpty)
        XCTAssertTrue(state.conflicts.isEmpty)
        let data = try XCTUnwrap(state.accountArchives["first-account"])
        let archived = try JSONDecoder().decode(ProfileSyncState.self, from: data)
        XCTAssertEqual(archived.pending, oldPending)
        XCTAssertEqual(archived.conflicts.count, 1)
        XCTAssertEqual(state.snapshot, archived.snapshot)
    }

    func testRemoteOrderConvergesRegardlessOfDeliveryOrder() throws {
        let profiles = Presets.library
        let reversed = Array(profiles.reversed())
        let documents = reversed.enumerated().map {
            SyncedProfile(
                id: $0.element.id, revision: UUID(), profile: $0.element, position: $0.offset)
        }
        var left = ProfileSyncState(
            snapshot: ProfileStoreSnapshot(profiles: profiles, manualProfileID: profiles[0].id))
        var right = left
        for document in documents {
            try left.receive(document); try left.reconcile(protectedProfileID: nil)
        }
        for document in documents.reversed() {
            try right.receive(document); try right.reconcile(protectedProfileID: nil)
        }
        XCTAssertEqual(left.snapshot.profiles.map(\.id), reversed.map(\.id))
        XCTAssertEqual(left.snapshot, right.snapshot)
        XCTAssertTrue(left.pending.isEmpty)
    }

    func testOfflineDeletionAndReplayDoNotResurrectAnUneditedProfile() throws {
        let profiles = Presets.library
        var state = ProfileSyncState(
            snapshot: ProfileStoreSnapshot(profiles: profiles, manualProfileID: profiles[0].id))
        state.seedPending()
        for document in Array(state.pending.values) { state.acknowledge(document) }
        let deleted = profiles[1]
        let tombstone = SyncedProfile(id: deleted.id, revision: UUID(), profile: nil, position: 1)
        for _ in 0..<3 {
            try state.receive(tombstone); try state.reconcile(protectedProfileID: nil)
        }
        state.seedPending()
        XCTAssertFalse(state.snapshot.profiles.contains { $0.id == deleted.id })
        XCTAssertNil(state.pending[deleted.id])
        XCTAssertEqual(state.history.filter { $0.profile.id == deleted.id }.count, 1)
        var future = tombstone
        future.schema = 999
        XCTAssertThrowsError(try state.receive(future))
        XCTAssertEqual(state.acknowledged[deleted.id], tombstone)
    }

    func testExplicitReconnectRepublishesProfilesAfterCloudLibraryWasRemoved() throws {
        var state = ProfileSyncState(
            snapshot: ProfileStoreSnapshot(
                profiles: [Presets.navigation], manualProfileID: Presets.navigation.id))
        state.seedPending()
        let previous = try XCTUnwrap(state.pending[Presets.navigation.id])
        state.acknowledge(previous)
        state.serverFields[previous.id] = Data([1])
        state.prepareFullFetch(recordIDs: [])
        XCTAssertNil(state.serverFields[previous.id])
        XCTAssertNil(state.acknowledged[previous.id])
        XCTAssertEqual(state.pending[previous.id]?.profile, Presets.navigation)
    }

}
