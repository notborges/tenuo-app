import CloudKit
import Foundation
import Security

struct CloudProfileRecord: Sendable {
    var id: UUID
    var payload: Data
    var systemFields: Data
}

enum CloudProfileEvent: Sendable {
    case received([CloudProfileRecord])
    case saved([CloudProfileRecord])
    case state(Data)
    case accountChanged
    case failure(String)
    case waiting(String)
}

protocol ProfileSyncTransport: Sendable {
    func accountID() async throws -> String
    func start(serializedState: Data?) async throws
    func fetch() async throws
    func send(_ documents: [SyncedProfile], fields: [UUID: Data]) async throws
    func stop() async
}

typealias ProfileSyncTransportFactory = (
    @escaping @Sendable (CloudProfileEvent) async -> Void,
    @escaping @Sendable () async -> Bool
) -> any ProfileSyncTransport

struct CloudProfileConfiguration: Sendable {
    let containerID: String

    static var current: Self? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var information: CFDictionary?
        guard
            SecCodeCopySigningInformation(
                staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let info = information as? [String: Any],
            let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
            let services = entitlements["com.apple.developer.icloud-services"] as? [String],
            services.contains("CloudKit"),
            let containers = entitlements["com.apple.developer.icloud-container-identifiers"]
                as? [String],
            let containerID = containers.first,
            let environment = entitlements["com.apple.developer.icloud-container-environment"]
                as? String
        else { return nil }
        #if DEBUG
            guard environment == "Development" else { return nil }
        #else
            guard environment == "Production" else { return nil }
        #endif
        return Self(containerID: containerID)
    }
}

