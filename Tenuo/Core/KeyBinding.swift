import Foundation

enum Modifier: String, Codable, CaseIterable, Sendable {
    case command, option, control, shift, function

    var flag: EventFlags {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        case .shift: return .shift
        case .function: return .secondaryFn
        }
    }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        case .function: return "fn"
        }
    }

    static let hyper: [Modifier] = [.control, .option, .command, .shift]

    static var hyperFlags: EventFlags {
        hyper.reduce(into: EventFlags()) { $0.formUnion($1.flag) }
    }

    static func flags(from modifiers: [Modifier]) -> EventFlags {
        modifiers.reduce(into: EventFlags()) { $0.formUnion($1.flag) }
    }
}

struct KeyBinding: Codable, Equatable, Hashable, Sendable {
    var key: String
    var modifiers: [Modifier]

    init(key: String, modifiers: [Modifier] = []) {
        self.key = key
        self.modifiers = modifiers
    }

    enum CodingKeys: String, CodingKey {
        case key, modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        modifiers = try container.decodeIfPresent([Modifier].self, forKey: .modifiers) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        if !modifiers.isEmpty {
            try container.encode(modifiers, forKey: .modifiers)
        }
    }

    var keyCode: UInt16? { KeyCatalog.code(for: key) }
    var flags: EventFlags { Modifier.flags(from: modifiers) }

    var displayLabel: String {
        let symbols = Modifier.allCases
            .filter { modifiers.contains($0) }
            .map(\.symbol)
            .joined()
        guard let code = keyCode else { return symbols + key }
        return symbols + KeyCatalog.label(for: code)
    }
}

enum HoldMode: String, Codable, CaseIterable, Sendable {
    case inject
    case layer
    case injectAndLayer

    var displayName: String {
        switch self {
        case .inject: return "Hyper only"
        case .layer: return "Remap only"
        case .injectAndLayer: return "Remap + Hyper"
        }
    }

    var summary: String {
        switch self {
        case .inject:
            return "Held keys send ⌃⌥⌘⇧. Your mappings are ignored."
        case .layer:
            return "Mapped keys are remapped. Everything else is untouched."
        case .injectAndLayer:
            return "Mapped keys are remapped. Everything else sends ⌃⌥⌘⇧."
        }
    }

    var appliesMappings: Bool { self != .inject }
    var injectsHyper: Bool { self != .layer }
}
