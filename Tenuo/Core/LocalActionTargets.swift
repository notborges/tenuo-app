import Foundation

struct LocalActionTarget: Codable, Equatable, Sendable {
    var name: String
    var bookmark: Data?
    var shortcutID: String?
}

extension Profile {
    func transformingMacActions(_ transform: (MacAction) -> MacAction) -> Profile {
        func action(_ value: Action) -> Action {
            if case let .macAction(target) = value { return .macAction(transform(target)) }
            return value
        }
        func mapping(_ value: LayerMapping) -> LayerMapping {
            if case let .action(value) = value { return .action(action(value)) }
            return value
        }
        var copy = self
        copy.layers = layers.map { layer in
            var layer = layer
            layer.tapAction = layer.tapAction.map(action)
            layer.mappings = layer.mappings.mapValues(mapping)
            layer.applications = layer.applications.mapValues {
                ApplicationOverride(name: $0.name, mappings: $0.mappings.mapValues(mapping))
            }
            return layer
        }
        return copy
    }
}

extension ProfileSyncState {
    mutating func portable(_ profile: Profile) -> Profile {
        let existing = snapshot.profiles.first { $0.id == profile.id }
        var canonicalShortcuts: [UUID: NamedActionTarget] = [:]
        _ = existing?.transformingMacActions { action in
            if case let .shortcut(target) = action, let id = target.localID {
                canonicalShortcuts[id] = target
            }
            return action
        }
        return profile.transformingMacActions { action in
            switch action {
            case var .file(target):
                let id = target.localID ?? UUID()
                target.localID = id
                let key = "\(profile.id)/\(id)"
                if !target.bookmark.isEmpty {
                    targets[key] = LocalActionTarget(name: target.name, bookmark: target.bookmark)
                }
                target.bookmark = Data()
                if let original = existing?.fileTarget(id: id) { target.name = original.name }
                return .file(target)
            case var .shortcut(target):
                let id = target.localID ?? UUID()
                target.localID = id
                targets["\(profile.id)/\(id)"] = LocalActionTarget(
                    name: target.name, shortcutID: target.id)
                return .shortcut(canonicalShortcuts[id] ?? target)
            default: return action
            }
        }
    }

    func resolved(_ profile: Profile) -> Profile {
        profile.transformingMacActions { action in
            switch action {
            case var .file(target):
                if let id = target.localID, let local = targets["\(profile.id)/\(id)"] {
                    target.bookmark = local.bookmark ?? Data()
                    target.name = local.name
                }
                return .file(target)
            case var .shortcut(target):
                if let id = target.localID, let local = targets["\(profile.id)/\(id)"],
                    let shortcutID = local.shortcutID
                {
                    target.id = shortcutID
                    target.name = local.name
                }
                return .shortcut(target)
            default: return action
            }
        }
    }
}

private extension Profile {
    func fileTarget(id: UUID) -> FileActionTarget? {
        var found: FileActionTarget?
        _ = transformingMacActions { action in
            if case let .file(target) = action, target.localID == id { found = target }
            return action
        }
        return found
    }
}
