import Foundation

final class AppPreferences {
    private enum Key {
        static let isEnabled = "TenuoEnabled"
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
}
