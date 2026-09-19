import AppKit
import Carbon
import Combine

// This is local presentation state. Profile key identifiers never depend on it.
@MainActor
final class KeyboardPresentation: ObservableObject {
    static let shared = KeyboardPresentation()

    enum Shape: String, CaseIterable {
        case ansi = "ANSI", iso = "ISO", jis = "JIS"

        // Standard ANSI/ISO/JIS keyboard type IDs from Apple’s Gestalt.h.
        var keyboardType: UInt32 {
            switch self {
            case .ansi: return 40
            case .iso: return 41
            case .jis: return 42
            }
        }
    }

    struct Legend: Equatable {
        var normal: String
        var shifted: String?
    }

    private var observedKeyboardType: UInt32?
    private var commandLegends: [String: String] = [:]
    private let inputSource: () -> TISInputSource?
    private let defaults: UserDefaults
    private let preferenceKey = "TenuoKeyboardShape"
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @Published private(set) var shape: Shape = .ansi
    @Published private(set) var legends: [String: Legend] = [:]
    @Published private(set) var detectedShape: Shape = .ansi
    @Published var override: Shape? {
        didSet {
            defaults.set(override?.rawValue, forKey: preferenceKey)
            refresh()
        }
    }

    init(
        defaults: UserDefaults = .standard,
        inputSource: @escaping () -> TISInputSource? = {
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        }
    ) {
        self.inputSource = inputSource
        self.defaults = defaults
        override = defaults.string(forKey: preferenceKey).flatMap(Shape.init(rawValue:))
        refresh()
        observe(
            DistributedNotificationCenter.default(),
            Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String))
        observe(NotificationCenter.default, NSApplication.didBecomeActiveNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        observers.append((center, token))
    }

    func observeKeyboardType(_ type: UInt32) {
        guard type > 0, type <= UInt32(Int16.max), observedKeyboardType != type else { return }
        observedKeyboardType = type
        refresh()
    }

    func resetKeyboardDetection() {
        observedKeyboardType = nil
        refresh()
    }

    func refresh() {
        let detectedType = observedKeyboardType ?? UInt32(LMGetKbdType())
        let detected: Shape
        switch KBGetLayoutType(Int16(detectedType)) {
        case UInt32(kKeyboardISO): detected = .iso
        case UInt32(kKeyboardJIS): detected = .jis
        default: detected = .ansi
        }
        if detectedShape != detected { detectedShape = detected }
        let nextShape = override ?? detected
        if shape != nextShape { shape = nextShape }
        let keyboardType = override?.keyboardType ?? detectedType

        guard let source = inputSource() else {
            clearLegends()
            return
        }
        var translationSource = source
        if TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) == nil,
            let fallback = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?
                .takeRetainedValue()
        {
            translationSource = fallback
        }
        guard
            let pointer = TISGetInputSourceProperty(
                translationSource, kTISPropertyUnicodeKeyLayoutData)
        else { clearLegends(); return }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { clearLegends(); return }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var next: [String: Legend] = [:]
        var nextCommand: [String: String] = [:]
        for key in KeyCatalog.all
        where key.group == .letters || key.group == .numbers
            || key.group == .punctuation
            || ["isoSection", "jisYen", "jisUnderscore"].contains(key.name)
        {
            guard
                let normal = translate(key.code, modifiers: 0, layout: layout, type: keyboardType)
            else { continue }
            let shifted = translate(
                key.code, modifiers: UInt32(shiftKey >> 8), layout: layout, type: keyboardType)
            let uppercase = normal.uppercased()
            let label =
                shifted?.lowercased() == normal.lowercased() && uppercase.count == 1
                ? uppercase : normal
            // Command can select a different alphabet (for example Dvorak–QWERTY Command).
            if let command = translate(
                key.code, modifiers: UInt32(cmdKey >> 8), layout: layout, type: keyboardType)
            {
                let upper = command.uppercased()
                nextCommand[key.name] = upper.count == 1 ? upper : command
            }
            next[key.name] = Legend(
                normal: label,
                shifted: shifted?.lowercased() == normal.lowercased() ? nil : shifted)
        }
        let commandChanged = commandLegends != nextCommand
        if commandChanged { objectWillChange.send() }
        commandLegends = nextCommand
        if legends != next { legends = next }
    }

    private func translate(
        _ code: UInt16, modifiers: UInt32, layout: UnsafePointer<UCKeyboardLayout>,
        type: UInt32
    ) -> String? {
        var deadState: UInt32 = 0
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout, code, UInt16(kUCKeyActionDisplay),
            modifiers, type,
            OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadState, buffer.count, &length, &buffer)
        guard status == noErr, length > 0 else { return nil }
        let value = String(utf16CodeUnits: buffer, count: length)
        guard
            !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return value
    }

    private func clearLegends() {
        if !commandLegends.isEmpty { objectWillChange.send(); commandLegends = [:] }
        if !legends.isEmpty { legends = [:] }
    }

    func shortcutKeyLabel(for binding: KeyBinding) -> String {
        if binding.modifiers.contains(.command), let key = KeyCatalog.key(named: binding.key),
            let label = commandLegends[key.name]
        {
            return label
        }
        return label(for: binding.key)
    }

    func label(for code: UInt16) -> String {
        guard let key = KeyCatalog.key(code: code) else { return "Key \(code)" }
        return label(for: key.name)
    }

    func label(for name: String) -> String {
        guard let key = KeyCatalog.key(named: name) else { return name }
        return legends[key.name]?.normal ?? key.label
    }

    func displayName(for name: String) -> String {
        guard let key = KeyCatalog.key(named: name) else { return name }
        return legends[key.name]?.normal ?? key.displayName
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }
}
