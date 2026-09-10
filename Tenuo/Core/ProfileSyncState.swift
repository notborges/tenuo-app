import Foundation

struct SyncedProfile: Codable, Equatable, Sendable {
    var schema = 1
    var id: UUID
    var revision: UUID
    var profile: Profile?
    var position: Int

    func validate() throws {
        guard schema == 1, position >= 0, profile == nil || profile?.id == id else {
            throw ProfileSyncError.invalidDocument
        }
        try profile?.validate()
        var containsBookmark = false
        _ = profile?.transformingMacActions { action in
            if case let .file(target) = action, !target.bookmark.isEmpty || target.localID == nil {
                containsBookmark = true
            }
            if case let .shortcut(target) = action, target.localID == nil {
                containsBookmark = true
            }
            return action
        }
        guard !containsBookmark else { throw ProfileSyncError.invalidDocument }
    }

    func hasSameContent(as other: SyncedProfile) -> Bool {
        profile == other.profile && position == other.position
    }
}

struct ProfileSyncConflict: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { remote.id }
    var remote: SyncedProfile
}

enum ProfileSyncError: LocalizedError {
    case invalidDocument
    case storageUnavailable
    case accountChanged
    case unresolvedConflict

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "A profile could not be read. Update Tenuo before trying again."
        case .storageUnavailable:
            return "Tenuo could not save your profiles. Your existing data has been kept."
        case .accountChanged:
            return "Your iCloud account changed. Connect sync again to review your profiles."
        case .unresolvedConflict:
            return "Review the conflicting versions before syncing this profile."
        }
    }
}

struct ProfileSyncState: Codable, Equatable, Sendable {
    var schema = 1
    var accountArchives: [String: Data] = [:]
    var quarantined: [UUID: Data] = [:]
    var snapshot: ProfileStoreSnapshot
    var targets: [String: LocalActionTarget] = [:]
    var history: [ProfileHistoryEntry] = []
    var accountID: String?
    var enabled = false
    var pending: [UUID: SyncedProfile] = [:]
    var acknowledged: [UUID: SyncedProfile] = [:]
    var incoming: [UUID: SyncedProfile] = [:]
    var conflicts: [UUID: ProfileSyncConflict] = [:]
    var serverFields: [UUID: Data] = [:]
    var engineState: Data?
    var lastSyncedAt: Date?

    func validate() throws {
        guard schema == 1 else { throw ProfileSyncError.invalidDocument }
        try snapshot.validate()
        for documents in [pending, acknowledged, incoming] {
            for (id, document) in documents {
                guard id == document.id else { throw ProfileSyncError.invalidDocument }
                try document.validate()
            }
        }
        for (id, conflict) in conflicts {
            guard id == conflict.id else { throw ProfileSyncError.invalidDocument }
            try conflict.remote.validate()
        }
        for entry in history { try entry.profile.validate() }
    }

    mutating func connectAccount(_ account: String) throws {
        guard accountID != account else { return }
        if let accountID {
            var archive = self
            archive.accountArchives = [:]
            accountArchives[accountID] = try JSONEncoder().encode(archive)
        }
        pending = [:]
        acknowledged = [:]
        incoming = [:]
        conflicts = [:]
        serverFields = [:]
        quarantined = [:]
        engineState = nil
        lastSyncedAt = nil
        accountID = account
    }

    mutating func recordHistory(_ profile: Profile, now: Date = Date()) {
        let latest = history.first { $0.profile.id == profile.id }
        if let latest {
            if latest.profile == profile { return }
        }
        history.insert(ProfileHistoryEntry(profile: profile, savedAt: now), at: 0)
        var count = 0
        history.removeAll { entry in
            guard entry.profile.id == profile.id else { return false }
            count += 1
            return count > 20
        }
    }

    mutating func recordLocalChanges(from previous: ProfileStoreSnapshot) {
        let old = Dictionary(
            uniqueKeysWithValues: previous.profiles.enumerated().map { ($0.element.id, $0) })
        let next = Dictionary(
            uniqueKeysWithValues: snapshot.profiles.enumerated().map { ($0.element.id, $0) })
        for id in Set(old.keys).union(next.keys) {
            guard old[id]?.element != next[id]?.element || old[id]?.offset != next[id]?.offset
            else { continue }
            pending[id] = SyncedProfile(
                id: id, revision: UUID(), profile: next[id]?.element,
                position: next[id]?.offset ?? old[id]?.offset ?? 0)
        }
    }

    mutating func prepareFullFetch(recordIDs: Set<UUID>) {
        for id in Set(acknowledged.keys).union(serverFields.keys).subtracting(recordIDs) {
            acknowledged[id] = nil
            serverFields[id] = nil
        }
        seedPending()
    }

    mutating func seedPending() {
        for (position, profile) in snapshot.profiles.enumerated() where pending[profile.id] == nil {
            if acknowledged[profile.id]?.profile != profile {
                pending[profile.id] = SyncedProfile(
                    id: profile.id, revision: UUID(), profile: profile, position: position)
            }
        }
    }

    mutating func receive(_ remote: SyncedProfile) throws {
        try remote.validate()
        incoming[remote.id] = remote
    }

    mutating func reconcile(protectedProfileID: UUID?) throws {
        for remote in incoming.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let id = remote.id
            if let pending = pending[id] {
                if pending.revision == remote.revision || pending.hasSameContent(as: remote) {
                    self.pending[id] = nil
                    acknowledged[id] = remote
                    incoming[id] = nil
                    conflicts[id] = nil
                    continue
                }
                if acknowledged[id]?.revision == remote.revision {
                    incoming[id] = nil
                    continue
                }
                conflicts[id] = ProfileSyncConflict(remote: remote)
                incoming[id] = nil
                continue
            }
            if acknowledged[id]?.revision == remote.revision {
                incoming[id] = nil
                continue
            }
            if remote.profile == nil, snapshot.manualProfileID == id {
                conflicts[id] = ProfileSyncConflict(remote: remote)
                incoming[id] = nil
                continue
            }
            if protectedProfileID == id { continue }
            try apply(remote)
            acknowledged[id] = remote
            conflicts[id] = nil
            incoming[id] = nil
        }
        let positions = Dictionary(
            uniqueKeysWithValues: snapshot.profiles.enumerated().map {
                (
                    $0.element.id,
                    pending[$0.element.id]?.position ?? acknowledged[$0.element.id]?.position
                        ?? $0.offset
                )
            })
        let ordered = snapshot.profiles.sorted {
            let left = positions[$0.id] ?? 0
            let right = positions[$1.id] ?? 0
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
        snapshot = ProfileStoreSnapshot(
            profiles: ordered, manualProfileID: snapshot.manualProfileID)
    }

    mutating func apply(_ remote: SyncedProfile) throws {
        var profiles = snapshot.profiles
        if let old = profiles.first(where: { $0.id == remote.id }), old != remote.profile {
            recordHistory(old)
        }
        profiles.removeAll { $0.id == remote.id }
        if let profile = remote.profile {
            profiles.insert(profile, at: min(remote.position, profiles.count))
        }
        guard !profiles.isEmpty, profiles.contains(where: { $0.id == snapshot.manualProfileID })
        else {
            throw ProfileSyncError.unresolvedConflict
        }
        snapshot = ProfileStoreSnapshot(
            profiles: profiles, manualProfileID: snapshot.manualProfileID)
    }

    mutating func acknowledge(_ sent: SyncedProfile) {
        acknowledged[sent.id] = sent
        if pending[sent.id]?.revision == sent.revision { pending[sent.id] = nil }
    }
}