actor CloudProfileTransport: CKSyncEngineDelegate, ProfileSyncTransport {
    static var factory: ProfileSyncTransportFactory? {
        guard let configuration = CloudProfileConfiguration.current else { return nil }
        return { event, maySend in
            CloudProfileTransport(configuration: configuration, event: event, maySend: maySend)
        }
    }

    private let zone: CKRecordZone.ID
    private let automaticallySync: Bool
    private let container: CKContainer
    private let event: @Sendable (CloudProfileEvent) async -> Void
    private let maySend: @Sendable () async -> Bool
    private var engine: CKSyncEngine?
    private var outgoing: [UUID: (SyncedProfile, Data?)] = [:]
    private var sendingEnabled = false
    private var stopped = false
    private var firstAccount: String?

    init(
        configuration: CloudProfileConfiguration,
        zoneName: String = "TenuoProfiles",
        automaticallySync: Bool = true,
        event: @escaping @Sendable (CloudProfileEvent) async -> Void,
        maySend: @escaping @Sendable () async -> Bool
    ) {
        container = CKContainer(identifier: configuration.containerID)
        zone = CKRecordZone.ID(zoneName: zoneName)
        self.automaticallySync = automaticallySync
        self.event = event
        self.maySend = maySend
    }

    func accountID() async throws -> String {
        guard try await container.accountStatus() == .available else {
            throw ProfileSyncError.accountChanged
        }
        let account = try await container.userRecordID().recordName
        if firstAccount == nil { firstAccount = account }
        return account
    }

    func start(serializedState: Data?) throws {
        let state = try serializedState.map {
            try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase, stateSerialization: state, delegate: self)
        configuration.automaticallySync = automaticallySync
        engine = CKSyncEngine(configuration)
    }

    func fetch() async throws {
        guard let engine, !stopped else { throw CancellationError() }
        try await engine.fetchChanges()
    }

    func send(_ documents: [SyncedProfile], fields: [UUID: Data]) async throws {
        guard let engine, !stopped, await maySend() else { throw CancellationError() }
        outgoing = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, ($0, fields[$0.id])) })
        sendingEnabled = true
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone))])
        engine.state.add(
            pendingRecordZoneChanges: documents.map {
                .saveRecord(CKRecord.ID(recordName: $0.id.uuidString, zoneID: zone))
            })
        defer { sendingEnabled = false }
        try await engine.sendChanges()
    }

    func stop() async {
        stopped = true
        sendingEnabled = false
        await engine?.cancelOperations()
        engine = nil
        outgoing = [:]
    }

    func handleEvent(_ value: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard !stopped else { return }
        do {
            switch value {
            case let .stateUpdate(update):
                await event(.state(try JSONEncoder().encode(update.stateSerialization)))
            case .accountChange:
                sendingEnabled = false
                await event(.accountChanged)
            case let .fetchedRecordZoneChanges(changes):
                guard !changes.deletions.contains(where: { $0.recordID.zoneID == zone }) else {
                    sendingEnabled = false
                    await event(
                        .failure(
                            "Cloud profiles were removed outside Tenuo. Sync is paused; your local profiles are safe."
                        ))
                    return
                }
                let records = changes.modifications.compactMap { try? self.decode($0.record) }
                await event(.received(records))
            case let .sentRecordZoneChanges(changes):
                await event(.saved(try changes.savedRecords.map { try self.decode($0) }))
                for failed in changes.failedRecordSaves {
                    if failed.error.code == .serverRecordChanged,
                        let record = failed.error.serverRecord
                    {
                        syncEngine.state.remove(pendingRecordZoneChanges: [
                            .saveRecord(failed.record.recordID)
                        ])
                        await event(.received([try self.decode(record)]))
                    } else if [
                        .networkUnavailable, .networkFailure, .serviceUnavailable,
                        .requestRateLimited, .zoneBusy,
                    ].contains(failed.error.code) {
                        await event(
                            .waiting("Waiting for iCloud. Your changes are saved on this Mac."))
                    } else {
                        await event(
                            .failure(
                                "iCloud could not save a profile. Your changes are kept on this Mac. Try syncing again."
                            ))
                    }
                }
            case let .fetchedDatabaseChanges(changes):
                if changes.deletions.contains(where: { $0.zoneID == zone }) {
                    sendingEnabled = false
                    await event(
                        .failure(
                            "Your iCloud profile library was removed. Review sync setup before reconnecting."
                        ))
                }
            default: break
            }
        } catch {
            sendingEnabled = false
            await event(.failure(error.localizedDescription))
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !stopped, sendingEnabled, await maySend() else { return nil }
        do {
            guard try await accountID() == firstAccount, !stopped, await maySend() else {
                throw ProfileSyncError.accountChanged
            }
        } catch {
            sendingEnabled = false
            await event(.failure(error.localizedDescription))
            return nil
        }
        let documents = outgoing
        let changes = syncEngine.state.pendingRecordZoneChanges.filter {
            context.options.scope.contains($0)
        }
        do {
            var records: [CKRecord.ID: CKRecord] = [:]
            for (uuid, (document, fields)) in documents {
                let id = CKRecord.ID(recordName: uuid.uuidString, zoneID: zone)
                let record: CKRecord
                if let fields {
                    let decoder = try NSKeyedUnarchiver(forReadingFrom: fields)
                    decoder.requiresSecureCoding = true
                    guard let restored = CKRecord(coder: decoder), restored.recordID == id else {
                        throw ProfileSyncError.invalidDocument
                    }
                    decoder.finishDecoding()
                    record = restored
                } else {
                    record = CKRecord(recordType: "TenuoProfile", recordID: id)
                }
                try document.validate()
                let payload = try ProfileDocument.encoder.encode(document)
                guard payload.count < 900_000 else { throw ProfileSyncError.invalidDocument }
                record["payload"] = payload as CKRecordValue
                records[id] = record
            }
            let prepared = records
            return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
                guard let record = prepared[id] else {
                    syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
                    return nil
                }
                return record
            }
        } catch {
            sendingEnabled = false
            await event(.failure(error.localizedDescription))
            return nil
        }
    }

    private func decode(_ record: CKRecord) throws -> CloudProfileRecord {
        guard record.recordID.zoneID == zone, let id = UUID(uuidString: record.recordID.recordName)
        else {
            throw ProfileSyncError.invalidDocument
        }
        let payload =
            record.recordType == "TenuoProfile" ? (record["payload"] as? Data ?? Data()) : Data()
        let encoder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: encoder)
        encoder.finishEncoding()
        return CloudProfileRecord(id: id, payload: payload, systemFields: encoder.encodedData)
    }
}
