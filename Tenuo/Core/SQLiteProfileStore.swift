import Foundation

final class SQLiteProfileStore: ProfileStore {
    private let database: ProfileDatabase
    fileprivate let now: () -> Date
    fileprivate var historySessions = HistoryCheckpointPolicy()
    private(set) var state: ProfileSyncState
    private var observers: [UUID: (ProfileStoreChange) -> Void] = [:]
    var onSyncChange: (() -> Void)?
    lazy var history: any ProfileHistoryStore = DatabaseProfileHistory(store: self)

    init(url: URL, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) throws
    {
        self.now = now
        database = try ProfileDatabase(url: url)
        if let saved = try database.load() {
            state = saved
        } else {
            let profiles: [Profile]
            if let stored = defaults.object(forKey: "TenuoProfiles") {
                guard let data = stored as? Data else { throw ProfileStoreError.invalidSnapshot }
                profiles = try JSONDecoder().decode([Profile].self, from: data)
            } else {
                profiles = Presets.library
            }
            guard let first = profiles.first else { throw ProfileStoreError.invalidSnapshot }
            let selected = defaults.string(forKey: "TenuoActiveProfile").flatMap(
                UUID.init(uuidString:))
            let snapshot = ProfileStoreSnapshot(
                profiles: profiles,
                manualProfileID: selected.flatMap { id in
                    profiles.contains { $0.id == id } ? id : nil
                } ?? first.id)
            try snapshot.validate()
            var initial = ProfileSyncState(snapshot: snapshot)
            if let stored = defaults.object(forKey: "TenuoProfileHistory") {
                guard let data = stored as? Data else { throw ProfileStoreError.invalidSnapshot }
                initial.history = try JSONDecoder().decode([ProfileHistoryEntry].self, from: data)
            }
            let portable = profiles.map { initial.portable($0) }
            initial.snapshot = ProfileStoreSnapshot(
                profiles: portable, manualProfileID: snapshot.manualProfileID)
            initial.history = initial.history.map { entry in
                ProfileHistoryEntry(
                    id: entry.id, profile: initial.portable(entry.profile), savedAt: entry.savedAt)
            }
            try database.save(initial)
            guard let saved = try database.load(), saved == initial else {
                throw ProfileSyncError.storageUnavailable
            }
            state = saved
        }
    }

    var snapshot: ProfileStoreSnapshot {
        ProfileStoreSnapshot(
            profiles: state.snapshot.profiles.map(state.resolved),
            manualProfileID: state.snapshot.manualProfileID)
    }

    func transaction(_ body: (inout ProfileSyncState) throws -> Void) throws {
        var next = state
        try body(&next)
        try persist(next)
    }

    private func persist(_ next: ProfileSyncState, sessions: HistoryCheckpointPolicy? = nil) throws
    {
        guard next != state else { return }
        try database.save(next)
        let previous = snapshot
        state = next
        if let sessions {
            historySessions = sessions
        } else if previous.profiles != snapshot.profiles {
            historySessions = HistoryCheckpointPolicy()
        }
        if previous != snapshot {
            let change = ProfileStoreChange(previous: previous, current: snapshot)
            for observer in Array(observers.values) { observer(change) }
        }
        onSyncChange?()
    }

    func addObserver(_ observer: @escaping (ProfileStoreChange) -> Void) -> UUID {
        let token = UUID()
        observers[token] = observer
        return token
    }

    func removeObserver(_ token: UUID) {
        observers.removeValue(forKey: token)
    }

    @discardableResult
    func updateProfile(_ profile: Profile) -> Bool {
        guard (try? profile.validate()) != nil else { return false }

        let current = snapshot
        guard let index = current.profiles.firstIndex(where: { $0.id == profile.id }) else {
            return false
        }
        guard current.profiles[index] != profile else { return false }

        var profiles = current.profiles
        profiles[index] = profile
        return replaceProfiles(profiles, selecting: current.manualProfileID)
    }

    @discardableResult
    func replaceProfiles(_ profiles: [Profile], selecting manualProfileID: UUID? = nil) -> Bool {
        let sanitised = profiles.isEmpty ? Presets.library : profiles
        guard sanitised.allSatisfy({ (try? $0.validate()) != nil }) else { return false }

        let current = snapshot
        let selectedID: UUID
        if let manualProfileID {
            guard sanitised.contains(where: { $0.id == manualProfileID }) else {
                return false
            }
            selectedID = manualProfileID
        } else if sanitised.contains(where: { $0.id == current.manualProfileID }) {
            selectedID = current.manualProfileID
        } else {
            selectedID = sanitised[0].id
        }

        let next = ProfileStoreSnapshot(profiles: sanitised, manualProfileID: selectedID)
        return commit(next, after: current)
    }

