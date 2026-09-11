import AppKit
import CloudKit
import Foundation

@main
struct LiveSyncCheck {
    @MainActor static func main() async {
        setbuf(stdout, nil)
        _ = NSApplication.shared
        guard let configuration = CloudProfileConfiguration.current else {
            print("Missing development CloudKit entitlements")
            exit(1)
        }
        let zoneName = "TenuoSyncCheck-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(zoneName)
        let database = CKContainer(identifier: configuration.containerID).privateCloudDatabase
        defer { try? FileManager.default.removeItem(at: directory) }
        var controllers: [ProfileSyncController] = []
        do {
            let navigation = Presets.navigation.copy(named: "Sync verification")
            let baseline = Profile(name: "Second client", layers: [Layer(name: "Base")])
            func store(_ name: String, profile: Profile) throws -> SQLiteProfileStore {
                guard
                    let defaults = UserDefaults(
                        suiteName: "app.tenuo.verification.\(zoneName).\(name)")
                else {
                    throw ProfileSyncError.storageUnavailable
                }
                defer {
                    defaults.removePersistentDomain(
                        forName: "app.tenuo.verification.\(zoneName).\(name)")
                }
                defaults.set(try JSONEncoder().encode([profile]), forKey: "TenuoProfiles")
                return try SQLiteProfileStore(
                    url: directory.appendingPathComponent("\(name).sqlite"), defaults: defaults)
            }
            let a = try store("a", profile: navigation)
            let b = try store("b", profile: baseline)
            var proEnabled = false
            var transportCount = 0
            func controller(_ store: SQLiteProfileStore) -> ProfileSyncController {
                ProfileSyncController(
                    store: store, hasPro: { proEnabled },
                    factory: { event, gate in
                        transportCount += 1
                        return CloudProfileTransport(
                            configuration: configuration, zoneName: zoneName,
                            automaticallySync: false, event: event, maySend: gate)
                    })
            }
            let syncA = controller(a)
            let syncB = controller(b)
            controllers = [syncA, syncB]
            func wait(_ label: String, sync: ProfileSyncController, until predicate: () -> Bool)
                async throws
            {
                let deadline = Date().addingTimeInterval(45)
                while !predicate() {
                    if sync.status == .attention && sync.preview == nil && sync.conflicts.isEmpty {
                        throw NSError(
                            domain: label, code: 1,
                            userInfo: [
                                NSLocalizedDescriptionKey: sync.message ?? "Sync needs attention"
                            ])
                    }
                    if Date() >= deadline {
                        throw NSError(
                            domain: label, code: 2,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "Timed out: \(sync.status), \(sync.message ?? "no message")"
                            ])
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
                print("\(label): OK")
            }
            syncA.prepare()
            guard syncA.status == .requiresPro, transportCount == 0 else {
                throw CheckFailure(message: "Free access created a cloud connection")
            }
            print("Free access gate: OK")
            proEnabled = true
            syncA.entitlementChanged()
            syncB.entitlementChanged()
            syncA.prepare()
            try await wait("First connection preview", sync: syncA) {
                syncA.preview != nil && !syncA.isBusy
            }
            syncA.confirm()
            try await wait("Cloud upload", sync: syncA) {
                syncA.status == .current && !syncA.isBusy
            }
            syncB.prepare()
            try await wait("Second connection preview", sync: syncB) {
                syncB.preview != nil && !syncB.isBusy
            }
            do {
                _ = try await database.record(
                    for: CKRecord.ID(
                        recordName: baseline.id.uuidString,
                        zoneID: CKRecordZone.ID(zoneName: zoneName)))
                throw CheckFailure(message: "Connection review uploaded before confirmation")
            } catch let error as CKError where error.code == .unknownItem {
                print("Review does not upload: OK")
            }
            syncB.confirm()
            try await wait("Second client download", sync: syncB) {
                syncB.status == .current && b.profiles.contains { $0.id == navigation.id }
            }
            var renamed = a.manualProfile
            renamed.name = "Renamed through iCloud"
            guard a.updateProfile(renamed) else { throw ProfileSyncError.storageUnavailable }
            try await wait("Rename upload", sync: syncA) {
                a.state.pending.isEmpty && !syncA.isBusy
            }
            syncB.syncNow()
            try await wait("Rename received", sync: syncB) {
                b.profiles.contains { $0.id == navigation.id && $0.name == renamed.name }
                    && !syncB.isBusy
            }
            syncA.disable()
            syncB.disable()
            renamed.name = "Client A offline edit"
            guard a.updateProfile(renamed) else { throw ProfileSyncError.storageUnavailable }
            guard var competing = b.profiles.first(where: { $0.id == navigation.id }) else {
                throw CheckFailure(message: "Downloaded profile missing")
            }
            competing.name = "Client B offline edit"
            guard b.updateProfile(competing) else { throw ProfileSyncError.storageUnavailable }
            syncA.prepare()
            try await wait("Resume A", sync: syncA) { syncA.preview != nil && !syncA.isBusy }
            syncA.confirm()
            try await wait("Offline edit uploaded", sync: syncA) {
                syncA.status == .current && !syncA.isBusy
            }
            syncB.prepare()
            try await wait("Resume B", sync: syncB) { syncB.preview != nil && !syncB.isBusy }
            syncB.confirm()
            try await wait("Conflict preserved", sync: syncB) {
                syncB.conflicts.count == 1 && !syncB.isBusy
            }
            guard let conflict = syncB.conflicts.first,
                conflict.remote.profile?.name == renamed.name,
                b.profiles.contains(where: { $0.name == competing.name })
            else { throw ProfileSyncError.unresolvedConflict }
            syncB.resolve(conflict, keepLocal: false)
            try await wait("Conflict resolved", sync: syncB) {
                syncB.conflicts.isEmpty && syncB.status == .current && !syncB.isBusy
            }
            guard
                a.replaceProfiles(
                    a.profiles.filter { $0.id != navigation.id }, selecting: baseline.id)
            else { throw ProfileSyncError.storageUnavailable }
            try await wait("Deletion uploaded", sync: syncA) {
                a.state.pending.isEmpty && !syncA.isBusy
            }
            syncB.syncNow()
            try await wait("Deletion received", sync: syncB) {
                !b.profiles.contains { $0.id == navigation.id } && !syncB.isBusy
            }
            proEnabled = false
            syncA.entitlementChanged()
            syncB.entitlementChanged()
            guard syncA.status == .requiresPro, syncB.status == .requiresPro else {
                throw CheckFailure(message: "Pro loss did not pause sync")
            }
            let connectionCount = transportCount
            guard var gatedProfile = b.profiles.first(where: { $0.id == baseline.id }) else {
                throw CheckFailure(message: "Merged profile missing")
            }
            gatedProfile.name = "Local edit without Pro"
            guard b.updateProfile(gatedProfile) else { throw ProfileSyncError.storageUnavailable }
            syncB.syncNow()
            guard transportCount == connectionCount, !b.state.pending.isEmpty else {
                throw CheckFailure(message: "Free edit was not retained locally")
            }
            let cloudRecord = try await database.record(
                for: CKRecord.ID(
                    recordName: baseline.id.uuidString, zoneID: CKRecordZone.ID(zoneName: zoneName))
            )
            guard let payload = cloudRecord["payload"] as? Data,
                try JSONDecoder().decode(SyncedProfile.self, from: payload).profile?.name
                    == baseline.name
            else { throw CheckFailure(message: "Free edit reached iCloud") }
            syncB.stop()
            let reopened = try store("b", profile: baseline)
            guard reopened.profiles.contains(where: { $0.name == gatedProfile.name }),
                reopened.state.pending == b.state.pending
            else { throw CheckFailure(message: "Pending edit did not survive reopening SQLite") }
            print("Pro loss retains local edits without uploading: OK")
            print("Pending edits survive reopening SQLite: OK")
            for controller in controllers { controller.stop() }
            _ = try await database.deleteRecordZone(withID: CKRecordZone.ID(zoneName: zoneName))
            try FileManager.default.removeItem(at: directory)
            print("Live CloudKit checks passed; isolated test zone removed")
            return
        } catch {
            for controller in controllers { controller.stop() }
            do {
                _ = try await database.deleteRecordZone(withID: CKRecordZone.ID(zoneName: zoneName))
            } catch let cleanup as CKError where cleanup.code == .zoneNotFound {
            } catch {
                print("Cleanup failed. Remove Development zone \(zoneName): \(error)")
            }
            try? FileManager.default.removeItem(at: directory)
            print("Live check failed: \(error)")
            exit(1)
        }
    }
}

private struct CheckFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
