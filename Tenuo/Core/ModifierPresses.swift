import Foundation

// Output modifiers are pressed as real keys around the output key. Flags alone
// do not reach apps that watch modifier presses, such as hold-to-talk shortcuts.
struct ModifierPresses {
    private static let modifiers: [(flag: EventFlags, keyCode: UInt16, device: EventFlags)] = [
        (.control, KeyCode.leftControl, .deviceLeftControl),
        (.option, KeyCode.leftOption, .deviceLeftOption),
        (.shift, KeyCode.leftShift, .deviceLeftShift),
        (.command, KeyCode.leftCommand, .deviceLeftCommand),
    ]

    private var counts: [UInt16: Int] = [:]
    private var outputs: [UInt16: [UInt16]] = [:]

    func isPressing(for output: UInt16) -> Bool { outputs[output] != nil }

    private var pressedFlags: EventFlags {
        Self.modifiers.reduce(into: EventFlags()) { flags, modifier in
            if counts[modifier.keyCode, default: 0] > 0 {
                flags.formUnion([modifier.flag, modifier.device])
            }
        }
    }

    /// Modifier downs to post before `output` goes down with `flags`.
    /// `visible` holds the modifiers apps already see as pressed.
    mutating func press(output: UInt16, flags: EventFlags, visible: EventFlags) -> [SyntheticKey] {
        guard outputs[output] == nil, SourceKeyCatalog.modifier(for: output) == nil else {
            return []
        }
        var codes: [UInt16] = []
        var downs: [SyntheticKey] = []
        for modifier in Self.modifiers
        where flags.contains(modifier.flag) && !visible.contains(modifier.flag) {
            codes.append(modifier.keyCode)
            counts[modifier.keyCode, default: 0] += 1
            if counts[modifier.keyCode] == 1 {
                downs.append(
                    SyntheticKey(
                        keyCode: modifier.keyCode, flags: visible.union(pressedFlags),
                        isKeyDown: true))
            }
        }
        if !codes.isEmpty { outputs[output] = codes }
        return downs
    }

    /// Modifier ups to post after `output` goes up.
    mutating func release(output: UInt16, visible: EventFlags) -> [SyntheticKey] {
        guard let codes = outputs.removeValue(forKey: output) else { return [] }
        var ups: [SyntheticKey] = []
        for code in codes.reversed() {
            counts[code, default: 0] -= 1
            guard counts[code] == 0 else { continue }
            counts[code] = nil
            ups.append(
                SyntheticKey(keyCode: code, flags: visible.union(pressedFlags), isKeyDown: false))
        }
        return ups
    }

    mutating func releaseAll(visible: EventFlags) -> [SyntheticKey] {
        outputs.keys.sorted().flatMap { release(output: $0, visible: visible) }
    }
}
