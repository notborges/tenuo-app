import Foundation
import XCTest

private enum SyncCallbackContext {
    @TaskLocal static var active = false
}

private actor SyncTransportFixture: ProfileSyncTransport {
    let event: @Sendable (CloudProfileEvent) async -> Void
    let maySend: @Sendable () async -> Bool
    var account = "test-account"
    var documents: [SyncedProfile] = []
    var uploaded: [SyncedProfile] = []
    var holdFetch = false
    var fetching = false
    var stoppedInCallback: Bool?
    private var fetchContinuation: CheckedContinuation<Void, Never>?

    init(
        event: @escaping @Sendable (CloudProfileEvent) async -> Void,
        maySend: @escaping @Sendable () async -> Bool,
        documents: [SyncedProfile] = [], holdFetch: Bool = false
    ) {
        self.event = event
        self.maySend = maySend
        self.documents = documents
        self.holdFetch = holdFetch
    }

    func accountID() -> String { account }
    func start(serializedState: Data?) {}
    func fetch() async throws {
        fetching = true
        if holdFetch { await withCheckedContinuation { fetchContinuation = $0 } }
        await event(.received(try documents.map(record)))
    }
    func releaseFetch() { fetchContinuation?.resume(); fetchContinuation = nil }
    func send(_ documents: [SyncedProfile], fields: [UUID: Data]) async throws {
        guard await maySend() else { return }
        uploaded.append(contentsOf: documents)
        await event(.saved(try documents.map(record)))
    }
    func emit(_ document: SyncedProfile) async throws {
        await event(.received([try record(document)]))
    }
    func failFromCallback() async {
        await SyncCallbackContext.$active.withValue(true) {
            await event(.failure("Upload rejected"))
        }
    }
    func stop() { stoppedInCallback = SyncCallbackContext.active }
    private func record(_ document: SyncedProfile) throws -> CloudProfileRecord {
        CloudProfileRecord(
            id: document.id, payload: try JSONEncoder().encode(document), systemFields: Data())
    }
}

