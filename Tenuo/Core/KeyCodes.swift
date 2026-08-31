import Foundation

enum KeyCode {
    static let a: UInt16 = 0
    static let s: UInt16 = 1
    static let b: UInt16 = 11
    static let d: UInt16 = 2
    static let h: UInt16 = 4
    static let j: UInt16 = 38
    static let k: UInt16 = 40
    static let l: UInt16 = 37
    static let t: UInt16 = 17
    static let w: UInt16 = 13

    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126

    static let escape: UInt16 = 53
    static let `return`: UInt16 = 36
    static let forwardDelete: UInt16 = 117
    static let home: UInt16 = 115
    static let end: UInt16 = 119
    static let pageUp: UInt16 = 116
    static let pageDown: UInt16 = 121

    static let capsLock: UInt16 = 57
    static let f18: UInt16 = 79

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
