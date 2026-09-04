import Foundation

enum Presets {
    private static func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "0000%04X-0000-4000-8000-000000000000", value))!
    }

    private static func base() -> Layer {
        Layer(id: id(0), name: "Base", outputMode: .layer)
    }

    static let navigation = Profile(
        id: id(0x10), name: "Navigation",
        layers: [
            base(),
            Layer(
                id: id(1),
                name: "Navigation",
                trigger: LayerTrigger(key: .capsLock),
                outputMode: .layer,
                tapAction: .sendKey(KeyBinding(key: "escape")),
                mappings: [
                    "h": .action(.sendKey(KeyBinding(key: "leftArrow"))),
                    "j": .action(.sendKey(KeyBinding(key: "downArrow"))),
                    "k": .action(.sendKey(KeyBinding(key: "upArrow"))),
                    "l": .action(.sendKey(KeyBinding(key: "rightArrow"))),
                ]
            ),
        ])

    static let vim = Profile(
        id: id(0x20), name: "Vim",
        layers: [
            base(),
            Layer(
                id: id(1),
                name: "Motion",
                trigger: LayerTrigger(key: .capsLock),
                outputMode: .layer,
                tapAction: .sendKey(KeyBinding(key: "escape")),
                mappings: [
                    "h": .action(.sendKey(KeyBinding(key: "leftArrow"))),
                    "j": .action(.sendKey(KeyBinding(key: "downArrow"))),
                    "k": .action(.sendKey(KeyBinding(key: "upArrow"))),
                    "l": .action(.sendKey(KeyBinding(key: "rightArrow"))),
                    "b": .action(.sendKey(KeyBinding(key: "leftArrow", modifiers: [.option]))),
                    "w": .action(.sendKey(KeyBinding(key: "rightArrow", modifiers: [.option]))),
                    "a": .action(.sendKey(KeyBinding(key: "leftArrow", modifiers: [.command]))),
                    "e": .action(.sendKey(KeyBinding(key: "rightArrow", modifiers: [.command]))),
                    "g": .action(.sendKey(KeyBinding(key: "upArrow", modifiers: [.command]))),
                    "n": .action(.sendKey(KeyBinding(key: "downArrow", modifiers: [.command]))),
                    "u": .action(.sendKey(KeyBinding(key: "pageUp"))),
                    "d": .action(.sendKey(KeyBinding(key: "pageDown"))),
                    "x": .action(.sendKey(KeyBinding(key: "forwardDelete"))),
                ]
            ),
        ])

    static let stacked = Profile(
        id: id(0x30), name: "Stacked",
        layers: [
            base(),
            Layer(
                id: id(1),
                name: "Move",
                trigger: LayerTrigger(key: .capsLock),
                outputMode: .layer,
                tapAction: .sendKey(KeyBinding(key: "escape")),
                mappings: [
                    "h": .action(.sendKey(KeyBinding(key: "leftArrow"))),
                    "j": .action(.sendKey(KeyBinding(key: "downArrow"))),
                    "k": .action(.sendKey(KeyBinding(key: "upArrow"))),
                    "l": .action(.sendKey(KeyBinding(key: "rightArrow"))),
                ]
            ),
            Layer(
                id: id(2),
                name: "Select",
                trigger: LayerTrigger(key: .capsLock, modifiers: [.leftShift]),
                outputMode: .layer,
                mappings: [
                    "h": .action(.sendKey(KeyBinding(key: "leftArrow", modifiers: [.shift]))),
                    "j": .action(.sendKey(KeyBinding(key: "downArrow", modifiers: [.shift]))),
                    "k": .action(.sendKey(KeyBinding(key: "upArrow", modifiers: [.shift]))),
                    "l": .action(.sendKey(KeyBinding(key: "rightArrow", modifiers: [.shift]))),
                    "w": .action(
                        .sendKey(KeyBinding(key: "rightArrow", modifiers: [.shift, .option]))),
                    "b": .action(
                        .sendKey(KeyBinding(key: "leftArrow", modifiers: [.shift, .option]))),
                ]
            ),
        ])

    static let hyperOnly = Profile(
        id: id(0x40), name: "Hyper Only",
        layers: [
            base(),
            Layer(
                id: id(1),
                name: "Hyper",
                trigger: LayerTrigger(key: .capsLock),
                outputMode: .injectAndLayer,
                tapAction: .sendKey(KeyBinding(key: "escape"))
            ),
        ])

    static let all: [Profile] = [navigation, vim, stacked, hyperOnly]

    static let library: [Profile] = all

    static let `default` = Profile(
        id: id(0xD),
        name: "Default",
        layers: navigation.layers
    )

    static func emptyBase() -> Layer {
        Layer(name: "Base", outputMode: .layer)
    }

    static func newLayer(index: Int) -> Layer {
        Layer(
            name: "Layer \(index)",
            trigger: LayerTrigger(key: .capsLock, modifiers: [.leftShift]),
            outputMode: .layer)
    }
}
