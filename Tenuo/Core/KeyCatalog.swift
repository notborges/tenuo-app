import Foundation

enum KeyCatalog {
    struct Key: Equatable, Hashable {
        let code: UInt16
        let name: String
        let label: String
        let group: Group

        var displayName: String {
            let spaced = name.replacingOccurrences(
                of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression
            ).capitalized
            return label == spaced ? spaced : "\(spaced)  \(label)"
        }
    }

    enum Group: String, CaseIterable {
        case letters = "Letters"
        case numbers = "Numbers"
        case navigation = "Navigation"
        case editing = "Editing"
        case function = "Function"
        case punctuation = "Punctuation"
        case modifiers = "Modifiers"
    }

    static let all: [Key] = [
        Key(code: 0, name: "a", label: "A", group: .letters),
        Key(code: 11, name: "b", label: "B", group: .letters),
        Key(code: 8, name: "c", label: "C", group: .letters),
        Key(code: 2, name: "d", label: "D", group: .letters),
        Key(code: 14, name: "e", label: "E", group: .letters),
        Key(code: 3, name: "f", label: "F", group: .letters),
        Key(code: 5, name: "g", label: "G", group: .letters),
        Key(code: 4, name: "h", label: "H", group: .letters),
        Key(code: 34, name: "i", label: "I", group: .letters),
        Key(code: 38, name: "j", label: "J", group: .letters),
        Key(code: 40, name: "k", label: "K", group: .letters),
        Key(code: 37, name: "l", label: "L", group: .letters),
        Key(code: 46, name: "m", label: "M", group: .letters),
        Key(code: 45, name: "n", label: "N", group: .letters),
        Key(code: 31, name: "o", label: "O", group: .letters),
        Key(code: 35, name: "p", label: "P", group: .letters),
        Key(code: 12, name: "q", label: "Q", group: .letters),
        Key(code: 15, name: "r", label: "R", group: .letters),
        Key(code: 1, name: "s", label: "S", group: .letters),
        Key(code: 17, name: "t", label: "T", group: .letters),
        Key(code: 32, name: "u", label: "U", group: .letters),
        Key(code: 9, name: "v", label: "V", group: .letters),
        Key(code: 13, name: "w", label: "W", group: .letters),
        Key(code: 7, name: "x", label: "X", group: .letters),
        Key(code: 16, name: "y", label: "Y", group: .letters),
        Key(code: 6, name: "z", label: "Z", group: .letters),

        Key(code: 29, name: "0", label: "0", group: .numbers),
        Key(code: 18, name: "1", label: "1", group: .numbers),
        Key(code: 19, name: "2", label: "2", group: .numbers),
        Key(code: 20, name: "3", label: "3", group: .numbers),
        Key(code: 21, name: "4", label: "4", group: .numbers),
        Key(code: 23, name: "5", label: "5", group: .numbers),
        Key(code: 22, name: "6", label: "6", group: .numbers),
        Key(code: 26, name: "7", label: "7", group: .numbers),
        Key(code: 28, name: "8", label: "8", group: .numbers),
        Key(code: 25, name: "9", label: "9", group: .numbers),

        Key(code: 123, name: "leftArrow", label: "←", group: .navigation),
        Key(code: 124, name: "rightArrow", label: "→", group: .navigation),
        Key(code: 125, name: "downArrow", label: "↓", group: .navigation),
        Key(code: 126, name: "upArrow", label: "↑", group: .navigation),
        Key(code: 115, name: "home", label: "↖", group: .navigation),
        Key(code: 119, name: "end", label: "↘", group: .navigation),
        Key(code: 116, name: "pageUp", label: "⇞", group: .navigation),
        Key(code: 121, name: "pageDown", label: "⇟", group: .navigation),

        Key(code: 53, name: "escape", label: "⎋", group: .editing),
        Key(code: 51, name: "delete", label: "⌫", group: .editing),
        Key(code: 117, name: "forwardDelete", label: "⌦", group: .editing),
        Key(code: 36, name: "return", label: "↩", group: .editing),
        Key(code: 76, name: "enter", label: "⌤", group: .editing),
        Key(code: 48, name: "tab", label: "⇥", group: .editing),
        Key(code: 49, name: "space", label: "␣", group: .editing),

        Key(code: 122, name: "f1", label: "F1", group: .function),
        Key(code: 120, name: "f2", label: "F2", group: .function),
        Key(code: 99, name: "f3", label: "F3", group: .function),
        Key(code: 118, name: "f4", label: "F4", group: .function),
        Key(code: 96, name: "f5", label: "F5", group: .function),
        Key(code: 97, name: "f6", label: "F6", group: .function),
        Key(code: 98, name: "f7", label: "F7", group: .function),
        Key(code: 100, name: "f8", label: "F8", group: .function),
        Key(code: 101, name: "f9", label: "F9", group: .function),
        Key(code: 109, name: "f10", label: "F10", group: .function),
        Key(code: 103, name: "f11", label: "F11", group: .function),
        Key(code: 111, name: "f12", label: "F12", group: .function),
        Key(code: 64, name: "f17", label: "F17", group: .function),
        Key(code: 79, name: "f18", label: "F18", group: .function),
        Key(code: 80, name: "f19", label: "F19", group: .function),

        Key(code: 27, name: "minus", label: "-", group: .punctuation),
        Key(code: 24, name: "equal", label: "=", group: .punctuation),
        Key(code: 33, name: "leftBracket", label: "[", group: .punctuation),
        Key(code: 30, name: "rightBracket", label: "]", group: .punctuation),
        Key(code: 41, name: "semicolon", label: ";", group: .punctuation),
        Key(code: 39, name: "quote", label: "'", group: .punctuation),
        Key(code: 43, name: "comma", label: ",", group: .punctuation),
        Key(code: 47, name: "period", label: ".", group: .punctuation),
        Key(code: 44, name: "slash", label: "/", group: .punctuation),
        Key(code: 42, name: "backslash", label: "\\", group: .punctuation),
        Key(code: 50, name: "grave", label: "`", group: .punctuation),
    ]

    private static let byName: [String: Key] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.name.lowercased(), $0) }
    )

    private static let byCode: [UInt16: Key] = Dictionary(
        all.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first }
    )

    static func key(named name: String) -> Key? { byName[name.lowercased()] }

    static func key(code: UInt16) -> Key? { byCode[code] }

    static func name(for code: UInt16) -> String? { byCode[code]?.name }

    static func code(for name: String) -> UInt16? { byName[name.lowercased()]?.code }

    static func label(for code: UInt16) -> String {
        byCode[code]?.label ?? "Key \(code)"
    }

    static func keys(in group: Group) -> [Key] {
        all.filter { $0.group == group }
    }
}
