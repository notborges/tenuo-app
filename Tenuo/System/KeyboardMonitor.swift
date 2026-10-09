import AppKit
import CoreGraphics
import Foundation
import os

final class KeyboardMonitor {
    private static let syntheticMarker: Int64 = 0x4E56_5348

    private let log = Logger(subsystem: "app.tenuo", category: "tap")

    private var hasGestureMappings: Bool
    private let availability: any ActionAvailability
    private var gestureSequence = TrackpadSequence()
    private var gestureAssignments: [String: GestureAssignment] = [:]
    private var pendingScrollEvents: [CGEvent] = []
    private var applicationID: String?
    private var engine: LayerEngine
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let eventSource = CGEventSource(stateID: .privateState)

    private var pressedKeys: Set<UInt16> = []
    private var physicalModifiers: CGEventFlags = []
    private var modifierPresses = ModifierPresses()
    private var stopWhenReleased = false
    private var waitingForRemapRemoval = false
    var capsLockRemapIsInstalled = false {
        didSet { engine.isCapsLockRemapped = capsLockRemapIsInstalled }
    }
    var isCapsLockHeld: Bool {
        // Installation can finish before its main-queue callback. Preserve
        // this release identity even while bridge confirmation is pending.
        pressedKeys.contains(KeyCode.f18)
    }
    var onCapsLockReleased: (() -> Void)?
    var onStopped: (() -> Void)?
    private static let heldModifierMask: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn,
        CGEventFlags(rawValue: EventFlags.allDeviceBits.rawValue),
    ]

    var isQuiescent: Bool {
        !isRunning
            || (!gestureSequence.isTouching(at: ProcessInfo.processInfo.systemUptime)
                && engine.isQuiescent && pressedKeys.isEmpty && physicalModifiers.isEmpty)
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
        hasGestureMappings = profile.hasGestures
        availability = actionAvailability
        engine = LayerEngine(
            profile: profile,
            isEnabled: isEnabled,
            actionAvailability: actionAvailability)
        engine.isCapsLockRemapped = false
    }

    @discardableResult
    func start() -> Bool {
        stopWhenReleased = false
        waitingForRemapRemoval = false
        guard tap == nil else { return true }

        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)

        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: { proxy, type, event, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon)
                        .takeUnretainedValue()
                    return monitor.process(proxy: proxy, type: type, event: event)
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

        gestureSequence.reset()
        pressedKeys = Set(
            (UInt16(0)..<128).filter {
                SourceKeyCatalog.modifier(for: $0) == nil && $0 != KeyCode.capsLock
                    && CGEventSource.keyState(.hidSystemState, key: $0)
            })
        physicalModifiers = CGEventSource.flagsState(.hidSystemState).intersection(
            Self.heldModifierMask)
        tap = port
        runLoopSource = source
        refreshTrackpad()
        log.info("Event tap installed")
        return true
    }

    func stop(waitingForRemap: Bool = false, immediately: Bool = false) {
        guard tap != nil else { return }
        engine.isEnabled = false
        stopWhenReleased = true
        waitingForRemapRemoval = waitingForRemap
        TrackpadContacts.shared.setEnabled(false)
        gestureSequence.reset()
        flushHeldKeys()
        // Keep the tap just long enough to consume releases for keys whose
        // physical down was suppressed. Removing it mid-press leaks key-ups.
        if immediately {
            removeTap()
        } else {
            finishStoppingIfReady()
        }
    }

    func remapWasRemoved() {
        capsLockRemapIsInstalled = false
        waitingForRemapRemoval = false
        finishStoppingIfReady()
    }

    private func finishStoppingIfReady() {
        if stopWhenReleased, !waitingForRemapRemoval, !engine.hasPendingReleases, !isCapsLockHeld {
            removeTap()
        }
    }

    private func removeTap() {
        guard let tap, let runLoopSource else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CFMachPortInvalidate(tap)
        self.tap = nil
        self.runLoopSource = nil
        pressedKeys.removeAll(keepingCapacity: true)
        physicalModifiers = []
        engine.reconcilePhysicalState()
        stopWhenReleased = false
        waitingForRemapRemoval = false
        log.info("Event tap removed")
        onStopped?()
    }

    func updateApplication(_ applicationID: String?) {
        if self.applicationID != applicationID { cancelGesture() }
        self.applicationID = applicationID
        engine.updateApplication(applicationID)
        if !availability.canUse(.macAction) { cancelGesture() }
        refreshTrackpad()
    }

    func update(profile: Profile) {
        flushHeldKeys()
        engine.apply(profile: profile)
        hasGestureMappings = profile.hasGestures
        refreshTrackpad()
        publishActiveLayerIfNeeded()
    }

    func update(isEnabled: Bool) {
        guard isEnabled != engine.isEnabled else { return }
        if !isEnabled { flushHeldKeys() }
        engine.isEnabled = isEnabled
        refreshTrackpad()
    }

    func focusDidChange() {
        let wasIdle = isQuiescent
        cancelGesture()
        // Release outputs in the previous app, but keep physically held layer keys active.
        let flags = EventFlags(rawValue: physicalModifiers.rawValue)
        postEmitted { engine.reset(preservingHeldTriggers: true, flags: flags, emit: $0) }
        publishActiveLayerIfNeeded()
        if !wasIdle && isQuiescent { onIdle?() }
    }

    func flushHeldKeys() {
        cancelGesture()
        lastKeyboardType = nil
        let hadActiveLayer = engine.isLayerActive || !lastActiveLayerStates.isEmpty
        postEmitted { engine.reset(emit: $0) }
        releaseModifierPresses()
        lastActiveLayerStates = []
        if hadActiveLayer { onActiveLayersChanged?([]) }
        onIdle?()
    }

    func recoverPhysicalState() {
        let wasCapsLockHeld = isCapsLockHeld
        flushHeldKeys()
        // Sleep and keyboard removal can lose physical releases altogether.
        // Retain suppression only for sources the HID system still sees down.
        let down = Set(
            (UInt16(0)..<128).filter { CGEventSource.keyState(.hidSystemState, key: $0) })
        engine.reconcilePhysicalState(keysDown: down)
        pressedKeys = down.filter {
            SourceKeyCatalog.modifier(for: $0) == nil && $0 != KeyCode.capsLock
        }
        physicalModifiers = CGEventSource.flagsState(.hidSystemState).intersection(
            Self.heldModifierMask)
        finishStoppingIfReady()
        if wasCapsLockHeld && !isCapsLockHeld { onCapsLockReleased?() }
        if isQuiescent { onIdle?() }
    }

    private func process(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<
        CGEvent
    >? {
        switch type {
        case .tapDisabledByTimeout:
            gestureSequence.reset()
            log.error("Tap disabled by timeout; re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            recoverPhysicalState()
            return nil

        case .tapDisabledByUserInput:
            gestureSequence.reset()
            log.error("Tap disabled by user input")
            recoverPhysicalState()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            onTapInvalidated?()
            return nil

        case .scrollWheel:
            return processScroll(event, proxy: proxy)

        case .keyDown, .keyUp, .flagsChanged:
            break

        default:
            return Unmanaged.passUnretained(event)
        }

        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let isSynthetic = event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker
        let flags =
            isSynthetic ? EventFlags(rawValue: event.flags.rawValue) : physicalFlags(event.flags)
        let modifierIsDown: Bool?
        if type == .flagsChanged, let modifier = SourceKeyCatalog.modifier(for: code) {
            // Device bits distinguish releasing one side while the other is
            // held. Some keyboards omit them; consult the raw HID state then.
            if modifier.deviceFlag != nil, flags.intersection(modifier.modifierSideFlags).isEmpty,
                let generalFlag = modifier.modifierFlag, flags.contains(generalFlag)
            {
                modifierIsDown = CGEventSource.keyState(.hidSystemState, key: code)
            } else {
                modifierIsDown = modifier.isDown(flags: flags)
            }
        } else {
            modifierIsDown = nil
        }
        let input = InputEvent(
            kind: type == .keyDown ? .keyDown : (type == .keyUp ? .keyUp : .flagsChanged),
            keyCode: code,
            flags: flags,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            isSynthetic: isSynthetic,
            timestamp: event.timestamp,
            modifierIsDown: modifierIsDown,
            physicalFunctionIsDown: isSynthetic
                ? nil : CGEventSource.keyState(.hidSystemState, key: KeyCode.function)
        )

        let wasIdle = isQuiescent
        let wasCapsLockHeld = isCapsLockHeld
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
            if SourceKeyCatalog.intrinsicFlags(for: input.keyCode).contains(.secondaryFn) {
                physicalModifiers.remove(.maskSecondaryFn)
                if input.physicalFunctionIsDown == true {
                    physicalModifiers.insert(.maskSecondaryFn)
                }
            }
        }
        let disposition = postEmitted(proxy: proxy) { engine.handle(input, emit: $0) }
        if gestureAssignments.values.contains(where: { !engine.isGestureLayerActive($0.layerID) }) {
            cancelGesture()
        }
        for action in engine.takePendingActions() { onAction?(action) }
        publishActiveLayerIfNeeded()
        defer {
            finishStoppingIfReady()
            if wasCapsLockHeld && !isCapsLockHeld { onCapsLockReleased?() }
            if !wasIdle && isQuiescent { onIdle?() }
        }

        switch disposition {
        case .passThrough:
            return Unmanaged.passUnretained(event)

        case .suppress:
            return nil

        case let .rewrite(keyCode, flags):
            if let kind = keyKind(input.kind),
                postWithModifiers(
                    SyntheticKey(keyCode: keyCode, flags: flags, isKeyDown: kind == .keyDown),
                    isRepeat: input.isRepeat, proxy: proxy)
            {
                return nil
            }
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(keyCode))
            event.flags = CGEventFlags(
                rawValue: flags.union(SourceKeyCatalog.intrinsicFlags(for: keyCode)).rawValue)
            return Unmanaged.passUnretained(event)

        case let .replace(kind, keyCode, flags):
            if keyKind(kind) != nil,
                postWithModifiers(
                    SyntheticKey(keyCode: keyCode, flags: flags, isKeyDown: kind == .keyDown),
                    isRepeat: input.isRepeat, proxy: proxy)
            {
                return nil
            }
            guard
                let replacement = CGEvent(
                    keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: kind == .keyDown
                )
            else { return nil }
            replacement.flags = CGEventFlags(
                rawValue: flags.union(SourceKeyCatalog.intrinsicFlags(for: keyCode)).rawValue)
            replacement.timestamp = event.timestamp
            replacement.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            return Unmanaged.passRetained(replacement)

        case .toggleCapsLock:
            if !CapsLockRemapper.toggleNativeCapsLock() {
                log.error("Could not toggle the native Caps Lock state")
            }
            return nil
        }
    }

    private func physicalFlags(_ flags: CGEventFlags) -> EventFlags {
        let raw = EventFlags(rawValue: flags.rawValue)
        var result = raw
        // Fill missing side bits from physical state before the engine strips
        // mapped sources. This also preserves the opposite, unmapped modifier.
        for key in TriggerKey.leftModifiers + TriggerKey.rightModifiers {
            guard let flag = key.modifierFlag, let side = key.deviceFlag,
                let code = key.physicalKeyCode, raw.contains(flag),
                raw.intersection(key.modifierSideFlags).isEmpty
            else { continue }
            if CGEventSource.keyState(.hidSystemState, key: code) { result.formUnion(side) }
        }
        return result
    }

    func restartTrackpad() {
        cancelGesture()
        gestureSequence.reset()
        TrackpadContacts.shared.setEnabled(false)
        refreshTrackpad()
    }

    private func refreshTrackpad() {
        TrackpadContacts.shared.setEnabled(
            isRunning && engine.isEnabled && hasGestureMappings && availability.canUse(.macAction))
    }

    private func processScroll(_ event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        guard
            gestureSequence.isCaptured
                || (engine.isEnabled && hasGestureMappings && availability.canUse(.macAction))
        else { return Unmanaged.passUnretained(event) }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker,
            let scroll = NSEvent(cgEvent: event), scroll.hasPreciseScrollingDeltas
        else {
            return Unmanaged.passUnretained(event)
        }
        let phase: TrackpadSequence.Phase
        if scroll.momentumPhase.contains(.ended) {
            phase = .momentumEnded
        } else if !scroll.momentumPhase.isEmpty {
            phase = .momentum
        } else if scroll.phase.contains(.cancelled) {
            phase = .cancelled
        } else if scroll.phase.contains(.ended) {
            phase = .ended
        } else if scroll.phase.contains(.began) {
            phase = .began
        } else if scroll.phase.contains(.changed) {
            phase = .changed
        } else {
            return Unmanaged.passUnretained(event)
        }

        let wasIdle = isQuiescent
        if phase == .began {
            pendingScrollEvents.removeAll(keepingCapacity: true)
            gestureAssignments =
                TrackpadContacts.shared.hasRecentScrollContact
                ? engine.beginTrackpadGesture() : [:]
        }
        var result = gestureSequence.handle(
            phase: phase, x: Double(scroll.scrollingDeltaX),
            y: Double(scroll.scrollingDeltaY),
            time: ProcessInfo.processInfo.systemUptime,
            canCapture: !gestureAssignments.isEmpty,
            isDirectionInvertedFromDevice: scroll.isDirectionInvertedFromDevice,
            mappedGestures: Set(gestureAssignments.keys.compactMap(TrackpadGesture.init(rawValue:)))
        )
        // Bound storage if a long, ambiguous movement never resolves to a direction.
        if gestureSequence.isPending, pendingScrollEvents.count >= 128 {
            result = gestureSequence.passThrough()
        }
        if result.replayBuffered {
            for buffered in pendingScrollEvents { buffered.tapPostEvent(proxy) }
            pendingScrollEvents.removeAll(keepingCapacity: true)
        } else if gestureSequence.isPending, let copy = event.copy() {
            pendingScrollEvents.append(copy)
        } else {
            pendingScrollEvents.removeAll(keepingCapacity: true)
        }
        if let gesture = result.gesture, !gestureAssignments.isEmpty {
            let assignment = gestureAssignments[gesture.rawValue]
            let flags = EventFlags(rawValue: event.flags.rawValue)
            postEmitted { engine.performGesture(assignment, flags: flags, emit: $0) }
            for action in engine.takePendingActions() { onAction?(action) }
            publishActiveLayerIfNeeded()
        }
        if !wasIdle && isQuiescent { onIdle?() }
        return result.suppress ? nil : Unmanaged.passUnretained(event)
    }

    private func cancelGesture() {
        gestureAssignments.removeAll()
        pendingScrollEvents.removeAll(keepingCapacity: true)
        gestureSequence.cancelRecognition()
    }

    // Posting reads engine state, so keys emitted during an engine call are
    // posted after it returns. Reading the engine mid-mutation traps at runtime.
    @discardableResult
    private func postEmitted<Result>(
        proxy: CGEventTapProxy? = nil,
        _ body: (_ emit: (SyntheticKey) -> Void) -> Result
    ) -> Result {
        var emitted: [SyntheticKey] = []
        let result = body { emitted.append($0) }
        for key in emitted { post(key, proxy: proxy) }
        return result
    }

    private var visibleModifiers: EventFlags {
        engine.visibleModifiers(EventFlags(rawValue: physicalModifiers.rawValue))
    }

    private func keyKind(_ kind: InputEvent.Kind) -> InputEvent.Kind? {
        kind == .flagsChanged ? nil : kind
    }

    // Posts the output between its modifier presses so they arrive in order.
    // Returns false when the rewritten event can be forwarded unchanged.
    private func postWithModifiers(
        _ key: SyntheticKey, isRepeat: Bool, proxy: CGEventTapProxy
    ) -> Bool {
        let needsModifiers =
            key.isKeyDown
            ? !isRepeat && !modifierPresses.isPressing(for: key.keyCode)
                && !key.flags.intersection([.command, .option, .control, .shift])
                    .subtracting(visibleModifiers).isEmpty
            : modifierPresses.isPressing(for: key.keyCode)
        guard needsModifiers else { return false }
        post(key, proxy: proxy)
        return true
    }

    private func post(_ key: SyntheticKey, proxy: CGEventTapProxy? = nil) {
        if key.isKeyDown {
            for down in modifierPresses.press(
                output: key.keyCode, flags: key.flags, visible: visibleModifiers)
            {
                postEvent(down, proxy: proxy)
            }
            postEvent(key, proxy: proxy)
        } else {
            postEvent(key, proxy: proxy)
            for up in modifierPresses.release(output: key.keyCode, visible: visibleModifiers) {
                postEvent(up, proxy: proxy)
            }
        }
    }

    private func releaseModifierPresses() {
        for up in modifierPresses.releaseAll(visible: visibleModifiers) { postEvent(up) }
    }

    private func postEvent(_ key: SyntheticKey, proxy: CGEventTapProxy? = nil) {
        guard
            let event = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: CGKeyCode(key.keyCode),
                keyDown: key.isKeyDown)
        else { return }
        event.flags = CGEventFlags(
            rawValue: key.flags.union(SourceKeyCatalog.intrinsicFlags(for: key.keyCode)).rawValue)
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        if let proxy {
            event.tapPostEvent(proxy)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func publishActiveLayerIfNeeded() {
        let active = engine.activeLayerStates
        guard active != lastActiveLayerStates else { return }
        lastActiveLayerStates = active
        onActiveLayersChanged?(active)
    }

    deinit {
        stop(immediately: true)
    }
}
