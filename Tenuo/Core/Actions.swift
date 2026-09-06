import Foundation

enum ActionKind: String, Codable, CaseIterable, Hashable, Sendable {
    case sendKey
    case toggleLayer
    case oneShotLayer

    var displayName: String {
        switch self {
        case .sendKey: return "Send key or shortcut"
        case .toggleLayer: return "Toggle layer"
        case .oneShotLayer: return "One-shot layer"
        }
    }

    var requiresPro: Bool {
        switch self {
        case .sendKey: return false
        case .toggleLayer, .oneShotLayer: return false
        }
    }
}

enum LayerTarget: Codable, Equatable, Hashable, Sendable {
    case current
    case layer(UUID)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if value == "current" {
            self = .current
        } else if let id = UUID(uuidString: value) {
            self = .layer(id)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid layer target: \(value)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .current:
            try container.encode("current")
        case let .layer(id):
            try container.encode(id.uuidString)
        }
    }
}

enum Action: Codable, Equatable, Hashable, Sendable {
    case sendKey(KeyBinding)
    case toggleLayer(LayerTarget)
    case oneShotLayer(LayerTarget)

    var kind: ActionKind {
        switch self {
        case .sendKey: return .sendKey
        case .toggleLayer: return .toggleLayer
        case .oneShotLayer: return .oneShotLayer
        }
    }

    var binding: KeyBinding? {
        guard case let .sendKey(binding) = self else { return nil }
        return binding
    }

    var target: LayerTarget? {
        switch self {
        case .sendKey: return nil
        case let .toggleLayer(target), let .oneShotLayer(target): return target
        }
    }

    var displayLabel: String {
        switch self {
        case let .sendKey(binding): return binding.displayLabel
        case .toggleLayer: return "Toggle layer"
        case .oneShotLayer: return "One-shot layer"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, binding, target
    }

    init(from decoder: Decoder) throws {
        if let binding = try? KeyBinding(from: decoder) {
            self = .sendKey(binding)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "sendKey":
            self = .sendKey(try container.decode(KeyBinding.self, forKey: .binding))
        case "toggleLayer":
            self = .toggleLayer(
                try container.decodeIfPresent(LayerTarget.self, forKey: .target) ?? .current)
        case "oneShotLayer":
            self = .oneShotLayer(
                try container.decodeIfPresent(LayerTarget.self, forKey: .target) ?? .current)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown action type")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .sendKey(binding):
            try binding.encode(to: encoder)
        case let .toggleLayer(target):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("toggleLayer", forKey: .type)
            try container.encode(target, forKey: .target)
        case let .oneShotLayer(target):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("oneShotLayer", forKey: .type)
            try container.encode(target, forKey: .target)
        }
    }

    func remappingLayerIDs(_ ids: [UUID: UUID]) -> Action {
        switch self {
        case .sendKey:
            return self
        case let .toggleLayer(target):
            return .toggleLayer(target.remappingLayerIDs(ids))
        case let .oneShotLayer(target):
            return .oneShotLayer(target.remappingLayerIDs(ids))
        }
    }
}

extension LayerTarget {
    func remappingLayerIDs(_ ids: [UUID: UUID]) -> LayerTarget {
        guard case let .layer(id) = self else { return self }
        return .layer(ids[id] ?? id)
    }
}

enum LayerMapping: Codable, Equatable, Hashable, Sendable {
    case action(Action)
    case transparent
    case blocked

    private enum CodingKeys: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        if let binding = try? KeyBinding(from: decoder) {
            self = .action(.sendKey(binding))
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "transparent": self = .transparent
        case "blocked": self = .blocked
        default: self = .action(try Action(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .action(action):
            try action.encode(to: encoder)
        case .transparent:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("transparent", forKey: .type)
        case .blocked:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("blocked", forKey: .type)
        }
    }

    var action: Action? {
        guard case let .action(action) = self else { return nil }
        return action
    }

    var binding: KeyBinding? { action?.binding }

    var displayLabel: String {
        switch self {
        case let .action(action): return action.displayLabel
        case .transparent: return "▽"
        case .blocked: return "✕"
        }
    }

    func remappingLayerIDs(_ ids: [UUID: UUID]) -> LayerMapping {
        guard case let .action(action) = self else { return self }
        return .action(action.remappingLayerIDs(ids))
    }
}

protocol ActionAvailability: Sendable {
    func canUse(_ kind: ActionKind) -> Bool
}

struct AllActionsAvailability: ActionAvailability {
    func canUse(_: ActionKind) -> Bool { true }
}

struct FreeActionsAvailability: ActionAvailability {
    func canUse(_ kind: ActionKind) -> Bool { !kind.requiresPro }
}

enum DefaultActionAvailability {
    static var current: any ActionAvailability {
        FreeActionsAvailability()
    }
}
