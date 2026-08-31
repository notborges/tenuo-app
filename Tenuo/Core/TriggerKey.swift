import Foundation

enum TriggerKey: Hashable, Codable, Sendable {
    case capsLock
    case leftCommand, rightCommand
    case leftOption, rightOption
    case leftControl, rightControl
    case leftShift, rightShift
    case function
    case key(String)

    static let `default`: TriggerKey = .capsLock

    static let suggested: [TriggerKey] = [.capsLock, .function]
    static let rightModifiers: [TriggerKey] = [
        .rightCommand, .rightOption, .rightControl, .rightShift,
    ]
    static let leftModifiers: [TriggerKey] = [
        .leftCommand, .leftOption, .leftControl, .leftShift,
    ]

    private static let names: [TriggerKey: String] = [
        .capsLock: "capsLock", .function: "function",
        .leftCommand: "leftCommand", .rightCommand: "rightCommand",
        .leftOption: "leftOption", .rightOption: "rightOption",
        .leftControl: "leftControl", .rightControl: "rightControl",
        .leftShift: "leftShift", .rightShift: "rightShift",
    ]
    private static let byName: [String: TriggerKey] = Dictionary(
        uniqueKeysWithValues: names.map { ($0.value.lowercased(), $0.key) }
    )

    var rawValue: String {
        if case let .key(name) = self { return name }
        return Self.names[self] ?? "capsLock"
    }

    init(rawValue: String) {
        self = Self.byName[rawValue.lowercased()] ?? .key(rawValue)
    }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var shortSymbol: String {
        switch self {
        case .capsLock: return "⇪"
        case .leftCommand: return "⌘L"
        case .rightCommand: return "⌘R"
        case .leftOption: return "⌥L"
        case .rightOption: return "⌥R"
        case .leftControl: return "⌃L"
        case .rightControl: return "⌃R"
        case .leftShift: return "⇧L"
        case .rightShift: return "⇧R"
        case .function: return "fn"
        case .key(let name):
            return KeyCatalog.key(named: name)?.label ?? name
        }
    }

    var displayName: String {
        switch self {
        case .capsLock: return "Caps Lock"
        case .leftCommand: return "Left Command"
        case .rightCommand: return "Right Command"
        case .leftOption: return "Left Option"
        case .rightOption: return "Right Option"
        case .leftControl: return "Left Control"
        case .rightControl: return "Right Control"
        case .leftShift: return "Left Shift"
        case .rightShift: return "Right Shift"
        case .function: return "Fn"
        case .key(let name):
            return KeyCatalog.key(named: name)?.displayName ?? name
        }
    }

    var isModifier: Bool { modifierFlag != nil }

    var requiresCapsLockRemap: Bool { self == .capsLock }

    var isConsumedWhileHeld: Bool { !isModifier }

    var observedKeyCode: UInt16? {
        switch self {
        case .capsLock: return KeyCode.f18
        case .leftCommand: return KeyCode.leftCommand
        case .rightCommand: return KeyCode.rightCommand
        case .leftOption: return KeyCode.leftOption
        case .rightOption: return KeyCode.rightOption
        case .leftControl: return KeyCode.leftControl
        case .rightControl: return KeyCode.rightControl
        case .leftShift: return KeyCode.leftShift
        case .rightShift: return KeyCode.rightShift
        case .function: return KeyCode.function
        case .key(let name): return KeyCatalog.code(for: name)
        }
    }

    var modifierFlag: EventFlags? {
        switch self {
        case .leftCommand, .rightCommand: return .command
        case .leftOption, .rightOption: return .option
        case .leftControl, .rightControl: return .control
        case .leftShift, .rightShift: return .shift
        case .function: return .secondaryFn
        case .capsLock, .key: return nil
        }
    }

    var flagToStripWhileHeld: EventFlags {
        modifierFlag ?? []
    }
}
