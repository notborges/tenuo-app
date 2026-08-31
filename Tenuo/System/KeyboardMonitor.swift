import CoreGraphics
import Foundation
import os

final class KeyboardMonitor {
    private static let syntheticMarker: Int64 = 0x4E56_5348  // "TENU"

    private let log = Logger(subsystem: "app.tenuo", category: "tap")

    private var engine: LayerEngine
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let eventSource = CGEventSource(stateID: .privateState)

    var onTapInvalidated: (() -> Void)?

    var onActiveLayerChanged: ((Int?) -> Void)?
    private var lastActiveLayer: Int?

    var isRunning: Bool { tap != nil }

    init(profile: Profile, isEnabled: Bool) {
        engine = LayerEngine(profile: profile, isEnabled: isEnabled)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: { _, type, event, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon)
                        .takeUnretainedValue()
                    return monitor.process(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            log.error("CGEvent.tapCreate failed; Accessibility permission is likely missing")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = source
        log.info("Event tap installed")
        return true
    }

    func stop() {
        guard let tap, let runLoopSource else { return }
        flushHeldKeys()
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.runLoopSource = nil
        log.info("Event tap removed")
    }

    func update(profile: Profile) {
        flushHeldKeys()
        engine.apply(profile: profile)
    }

    func update(isEnabled: Bool) {
        guard isEnabled != engine.isEnabled else { return }
        if !isEnabled { flushHeldKeys() }
        engine.isEnabled = isEnabled
    }

    func flushHeldKeys() {
        let hadActiveLayer = engine.activeLayerIndex != nil || lastActiveLayer != nil
        engine.reset { [weak self] key in self?.post(key) }
        lastActiveLayer = nil
        if hadActiveLayer { onActiveLayerChanged?(nil) }
    }

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout:
            log.error("Tap disabled by timeout; re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            flushHeldKeys()
            return nil

        case .tapDisabledByUserInput:
            log.error("Tap disabled by user input")
            flushHeldKeys()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            onTapInvalidated?()
            return nil

        case .keyDown, .keyUp, .flagsChanged:
            break

        default:
            return Unmanaged.passUnretained(event)
        }

        let input = InputEvent(
            kind: type == .keyDown ? .keyDown : (type == .keyUp ? .keyUp : .flagsChanged),
            keyCode: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
            flags: EventFlags(rawValue: event.flags.rawValue),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            isSynthetic: event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker,
            timestamp: event.timestamp
        )

        let disposition = engine.handle(input, emit: { [weak self] key in self?.post(key) })

        let active = engine.activeLayerIndex
        if active != lastActiveLayer {
            lastActiveLayer = active
            onActiveLayerChanged?(active)
        }

        switch disposition {
        case .passThrough:
            return Unmanaged.passUnretained(event)

        case .suppress:
            return nil

        case let .rewrite(keyCode, flags):
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
            event.flags = CGEventFlags(rawValue: flags.rawValue)
            return Unmanaged.passUnretained(event)
        }
    }

    private func post(_ key: SyntheticKey) {
        guard
            let event = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: CGKeyCode(key.keyCode),
                keyDown: key.isKeyDown)
        else { return }
        event.flags = CGEventFlags(rawValue: key.flags.rawValue)
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        event.post(tap: .cgSessionEventTap)
    }

    deinit {
        stop()
    }
}