    @discardableResult
    func selectManualProfile(_ id: UUID) -> Bool {
        let current = snapshot
        guard id != current.manualProfileID,
            current.profiles.contains(where: { $0.id == id })
        else { return false }

        let next = ProfileStoreSnapshot(profiles: current.profiles, manualProfileID: id)
        return commit(next, after: current)
    }

    @discardableResult
    func restore(_ entry: ProfileHistoryEntry) -> Bool {
        guard (try? entry.profile.validate()) != nil else { return false }

        let current = snapshot
        guard let index = current.profiles.firstIndex(where: { $0.id == entry.profile.id }) else {
            return false
        }

        var profiles = current.profiles
        profiles[index] = entry.profile
        let next = ProfileStoreSnapshot(
            profiles: profiles,
            manualProfileID: current.manualProfileID)
        return commit(next, after: current, forceHistoryFor: entry.profile.id)
    }

    func uniqueName(_ wanted: String) -> String {
        let taken = Set(profiles.map(\.name))
        guard taken.contains(wanted) else { return wanted }

        var attempt = 2
        while taken.contains("\(wanted) \(attempt)") { attempt += 1 }
        return "\(wanted) \(attempt)"
    }

    func exportProfile(_ profile: Profile) throws -> Data {
        try ProfileDocument.encoder.encode(profile)
    }

    @discardableResult
    func importProfile(_ data: Data) throws -> Profile {
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        try decoded.validate()

        let current = snapshot
        let added = decoded.copy(named: uniqueName(decoded.name))
        let next = ProfileStoreSnapshot(
            profiles: current.profiles + [added],
            manualProfileID: added.id)
        guard commit(next, after: current) else { throw ProfileStoreError.unableToSave }
        return added
    }

    private func commit(
        _ next: ProfileStoreSnapshot, after previous: ProfileStoreSnapshot,
        forceHistoryFor profileID: UUID? = nil
    ) -> Bool {
        guard next != previous else { return false }
        var sessions = historySessions
        if next.manualProfileID != previous.manualProfileID { sessions = HistoryCheckpointPolicy() }
        do {
            try next.validate()
            var candidate = state
            let previous = candidate.snapshot
            let portable = ProfileStoreSnapshot(
                profiles: next.profiles.map { candidate.portable($0) },
                manualProfileID: next.manualProfileID)
            let date = now()
            for profile in previous.profiles
            where portable.profiles.first(where: { $0.id == profile.id }) != profile {
                if sessions.edit(profile.id, at: date, force: profile.id == profileID) {
                    candidate.recordHistory(profile, now: date)
                }
            }
            candidate.snapshot = portable
            candidate.recordLocalChanges(from: previous)
            try persist(candidate, sessions: sessions)
            return true
        } catch { return false }
    }
}

private final class DatabaseProfileHistory: ProfileHistoryStore {
    private unowned let store: SQLiteProfileStore
    init(store: SQLiteProfileStore) { self.store = store }
    func endSession() { store.historySessions = HistoryCheckpointPolicy() }
    func entries(for profileID: UUID) -> Result<[ProfileHistoryEntry], ProfileHistoryError> {
        .success(
            store.state.history.filter { $0.profile.id == profileID }.map {
                ProfileHistoryEntry(
                    id: $0.id, profile: store.state.resolved($0.profile), savedAt: $0.savedAt)
            }.sorted { $0.savedAt > $1.savedAt })
    }
    func record(_ profile: Profile, force: Bool) -> Bool {
        var sessions = store.historySessions
        let date = store.now()
        let checkpoint = sessions.edit(profile.id, at: date, force: force)
        do {
            if checkpoint {
                try store.transaction { state in
                    let profile = state.portable(profile)
                    state.recordHistory(profile, now: date)
                }
            }
            store.historySessions = sessions
            return true
        } catch { return false }
    }
    func removeAll(for profileID: UUID) -> Bool {
        do {
            try store.transaction { $0.history.removeAll { $0.profile.id == profileID } };
            return true
        } catch { return false }
    }
}
