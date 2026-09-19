import CoreGraphics
import Foundation

enum KeyboardGeometry {

    enum LegendPosition { case center, leading, trailing }

    struct Key {
        var name: String?
        var label: String
        var symbol: String?
        var glyph: String?
        var word: String?
        var shifted: String?
        var width: CGFloat = 1
        var legend: LegendPosition = .center
        var hasIndicator: Bool = false
        var trigger: TriggerKey?

        var isMappable: Bool { name != nil }
    }

    enum Element: Identifiable {
        case key(Key)
        case arrows
        case returnKey
        case space(CGFloat)

        var id: String {
            switch self {
            case .arrows: return "arrows"
            case .returnKey: return "return"
            case .space: return "spacer"
            case .key(let key): return key.name ?? "fixed-\(key.label)-\(key.word ?? "")"
            }
        }

        var width: CGFloat {
            switch self {
            case .arrows: return 3
            case .returnKey: return 1
            case .space(let width): return width
            case .key(let key): return key.width
            }
        }
    }

    private static func cap(
        _ name: String,
        _ width: CGFloat = 1,
        label: String? = nil,
        symbol: String? = nil,
        glyph: String? = nil,
        word: String? = nil,
        shifted: String? = nil,
        legend: LegendPosition = .center
    ) -> Element {
        .key(
            Key(
                name: name,
                label: label ?? KeyCatalog.key(named: name)?.label ?? name,
                symbol: symbol,
                glyph: glyph,
                word: word,
                shifted: shifted,
                width: width,
                legend: legend))
    }

    private static func fixed(
        _ label: String,
        _ width: CGFloat = 1,
        symbol: String? = nil,
        word: String? = nil,
        legend: LegendPosition = .center,
        hasIndicator: Bool = false,
        trigger: TriggerKey? = nil
    ) -> Element {
        .key(
            Key(
                name: nil,
                label: label,
                symbol: symbol,
                word: word,
                width: width,
                legend: legend,
                hasIndicator: hasIndicator,
                trigger: trigger))
    }

    private static func letters(_ names: String...) -> [Element] {
        names.map { cap($0) }
    }

    private static func pair(_ name: String, _ shifted: String) -> Element {
        cap(name, shifted: shifted)
    }

    private static let functionSymbols = [
        "sun.min", "sun.max", "rectangle.3.group", "magnifyingglass",
        "mic", "moon", "backward.end.fill", "playpause.fill",
        "forward.end.fill", "speaker.slash.fill",
        "speaker.wave.1.fill", "speaker.wave.3.fill",
    ]

    static let rows: [[Element]] = [
        [cap("escape", 1.5, label: "esc", legend: .leading)]
            + (1...12).map { cap("f\($0)", glyph: functionSymbols[$0 - 1]) }
            + [fixed("", symbol: "touchid")],

        [
            pair("grave", "~"), pair("1", "!"), pair("2", "@"), pair("3", "#"),
            pair("4", "$"), pair("5", "%"), pair("6", "^"), pair("7", "&"),
            pair("8", "*"), pair("9", "("), pair("0", ")"), pair("minus", "_"),
            pair("equal", "+"),
        ]
            + [cap("delete", 1.5, word: "delete", legend: .trailing)],

        [cap("tab", 1.5, word: "tab", legend: .leading)]
            + letters("q", "w", "e", "r", "t", "y", "u", "i", "o", "p")
            + [
                pair("leftBracket", "{"), pair("rightBracket", "}"),
                pair("backslash", "|"),
            ],

        [
            fixed(
                "⇪", 1.75, word: "caps lock", legend: .leading,
                hasIndicator: true, trigger: .capsLock)
        ]
            + letters("a", "s", "d", "f", "g", "h", "j", "k", "l")
            + [pair("semicolon", ":"), pair("quote", "\"")]
            + [cap("return", 1.75, word: "return", legend: .trailing)],

        [fixed("⇧", 2.25, word: "shift", legend: .leading, trigger: .leftShift)]
            + letters("z", "x", "c", "v", "b", "n", "m")
            + [pair("comma", "<"), pair("period", ">"), pair("slash", "?")]
            + [fixed("⇧", 2.25, word: "shift", legend: .trailing, trigger: .rightShift)],

        [
            fixed("", symbol: "globe", word: "fn", legend: .leading, trigger: .function),
            fixed("⌃", word: "control", legend: .leading, trigger: .leftControl),
            fixed("⌥", word: "option", legend: .leading, trigger: .leftOption),
            fixed("⌘", 1.25, word: "command", legend: .leading, trigger: .leftCommand),
            cap("space", 5, label: ""),
            fixed("⌘", 1.25, word: "command", legend: .trailing, trigger: .rightCommand),
            fixed("⌥", word: "option", legend: .trailing, trigger: .rightOption),
            .arrows,
        ],
    ]

