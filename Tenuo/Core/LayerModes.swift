import Foundation

enum LayerActivationMode: String, Codable, CaseIterable, Sendable {
    case hold
}

enum LayerOutputMode: String, Codable, CaseIterable, Hashable, Sendable {
    case inject
    case layer
    case injectAndLayer

    var displayName: String {
        switch self {
        case .inject: return "Send Hyper"
        case .layer: return "Remap keys"
        case .injectAndLayer: return "Remap keys + send Hyper"
        }
    }

    var summary: String {
        switch self {
        case .inject:
            return "Every held key sends Hyper (⌃⌥⌘⇧). Mappings are ignored."
        case .layer:
            return "Mapped keys send their assigned output. Everything else passes through."
        case .injectAndLayer:
            return "Mapped keys send their assigned output. Everything else sends Hyper (⌃⌥⌘⇧)."
        }
    }

    var appliesMappings: Bool { self != .inject }
    var injectsHyper: Bool { self != .layer }
}
