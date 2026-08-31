import Foundation

enum ModifierRequirement: String, Codable, CaseIterable, Hashable, Sendable {
    case shift, leftShift, rightShift
    case control, leftControl, rightControl
    case option, leftOption, rightOption
    case command, leftCommand, rightCommand
    case function

    var generalFlag: EventFlags {
        switch self {
        case .shift, .leftShift, .rightShift: return .shift
        case .control, .leftControl, .rightControl: return .control
        case .option, .leftOption, .rightOption: return .option
        case .command, .leftCommand, .rightCommand: return .command
        case .function: return .secondaryFn
        }
    }

    var sideFlag: EventFlags? {
        switch self {
        case .leftShift: return .deviceLeftShift
        case .rightShift: return .deviceRightShift
        case .leftControl: return .deviceLeftControl
        case .rightControl: return .deviceRightControl
        case .leftOption: return .deviceLeftOption
        case .rightOption: return .deviceRightOption
        case .leftCommand: return .deviceLeftCommand
        case .rightCommand: return .deviceRightCommand
        default: return nil
        }
    }

    @inline(__always)
    func isSatisfied(by flags: EventFlags) -> Bool {
        guard flags.contains(generalFlag) else { return false }
        guard let sideFlag else { return true }
        return flags.contains(sideFlag)
    }

    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .leftShift: return "⇧L"
        case .rightShift: return "⇧R"
        case .control: return "⌃"
        case .leftControl: return "⌃L"
        case .rightControl: return "⌃R"
        case .option: return "⌥"
        case .leftOption: return "⌥L"
        case .rightOption: return "⌥R"
        case .command: return "⌘"
        case .leftCommand: return "⌘L"
        case .rightCommand: return "⌘R"
        case .function: return "fn"
        }
    }

    var displayName: String {
        switch self {
        case .shift: return "Shift"
        case .leftShift: return "Left Shift"
        case .rightShift: return "Right Shift"
        case .control: return "Control"
        case .leftControl: return "Left Control"
        case .rightControl: return "Right Control"
        case .option: return "Option"
        case .leftOption: return "Left Option"
        case .rightOption: return "Right Option"
        case .command: return "Command"
        case .leftCommand: return "Left Command"
        case .rightCommand: return "Right Command"
        case .function: return "Fn"
        }
    }
}

struct LayerTrigger: Codable, Equatable, Hashable, Sendable {
    var key: TriggerKey
    var modifiers: [ModifierRequirement]

    init(key: TriggerKey = .capsLock, modifiers: [ModifierRequirement] = []) {
        self.key = key
        self.modifiers = modifiers
    }

    enum CodingKeys: String, CodingKey { case key, modifiers }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(TriggerKey.self, forKey: .key)
        modifiers =
            try container.decodeIfPresent(
                [ModifierRequirement].self,
                forKey: .modifiers) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        if !modifiers.isEmpty { try container.encode(modifiers, forKey: .modifiers) }
    }

    @inline(__always)
    func matches(flags: EventFlags) -> Bool {
        for modifier in modifiers where !modifier.isSatisfied(by: flags) { return false }
        return true
    }

    var specificity: Int { modifiers.count }

    var consumedFlags: EventFlags {
        var flags = key.flagToStripWhileHeld
        for modifier in modifiers { flags.formUnion(modifier.generalFlag) }
        return flags
    }

    var displayLabel: String {
        modifiers.map(\.symbol).joined() + key.shortSymbol
    }
}

enum KeyAction: Codable, Equatable, Hashable, Sendable {
    case key(KeyBinding)
    case transparent
    case blocked

    enum CodingKeys: String, CodingKey { case type, binding }

    init(from decoder: Decoder) throws {
        if let binding = try? KeyBinding(from: decoder) {
            self = .key(binding)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "transparent": self = .transparent
        case "blocked": self = .blocked
        default: self = .key(try container.decode(KeyBinding.self, forKey: .binding))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .key(binding):
            try binding.encode(to: encoder)
        case .transparent:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("transparent", forKey: .type)
        case .blocked:
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("blocked", forKey: .type)
        }
    }

    var binding: KeyBinding? {
        if case let .key(binding) = self { return binding }
        return nil
    }

    var displayLabel: String {
        switch self {
        case let .key(binding): return binding.displayLabel
        case .transparent: return "▽"
        case .blocked: return "✕"
        }
    }
}

struct Layer: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var trigger: LayerTrigger?
    var holdMode: HoldMode
    var tapAction: KeyBinding?
    var mappings: [String: KeyAction]

    init(
        id: UUID = UUID(),
        name: String,
        trigger: LayerTrigger? = nil,
        holdMode: HoldMode = .injectAndLayer,
        tapAction: KeyBinding? = nil,
        mappings: [String: KeyAction] = [:]
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.holdMode = holdMode
        self.tapAction = tapAction
        self.mappings = mappings
    }

    var isBase: Bool { trigger == nil }
}

struct Layout: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var layers: [Layer]
    var tapThresholdMilliseconds: Int

    init(
        id: UUID = UUID(),
        name: String,
        layers: [Layer],
        tapThresholdMilliseconds: Int = 200
    ) {
        self.id = id
        self.name = name
        self.layers = layers
        self.tapThresholdMilliseconds = tapThresholdMilliseconds
    }

    func copy(named newName: String) -> Layout {
        Layout(
            id: UUID(), name: newName, layers: layers,
            tapThresholdMilliseconds: tapThresholdMilliseconds)
    }

    static let maxTriggeredLayers = 6

    var baseLayer: Layer? { layers.first(where: \.isBase) }
    var triggeredLayers: [Layer] { layers.filter { !$0.isBase } }

    var canAddLayer: Bool { triggeredLayers.count < Self.maxTriggeredLayers }

    func conflicts() -> [(Layer, Layer)] {
        var found: [(Layer, Layer)] = []
        let triggered = triggeredLayers
        for (index, layer) in triggered.enumerated() {
            for other in triggered.dropFirst(index + 1)
            where layer.trigger == other.trigger {
                found.append((layer, other))
            }
        }
        return found
    }
}

enum ProfileError: LocalizedError, Equatable {
    case tooManyLayers(found: Int)

    var errorDescription: String? {
        switch self {
        case let .tooManyLayers(found):
            return """
                That profile holds \(found) layers, and a profile may have at \
                most \(Layout.maxTriggeredLayers).
                """
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .tooManyLayers:
            return "Split it into more than one profile, then import each."
        }
    }
}
