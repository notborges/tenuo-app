import CoreGraphics
import Foundation
import os

final class KeyboardMonitor {
    private static let syntheticMarker: Int64 = 0x4E56_5348

    private let log = Logger(subsystem: "app.tenuo", category: "tap")

    private var engine: LayerEngine
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let eventSource = CGEventSource(stateID: .privateState)

    private var pressedKeys: Set<UInt16> = []
    private var physicalModifiers: CGEventFlags = []
    private static let heldModifierMask: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn,
    ]

    var isQuiescent: Bool {
        !isRunning || (engine.isQuiescent && pressedKeys.isEmpty && physicalModifiers.isEmpty)
    }
    var onIdle: (() -> Void)?

    private var lastKeyboardType: UInt32?
    var onKeyboardTypeChanged: ((UInt32) -> Void)?

    var onAction: ((MacAction) -> Void)?

    var onTapInvalidated: (() -> Void)?

    var onActiveLayersChanged: (([LayerActivity]) -> Void)?
    private var lastActiveLayerStates: [LayerActivity] = []

    var isRunning: Bool { tap != nil }

    init(
        profile: Profile,
        isEnabled: Bool,
        actionAvailability: any ActionAvailability = DefaultActionAvailability.current
    ) {
        engine = LayerEngine(
            profile: profile,
            isEnabled: isEnabled,
            actionAvailability: actionAvailability)
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

        pressedKeys = Set(
            (UInt16(0)..<128).filter { CGEventSource.keyState(.combinedSessionState, key: $0) })
        physicalModifiers = CGEventSource.flagsState(.combinedSessionState).intersection(
            Self.heldModifierMask)
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
        pressedKeys.removeAll(keepingCapacity: true)
        physicalModifiers = []
        log.info("Event tap removed")
    }

    func updateApplication(_ applicationID: String?) {
        engine.updateApplication(applicationID)
    }

    func update(profile: Profile) {
        flushHeldKeys()
        engine.apply(profile: profile)
        publishActiveLayerIfNeeded()
    }

    func update(isEnabled: Bool) {
        guard isEnabled != engine.isEnabled else { return }
        if !isEnabled { flushHeldKeys() }
        engine.isEnabled = isEnabled
    }

    func flushHeldKeys() {
        lastKeyboardType = nil
        let hadActiveLayer = engine.isLayerActive || !lastActiveLayerStates.isEmpty
        engine.reset { [weak self] key in self?.post(key) }
        lastActiveLayerStates = []
        if hadActiveLayer { onActiveLayersChanged?([]) }
        onIdle?()
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

        let wasIdle = isQuiescent
        if !input.isSynthetic {
            let typeID = event.getIntegerValueField(.keyboardEventKeyboardType)
            if type == .keyDown, typeID > 0, typeID <= Int64(Int16.max) {
                let keyboardType = UInt32(typeID)
                if lastKeyboardType != keyboardType {
                    lastKeyboardType = keyboardType
                    onKeyboardTypeChanged?(keyboardType)
                }
            }
            if type == .keyDown { pressedKeys.insert(input.keyCode) }
            if type == .keyUp { pressedKeys.remove(input.keyCode) }
            physicalModifiers = event.flags.intersection(Self.heldModifierMask)
        }
        let disposition = engine.handle(input, emit: { [weak self] key in self?.post(key) })
        if !wasIdle && isQuiescent { onIdle?() }
        for action in engine.takePendingActions() { onAction?(action) }
        publishActiveLayerIfNeeded()

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

    private func publishActiveLayerIfNeeded() {
        let active = engine.activeLayerStates
        guard active != lastActiveLayerStates else { return }
        lastActiveLayerStates = active
        onActiveLayersChanged?(active)
    }

    deinit {
        stop()
    }
}
