import Foundation

enum KeyCode {
    private static func catalogCode(_ name: String) -> UInt16 {
        guard let code = KeyCatalog.code(for: name) else {
            preconditionFailure("Missing key catalog entry: \(name)")
        }
        return code
    }

    static let a = catalogCode("a")
    static let s = catalogCode("s")
    static let b = catalogCode("b")
    static let d = catalogCode("d")
    static let h = catalogCode("h")
    static let j = catalogCode("j")
    static let k = catalogCode("k")
    static let l = catalogCode("l")
    static let t = catalogCode("t")
    static let w = catalogCode("w")

    static let leftArrow = catalogCode("leftArrow")
    static let rightArrow = catalogCode("rightArrow")
    static let downArrow = catalogCode("downArrow")
    static let upArrow = catalogCode("upArrow")

    static let escape = catalogCode("escape")
    static let `return` = catalogCode("return")
    static let forwardDelete = catalogCode("forwardDelete")
    static let home = catalogCode("home")
    static let end = catalogCode("end")
    static let pageUp = catalogCode("pageUp")
    static let pageDown = catalogCode("pageDown")

    static let capsLock: UInt16 = 57
    static let f18 = catalogCode("f18")

    // These are physical trigger codes, not selectable mapping keys.
    static let leftShift: UInt16 = 56
    static let rightShift: UInt16 = 60
    static let leftControl: UInt16 = 59
    static let rightControl: UInt16 = 62
    static let leftOption: UInt16 = 58
    static let rightOption: UInt16 = 61
    static let leftCommand: UInt16 = 55
    static let rightCommand: UInt16 = 54
    static let function: UInt16 = 63
}

struct EventFlags: OptionSet, Hashable {
    let rawValue: UInt64

    static let alphaShift = EventFlags(rawValue: 0x0001_0000)
    static let shift = EventFlags(rawValue: 0x0002_0000)
    static let control = EventFlags(rawValue: 0x0004_0000)
    static let option = EventFlags(rawValue: 0x0008_0000)
    static let command = EventFlags(rawValue: 0x0010_0000)
    static let numericPad = EventFlags(rawValue: 0x0020_0000)
    static let help = EventFlags(rawValue: 0x0040_0000)
    static let secondaryFn = EventFlags(rawValue: 0x0080_0000)

    static let deviceLeftControl = EventFlags(rawValue: 0x0000_0001)
    static let deviceLeftShift = EventFlags(rawValue: 0x0000_0002)
    static let deviceRightShift = EventFlags(rawValue: 0x0000_0004)
    static let deviceLeftCommand = EventFlags(rawValue: 0x0000_0008)
    static let deviceRightCommand = EventFlags(rawValue: 0x0000_0010)
    static let deviceLeftOption = EventFlags(rawValue: 0x0000_0020)
    static let deviceRightOption = EventFlags(rawValue: 0x0000_0040)
    static let deviceRightControl = EventFlags(rawValue: 0x0000_2000)

    static let allDeviceBits: EventFlags = [
        .deviceLeftControl, .deviceLeftShift, .deviceRightShift,
        .deviceLeftCommand, .deviceRightCommand, .deviceLeftOption,
        .deviceRightOption, .deviceRightControl,
    ]

    static let arrowIntrinsic: EventFlags = [.numericPad, .secondaryFn]

}
