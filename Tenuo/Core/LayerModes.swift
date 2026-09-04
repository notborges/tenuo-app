import Foundation

enum LayerOutputMode: String, Codable, CaseIterable, Hashable, Sendable {
    case inject
    case layer
    case injectAndLayer

    var displayName: String {
        switch self {
        case .inject, .injectAndLayer: return "Hyper shortcuts"
        case .layer: return "Normal keys"
        }
    }

    var summary: String {
        switch self {
        case .layer:
            return
                "If no active layer maps the key, use it normally. Another active layer can still turn it into a Hyper shortcut."
        case .inject, .injectAndLayer:
            return
                "If no active layer maps the key, send it with Control, Option, Command and Shift held together."
        }
    }

    var injectsHyper: Bool { self != .layer }
}
