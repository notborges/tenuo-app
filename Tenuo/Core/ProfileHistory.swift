import Foundation

struct ProfileHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let profile: Profile
    let savedAt: Date

    init(id: UUID = UUID(), profile: Profile, savedAt: Date) {
        self.id = id
        self.profile = profile
        self.savedAt = savedAt
    }

    private enum CodingKeys: String, CodingKey { case id, profile, savedAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let profile = try container.decode(Profile.self, forKey: .profile)
        try profile.validate()
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            profile: profile,
            savedAt: try container.decode(Date.self, forKey: .savedAt))
    }
}

enum ProfileHistoryError: Error, Equatable {
    case unreadable
}

/// A directional comparison: `before` is the current profile and `after` is the restore target.
struct ProfileHistoryChange: Identifiable, Equatable {
    let id: String
    let layerID: UUID?
    let layerName: String?
    let key: String?
    let title: String
    let before: String
    let after: String
}

enum ProfileHistoryComparison {
    static func changes(from before: Profile, to after: Profile) -> [ProfileHistoryChange] {
        var result: [ProfileHistoryChange] = []
        func append(
            _ field: String, _ title: String, _ old: String, _ new: String,
            layer: Layer? = nil, key: String? = nil
        ) {
            result.append(
                ProfileHistoryChange(
                    id: "\(layer?.id.uuidString ?? "profile")/\(field)",
                    layerID: layer?.id, layerName: layer?.name, key: key,
                    title: title, before: old, after: new))
        }
        if before.name != after.name {
            append("name", "Profile name", before.name, after.name)
        }
        if before.tapThresholdMilliseconds != after.tapThresholdMilliseconds {
            append(
                "timing", "Tap window", "\(before.tapThresholdMilliseconds) ms",
                "\(after.tapThresholdMilliseconds) ms")
        }
        let oldIDs = Set(before.layers.map(\.id))
        let newIDs = Set(after.layers.map(\.id))
        let commonIDs = oldIDs.intersection(newIDs)
        if before.layers.filter({ commonIDs.contains($0.id) }).map(\.id)
            != after.layers.filter({ commonIDs.contains($0.id) }).map(\.id)
        {
            append(
                "order", "Layer priority", before.layers.map(\.name).joined(separator: " → "),
                after.layers.map(\.name).joined(separator: " → "))
        }
        let layers = after.layers + before.layers.filter { !newIDs.contains($0.id) }
        for layer in layers {
            let old = before.layers.first { $0.id == layer.id }
            let new = after.layers.first { $0.id == layer.id }
            if old == nil || new == nil {
                append(
                    "existence", old == nil ? "Add layer" : "Remove layer",
                    old?.name ?? "Not present", new?.name ?? "Not present", layer: layer)
            } else if let old, let new {
                if old.name != new.name {
                    append("name", "Layer name", old.name, new.name, layer: new)
                }
                if old.trigger != new.trigger {
                    append(
                        "trigger", "Trigger", old.trigger?.displayLabel ?? "Base",
                        new.trigger?.displayLabel ?? "Base", layer: new)
                }
                if old.outputMode != new.outputMode {
                    append(
                        "output", "Unmapped keys", old.outputMode.displayName,
                        new.outputMode.displayName, layer: new)
                }
                if old.tapAction != new.tapAction {
                    append(
                        "tap", "Tap action", actionLabel(old.tapAction, in: before),
                        actionLabel(new.tapAction, in: after), layer: new)
                }
            }
            let keys = Set(old?.mappings.keys.map { $0 } ?? [])
                .union(new?.mappings.keys.map { $0 } ?? [])
            for key in keys.sorted() where old?.mappings[key] != new?.mappings[key] {
                append(
                    "key/\(key)", KeyCatalog.key(named: key)?.displayName ?? key,
                    mappingLabel(old?.mappings[key], in: before),
                    mappingLabel(new?.mappings[key], in: after), layer: layer, key: key)
            }
        }
        return result
    }

    static func mappingLabel(_ mapping: LayerMapping?, in profile: Profile) -> String {
        switch mapping {
        case .none: return "No direct mapping"
        case .transparent: return "Pass through"
        case .blocked: return "Block key"
        case .action(let action): return actionLabel(action, in: profile)
        }
    }

    static func actionLabel(_ action: Action?, in profile: Profile) -> String {
        guard let action else { return "None" }
        guard let target = action.target else { return action.displayLabel }
        let name: String
        switch target {
        case .current: name = "this layer"
        case .layer(let id): name = profile.layers.first { $0.id == id }?.name ?? "Missing layer"
        }
        return "\(action.displayLabel) · \(name)"
    }
}

protocol ProfileHistoryStore: AnyObject {
    func entries(for profileID: UUID) -> Result<[ProfileHistoryEntry], ProfileHistoryError>
    func record(_ profile: Profile, force: Bool) -> Bool
    func removeAll(for profileID: UUID) -> Bool
}

final class UserDefaultsProfileHistoryStore: ProfileHistoryStore {
    private enum Key {
        static let entries = "TenuoProfileHistory"
    }

    private static let maxEntriesPerProfile = 20
    private static let coalescingWindow: TimeInterval = 1

    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    func entries(for profileID: UUID) -> Result<[ProfileHistoryEntry], ProfileHistoryError> {
        load().map { entries in
            entries
                .filter { $0.profile.id == profileID }
                .sorted { $0.savedAt > $1.savedAt }
        }
    }

    func record(_ profile: Profile, force: Bool = false) -> Bool {
        guard (try? profile.validate()) != nil,
            case .success(var entries) = load()
        else { return false }

        let savedAt = now()
        let latest =
            entries
            .filter { $0.profile.id == profile.id }
            .max { $0.savedAt < $1.savedAt }
        if let latest {
            if latest.profile == profile { return true }
            if !force,
                savedAt.timeIntervalSince(latest.savedAt) >= 0,
                savedAt.timeIntervalSince(latest.savedAt) < Self.coalescingWindow
            {
                return true
            }
        }

        entries.append(ProfileHistoryEntry(profile: profile, savedAt: savedAt))
        return save(trimmed(entries))
    }

    func removeAll(for profileID: UUID) -> Bool {
        guard case .success(let entries) = load() else { return false }
        let remaining = entries.filter { $0.profile.id != profileID }
        guard remaining.count != entries.count else { return true }
        return save(remaining)
    }

    private func load() -> Result<[ProfileHistoryEntry], ProfileHistoryError> {
        guard let stored = defaults.object(forKey: Key.entries) else { return .success([]) }
        guard let data = stored as? Data,
            let entries = try? JSONDecoder().decode([ProfileHistoryEntry].self, from: data)
        else { return .failure(.unreadable) }
        return .success(entries)
    }

    private func save(_ entries: [ProfileHistoryEntry]) -> Bool {
        guard let data = try? ProfileDocument.encoder.encode(entries) else { return false }
        defaults.set(data, forKey: Key.entries)
        return defaults.data(forKey: Key.entries) == data
    }

    private func trimmed(_ entries: [ProfileHistoryEntry]) -> [ProfileHistoryEntry] {
        var counts: [UUID: Int] = [:]
        return entries.sorted { $0.savedAt > $1.savedAt }.filter { entry in
            let count = counts[entry.profile.id, default: 0]
            guard count < Self.maxEntriesPerProfile else { return false }
            counts[entry.profile.id] = count + 1
            return true
        }
    }
}
