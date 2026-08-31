import Foundation

// Store profiles as one JSON value so persistence and import/export share a format.
final class Settings {
    private enum Key {
        static let isEnabled = "TenuoEnabled"
        static let profiles = "TenuoProfiles"
        static let activeProfile = "TenuoActiveProfile"
        static let showsCheatSheet = "TenuoShowsCheatSheet"
        static let checksForUpdates = "TenuoChecksForUpdates"
    }

    private let defaults: UserDefaults

    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.showsCheatSheet: true,
        ])
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Key.isEnabled) }
        set {
            guard newValue != isEnabled else { return }
            defaults.set(newValue, forKey: Key.isEnabled)
            onChange?()
        }
    }

    var showsCheatSheet: Bool {
        get { defaults.bool(forKey: Key.showsCheatSheet) }
        set {
            guard newValue != showsCheatSheet else { return }
            defaults.set(newValue, forKey: Key.showsCheatSheet)
            onChange?()
        }
    }

    var checksForUpdates: Bool {
        get { defaults.bool(forKey: Key.checksForUpdates) }
        set {
            guard newValue != checksForUpdates else { return }
            defaults.set(newValue, forKey: Key.checksForUpdates)
            onChange?()
        }
    }

    var profiles: [Profile] {
        get {
            guard let data = defaults.data(forKey: Key.profiles),
                let decoded = try? JSONDecoder().decode([Profile].self, from: data),
                !decoded.isEmpty,
                decoded.allSatisfy({ (try? $0.validate()) != nil })
            else { return Presets.library }
            return decoded
        }
        set {
            let sanitised = newValue.isEmpty ? Presets.library : newValue
            guard sanitised.allSatisfy({ (try? $0.validate()) != nil }) else { return }
            guard sanitised != profiles else { return }
            write(profiles: sanitised)
            onChange?()
        }
    }

    private func write(profiles: [Profile]) {
        guard profiles.allSatisfy({ (try? $0.validate()) != nil }) else { return }
        guard let data = try? Self.encoder.encode(profiles) else { return }
        defaults.set(data, forKey: Key.profiles)
    }

    var activeProfileID: UUID {
        get {
            let all = profiles
            if let raw = defaults.string(forKey: Key.activeProfile),
                let id = UUID(uuidString: raw),
                all.contains(where: { $0.id == id })
            {
                return id
            }
            return all[0].id
        }
        set {
            guard newValue != activeProfileID else { return }
            defaults.set(newValue.uuidString, forKey: Key.activeProfile)
            onChange?()
        }
    }

    var activeProfile: Profile {
        get {
            let all = profiles
            return all.first { $0.id == activeProfileID } ?? all[0]
        }
        set {
            guard (try? newValue.validate()) != nil else { return }
            var all = profiles
            guard let index = all.firstIndex(where: { $0.id == newValue.id }) else { return }
            guard all[index] != newValue else { return }
            all[index] = newValue
            write(profiles: all)
            onChange?()
        }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    func exportJSON() throws -> Data {
        try Self.encoder.encode(activeProfile)
    }

    @discardableResult
    func importJSON(_ data: Data) throws -> Profile {
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        try decoded.validate()
        let added = decoded.copy(named: uniqueName(decoded.name))
        profiles = profiles + [added]
        activeProfileID = added.id
        return added
    }

    func uniqueName(_ wanted: String) -> String {
        let taken = Set(profiles.map(\.name))
        guard taken.contains(wanted) else { return wanted }
        var attempt = 2
        while taken.contains("\(wanted) \(attempt)") { attempt += 1 }
        return "\(wanted) \(attempt)"
    }
}