    @MainActor
    static func rows(for shape: KeyboardPresentation.Shape) -> [[Element]] {
        guard shape != .ansi else { return rows }
        var result = rows
        result[2] =
            [cap("tab", 1.5, word: "tab", legend: .leading)]
            + letters("q", "w", "e", "r", "t", "y", "u", "i", "o", "p")
            + [pair("leftBracket", "{"), pair("rightBracket", "}"), .returnKey]
        result[3] =
            [
                fixed(
                    "⇪", 1.75, word: "caps lock", legend: .leading,
                    hasIndicator: true, trigger: .capsLock)
            ]
            + letters("a", "s", "d", "f", "g", "h", "j", "k", "l")
            + [pair("semicolon", ":"), pair("quote", "\""), pair("backslash", "|"), .space(0.75)]
        if shape == .iso {
            // macOS reports ISO's upper-left key as Section, and the key beside Shift as Grave.
            result[1][0] = cap("isoSection")
            result[4] =
                [
                    fixed("⇧", 1.25, word: "shift", legend: .leading, trigger: .leftShift),
                    cap("grave"),
                ]
                + letters("z", "x", "c", "v", "b", "n", "m")
                + [pair("comma", "<"), pair("period", ">"), pair("slash", "?")]
                + [fixed("⇧", 2.25, word: "shift", legend: .trailing, trigger: .rightShift)]
        } else {
            result[1] =
                Array(rows[1].dropFirst().dropLast())
                + [cap("jisYen"), cap("delete", 1.5, word: "delete", legend: .trailing)]
            result[4] =
                [fixed("⇧", 1.75, word: "shift", legend: .leading, trigger: .leftShift)]
                + letters("z", "x", "c", "v", "b", "n", "m")
                + [
                    pair("comma", "<"), pair("period", ">"), pair("slash", "?"),
                    cap("jisUnderscore"),
                ]
                + [fixed("⇧", 1.75, word: "shift", legend: .trailing, trigger: .rightShift)]
            result[5] =
                Array(rows[5].prefix(4))
                + [cap("jisEisu"), cap("space", 3, label: ""), cap("jisKana")]
                + Array(rows[5].suffix(3))
        }
        return result
    }

    @MainActor
    static func visibleKeys(for shape: KeyboardPresentation.Shape) -> Set<String> {
        var names = Set(
            rows(for: shape).flatMap { $0 }.compactMap { element -> String? in
                if case let .key(key) = element { return key.name }
                if case .returnKey = element { return "return" }
                return nil
            })
        names.formUnion(["leftArrow", "rightArrow", "upArrow", "downArrow"])
        return names
    }

    static var shiftedKeyCount: Int {
        rows.flatMap { $0 }.reduce(0) { total, element in
            guard case let .key(key) = element, key.shifted != nil else { return total }
            return total + 1
        }
    }

    static let gapRatio: CGFloat = 0.083
    static let bezelRatio: CGFloat = 0.34

    static var rowUnits: CGFloat {
        rows.map { $0.reduce(0) { $0 + $1.width } }.max() ?? 14.5
    }

    static var widthInUnits: CGFloat {
        rowUnits + gapRatio * (rowUnits - 1) + bezelRatio * 2
    }

    static var heightInUnits: CGFloat {
        CGFloat(rows.count) + gapRatio * CGFloat(rows.count - 1) + bezelRatio * 2
    }

    static var aspectRatio: CGFloat { widthInUnits / heightInUnits }

    static let maxWidth: CGFloat = 760
}
