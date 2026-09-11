import Foundation

struct ProfileStoreSnapshot: Codable, Equatable, Sendable {
    let profiles: [Profile]
    let manualProfileID: UUID

    init(profiles: [Profile], manualProfileID: UUID) {
        self.profiles = profiles
        self.manualProfileID = manualProfileID
    }

    func validate() throws {
        guard !profiles.isEmpty, Set(profiles.map(\.id)).count == profiles.count,
            profiles.contains(where: { $0.id == manualProfileID })
        else {
            throw ProfileStoreError.invalidSnapshot
        }
        for profile in profiles { try profile.validate() }
    }

    var manualProfile: Profile {
        guard let profile = profiles.first(where: { $0.id == manualProfileID }) else {
            preconditionFailure("A profile store snapshot must contain its manual profile")
        }
        return profile
    }

    private enum CodingKeys: String, CodingKey { case profiles, manualProfileID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let profiles = try container.decode([Profile].self, forKey: .profiles)
        let manualProfileID = try container.decode(UUID.self, forKey: .manualProfileID)

        guard !profiles.isEmpty,
            profiles.contains(where: { $0.id == manualProfileID }),
            profiles.allSatisfy({ (try? $0.validate()) != nil })
        else {
            throw ProfileStoreError.invalidSnapshot
        }

        self.init(profiles: profiles, manualProfileID: manualProfileID)
        try validate()
    }
}

struct ProfileStoreChange: Equatable, Sendable {
    let previous: ProfileStoreSnapshot
    let current: ProfileStoreSnapshot

    var didChangeProfiles: Bool { previous.profiles != current.profiles }
    var didChangeManualSelection: Bool {
        previous.manualProfileID != current.manualProfileID
    }
}

protocol ProfileStore: AnyObject {
    var snapshot: ProfileStoreSnapshot { get }
    var history: any ProfileHistoryStore { get }

    func addObserver(_ observer: @escaping (ProfileStoreChange) -> Void) -> UUID
    func removeObserver(_ token: UUID)

    @discardableResult
    func updateProfile(_ profile: Profile) -> Bool

    @discardableResult
    func replaceProfiles(_ profiles: [Profile], selecting manualProfileID: UUID?) -> Bool

    @discardableResult
    func selectManualProfile(_ id: UUID) -> Bool

    @discardableResult
    func restore(_ entry: ProfileHistoryEntry) -> Bool

    func uniqueName(_ wanted: String) -> String
    func exportProfile(_ profile: Profile) throws -> Data

    @discardableResult
    func importProfile(_ data: Data) throws -> Profile
}

extension ProfileStore {
    var profiles: [Profile] { snapshot.profiles }
    var manualProfileID: UUID { snapshot.manualProfileID }
    var manualProfile: Profile { snapshot.manualProfile }
}

enum ProfileStoreError: LocalizedError, Equatable {
    case invalidSnapshot
    case unableToSave

    var errorDescription: String? {
        switch self {
        case .invalidSnapshot:
            return "The profile data is incomplete or invalid."
        case .unableToSave:
            return "Tenuo could not save the profile."
        }
    }
}

enum ProfileDocument {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

final class UserDefaultsProfileStore: ProfileStore {
    private enum Key {
        static let profiles = "TenuoProfiles"
        static let manualProfile = "TenuoActiveProfile"
    }

    private let defaults: UserDefaults
    let history: any ProfileHistoryStore
    private var observers: [UUID: (ProfileStoreChange) -> Void] = [:]

    init(
        defaults: UserDefaults = .standard,
        history: (any ProfileHistoryStore)? = nil
    ) {
        self.defaults = defaults
        self.history = history ?? UserDefaultsProfileHistoryStore(defaults: defaults)
    }

    var snapshot: ProfileStoreSnapshot {
        let profiles = loadProfiles()
        return ProfileStoreSnapshot(
            profiles: profiles,
            manualProfileID: storedManualProfileID(for: profiles))
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

    private func loadProfiles() -> [Profile] {
        guard let data = defaults.data(forKey: Key.profiles),
            let decoded = try? JSONDecoder().decode([Profile].self, from: data),
            !decoded.isEmpty,
            decoded.allSatisfy({ (try? $0.validate()) != nil })
        else {
            return Presets.library
        }
        return decoded
    }

    private func storedManualProfileID(for profiles: [Profile]) -> UUID {
        if let raw = defaults.string(forKey: Key.manualProfile),
            let id = UUID(uuidString: raw),
            profiles.contains(where: { $0.id == id })
        {
            return id
        }
        return profiles[0].id
    }

    private func commit(
        _ next: ProfileStoreSnapshot,
        after previous: ProfileStoreSnapshot,
        forceHistoryFor profileID: UUID? = nil
    ) -> Bool {
        guard next != previous,
            let data = try? ProfileDocument.encoder.encode(next.profiles),
            prepareHistory(before: previous, after: next, forceHistoryFor: profileID)
        else { return false }

        defaults.set(data, forKey: Key.profiles)
        if next.manualProfileID != previous.manualProfileID { history.endSession() }
        if next.manualProfileID != previous.manualProfileID {
            defaults.set(next.manualProfileID.uuidString, forKey: Key.manualProfile)
        }

        let change = ProfileStoreChange(previous: previous, current: next)
        for observer in Array(observers.values) {
            observer(change)
        }
        return true
    }

    private func prepareHistory(
        before previous: ProfileStoreSnapshot,
        after next: ProfileStoreSnapshot,
        forceHistoryFor profileID: UUID?
    ) -> Bool {
        guard previous.profiles != next.profiles else { return true }

        let currentByID = Dictionary(uniqueKeysWithValues: next.profiles.map { ($0.id, $0) })
        for profile in previous.profiles {
            guard let current = currentByID[profile.id] else {
                guard history.removeAll(for: profile.id) else { return false }
                continue
            }
            guard current != profile else { continue }
            guard history.record(profile, force: profile.id == profileID) else { return false }
        }
        return true
    }
}