@MainActor
final class ProfileSyncLifecycleTests: XCTestCase {
    private func store(enabled: Bool = true) throws -> SQLiteProfileStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        let domain = "app.tenuo.sync-lifecycle.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try SQLiteProfileStore(
            url: directory.appendingPathComponent("profiles.sqlite"), defaults: defaults)
        try store.transaction { state in
            try state.connectAccount("test-account")
            state.enabled = enabled
            state.seedPending()
        }
        return store
    }

    private func waitUntil(_ predicate: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !(await predicate()) {
            guard Date() < deadline else {
                XCTFail("Sync did not reach the expected state"); return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testCallbackFailureStopsOutsideCloudKitContextAndKeepsPendingEdits() async throws {
        let store = try store()
        var fixture: SyncTransportFixture?
        let sync = ProfileSyncController(
            store: store, hasPro: { true },
            factory: { event, gate in
                let transport = SyncTransportFixture(event: event, maySend: gate, holdFetch: true)
                fixture = transport
                return transport
            })
        sync.syncNow()
        try await waitUntil { await fixture?.fetching == true }
        let transport = try XCTUnwrap(fixture)
        let pending = store.state.pending
        await transport.failFromCallback()
        try await waitUntil { await transport.stoppedInCallback != nil }
        let inheritedCallback = await transport.stoppedInCallback
        XCTAssertEqual(inheritedCallback, false)
        XCTAssertEqual(sync.status, .attention)
        XCTAssertEqual(store.state.pending, pending)
        await transport.releaseFetch()
        sync.stop()
    }

    func testFreeCannotConnectAndEntitlementLossRejectsLateDownloads() async throws {
        let store = try store()
        var pro = false
        var fixture: SyncTransportFixture?
        let sync = ProfileSyncController(
            store: store, hasPro: { pro },
            factory: { event, gate in
                let created = SyncTransportFixture(event: event, maySend: gate)
                fixture = created
                return created
            })
        sync.prepare()
        sync.syncNow()
        XCTAssertNil(fixture)
        XCTAssertEqual(sync.status, .requiresPro)
        pro = true
        sync.syncNow()
        try await waitUntil { fixture != nil }
        let transport = try XCTUnwrap(fixture)
        try await waitUntil { !sync.isBusy }
        XCTAssertTrue(store.state.pending.isEmpty)
        pro = false
        sync.entitlementChanged()
        var remote = SyncedProfile(
            id: store.manualProfile.id, revision: UUID(),
            profile: store.state.snapshot.manualProfile, position: 0)
        remote.profile?.name = "Late download"
        try await transport.emit(remote)
        XCTAssertNotEqual(store.manualProfile.name, "Late download")
        XCTAssertEqual(sync.status, .requiresPro)
        sync.stop()
    }

    func testAccountMismatchNeverUploadsLocalLibrary() async throws {
        let store = try store()
        let pending = store.state.pending
        var fixture: SyncTransportFixture?
        let sync = ProfileSyncController(
            store: store, hasPro: { true },
            factory: { event, gate in
                let created = SyncTransportFixture(event: event, maySend: gate)
                fixture = created
                return created
            })
        try store.transaction { $0.accountID = "different-account" }
        sync.syncNow()
        try await waitUntil { sync.status == .attention }
        let transport = try XCTUnwrap(fixture)
        let uploaded = await transport.uploaded
        XCTAssertTrue(uploaded.isEmpty)
        XCTAssertEqual(store.state.pending, pending)
        XCTAssertTrue(store.state.enabled)
        sync.stop()
    }

    func testLosingProDiscardsConnectionReviewBeforeReactivation() async throws {
        let store = try store(enabled: false)
        let original = store.snapshot
        var pro = true
        var fixture: SyncTransportFixture?
        let sync = ProfileSyncController(
            store: store, hasPro: { pro },
            factory: { event, gate in
                let created = SyncTransportFixture(event: event, maySend: gate)
                fixture = created
                return created
            })
        sync.prepare()
        try await waitUntil { sync.preview != nil && !sync.isBusy }
        let previousTransport = try XCTUnwrap(fixture)

        pro = false
        sync.entitlementChanged()
        XCTAssertNil(sync.preview)
        XCTAssertEqual(sync.status, .requiresPro)
        pro = true
        sync.entitlementChanged()
        sync.confirm()
        XCTAssertFalse(sync.enabled)
        XCTAssertEqual(store.snapshot, original)
        let allowed = await previousTransport.maySend()
        XCTAssertFalse(allowed)

        sync.prepare()
        try await waitUntil { sync.preview != nil && !sync.isBusy }
        sync.confirm()
        try await waitUntil { sync.status == .current }
        XCTAssertTrue(sync.enabled)
        sync.stop()
    }

    func testInitialReviewDoesNotUploadUntilConfirmedAndPauseKeepsEdits() async throws {
        let store = try store(enabled: false)
        var fixture: SyncTransportFixture?
        let sync = ProfileSyncController(
            store: store, hasPro: { true },
            factory: { event, gate in
                let created = SyncTransportFixture(event: event, maySend: gate)
                fixture = created
                return created
            })
        sync.prepare()
        try await waitUntil { sync.preview != nil && !sync.isBusy }
        let reviewTransport = try XCTUnwrap(fixture)
        let reviewUploads = await reviewTransport.uploaded
        XCTAssertTrue(reviewUploads.isEmpty)
        XCTAssertFalse(sync.enabled)
        sync.confirm()
        try await waitUntil { sync.status == .current }
        XCTAssertTrue(store.state.pending.isEmpty)
        sync.disable()
        var edited = store.manualProfile
        edited.name = "Changed while paused"
        XCTAssertTrue(store.updateProfile(edited))
        let pending = store.state.pending
        var remote = SyncedProfile(id: edited.id, revision: UUID(), profile: edited, position: 0)
        remote.profile?.name = "Stale session"
        try await reviewTransport.emit(remote)
        XCTAssertEqual(store.state.pending, pending)
        XCTAssertEqual(store.manualProfile.name, edited.name)
        sync.stop()
    }
    func testPauseDuringFetchRejectsDownloadedDataAndNeverUploads() async throws {
        let store = try store()
        let original = store.state
        var remote = SyncedProfile(
            id: store.manualProfile.id, revision: UUID(),
            profile: store.state.snapshot.manualProfile, position: 0)
        remote.profile?.name = "Arrived after pause"
        var fixture: SyncTransportFixture?
        let sync = ProfileSyncController(
            store: store, hasPro: { true },
            factory: { event, gate in
                let created = SyncTransportFixture(
                    event: event, maySend: gate, documents: [remote], holdFetch: true)
                fixture = created
                return created
            })
        sync.syncNow()
        try await waitUntil { await fixture?.fetching == true }
        let transport = try XCTUnwrap(fixture)
        sync.disable()
        await transport.releaseFetch()
        try await transport.emit(remote)
        XCTAssertEqual(store.snapshot, original.snapshot)
        XCTAssertEqual(store.state.pending, original.pending)
        let uploaded = await transport.uploaded
        XCTAssertTrue(uploaded.isEmpty)
        XCTAssertEqual(sync.status, .off)
        sync.stop()
    }

    func testOneConflictDoesNotBlockOtherProfilesFromSyncing() async throws {
        let store = try store()
        var fixture: SyncTransportFixture?
        let sync = ProfileSyncController(
            store: store, hasPro: { true },
            factory: { event, gate in
                let created = SyncTransportFixture(event: event, maySend: gate)
                fixture = created
                return created
            })
        sync.syncNow()
        try await waitUntil { sync.status == .current }
        let transport = try XCTUnwrap(fixture)
        var local = store.profiles[0]
        var remote = try XCTUnwrap(store.state.acknowledged[local.id])
        local.name = "Local conflicting edit"
        XCTAssertTrue(store.updateProfile(local))
        remote.revision = UUID()
        remote.profile?.name = "Remote conflicting edit"
        try await transport.emit(remote)
        XCTAssertEqual(sync.conflicts.count, 1)
        var independent = store.profiles[1]
        independent.name = "Independent edit"
        XCTAssertTrue(store.updateProfile(independent))
        try await waitUntil { store.state.pending[independent.id] == nil }
        let uploaded = await transport.uploaded
        XCTAssertTrue(uploaded.contains { $0.profile?.name == "Independent edit" })
        XCTAssertEqual(sync.conflicts.count, 1)
        sync.stop()
    }

}
