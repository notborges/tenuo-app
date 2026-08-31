import Foundation

struct InputEvent: Equatable {
    enum Kind: Equatable { case keyDown, keyUp, flagsChanged }

    var kind: Kind
    var keyCode: UInt16
    var flags: EventFlags
    var isRepeat: Bool
    var isSynthetic: Bool
    var timestamp: UInt64

    init(
        kind: Kind, keyCode: UInt16, flags: EventFlags = [],
        isRepeat: Bool = false, isSynthetic: Bool = false, timestamp: UInt64 = 0
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.flags = flags
        self.isRepeat = isRepeat
        self.isSynthetic = isSynthetic
        self.timestamp = timestamp
    }
}

enum Disposition: Equatable {
    case passThrough
    case suppress
    case rewrite(keyCode: UInt16, flags: EventFlags)
}

struct SyntheticKey: Equatable {
    var keyCode: UInt16
    var flags: EventFlags
    var isKeyDown: Bool
}

// The event tap and the test target both drive this state machine. It has no
// AppKit or CoreGraphics dependencies.
struct LayerEngine {

    private struct CompiledLayer {
        var trigger: LayerTrigger?
        var holdMode: HoldMode
        var mappings: [UInt16: KeyAction]
        var consumedFlags: EventFlags
        var triggerSlot: Int
    }

    private struct TriggerRuntime {
        var key: TriggerKey
        var isDown = false
        var downTimestamp: UInt64 = 0
        var wasUsed = false
        var tapAction: (keyCode: UInt16, flags: EventFlags)?
    }

    private var layers: [CompiledLayer] = []
    private var triggers: [TriggerRuntime] = []

    private var activeMask: UInt32 = 0

    private var baseMask: UInt32 = 0

    private struct HeldKey {
        var source: UInt16
        var output: UInt16
        var flags: EventFlags
        var awaitingSourceRelease: Bool
    }
    private var held: [HeldKey] = []

    private var tapThresholdNanoseconds: UInt64 = 200_000_000

    var isEnabled: Bool

    private(set) var activeLayerIndex: Int?

    init(layout: Layout = Presets.default, isEnabled: Bool = true) {
        self.isEnabled = isEnabled
        held.reserveCapacity(16)
        apply(layout: layout)
    }

    mutating func apply(layout: Layout) {
        tapThresholdNanoseconds =
            UInt64(max(0, layout.tapThresholdMilliseconds)) * 1_000_000

        var keyOrder: [TriggerKey] = []
        for layer in layout.layers {
            guard let trigger = layer.trigger else { continue }
            if !keyOrder.contains(trigger.key) { keyOrder.append(trigger.key) }
        }
        triggers = keyOrder.map { TriggerRuntime(key: $0) }

        baseMask = 0
        layers = layout.layers.enumerated().map { index, layer in
            var mappings: [UInt16: KeyAction] = [:]
            mappings.reserveCapacity(layer.mappings.count)
            for (name, action) in layer.mappings {
                guard let code = KeyCatalog.code(for: name) else { continue }
                if case let .key(binding) = action, binding.keyCode == nil { continue }
                mappings[code] = action
            }
            if layer.trigger == nil { baseMask |= UInt32(1) << UInt32(index) }
            return CompiledLayer(
                trigger: layer.trigger,
                holdMode: layer.trigger == nil ? .layer : layer.holdMode,
                mappings: mappings,
                consumedFlags: layer.trigger?.consumedFlags ?? [],
                triggerSlot: layer.trigger.flatMap { keyOrder.firstIndex(of: $0.key) } ?? -1
            )
        }

        for (slot, runtime) in triggers.enumerated() {
            let candidates = layout.layers
                .filter { $0.trigger?.key == runtime.key && $0.tapAction != nil }
                .sorted { ($0.trigger?.specificity ?? 0) < ($1.trigger?.specificity ?? 0) }
            if let action = candidates.first?.tapAction, let code = action.keyCode {
                triggers[slot].tapAction = (code, action.flags)
            }
        }

        held.removeAll(keepingCapacity: true)
        activeMask = baseMask
        activeLayerIndex = nil
    }

    @inline(__always)
    mutating func handle(_ event: InputEvent, emit: (SyntheticKey) -> Void) -> Disposition {
        guard !event.isSynthetic else { return .passThrough }

        guard isEnabled else {
            reset(emit: emit)
            return .passThrough
        }

        if let slot = triggerSlot(for: event) {
            return handleTrigger(slot: slot, event: event, emit: emit)
        }

        if event.kind == .flagsChanged {
            recomputeActiveLayers(flags: event.flags, emit: emit)
            return .passThrough
        }

        return handleKey(event, emit: emit)
    }

    @inline(__always)
    private func triggerSlot(for event: InputEvent) -> Int? {
        for (slot, runtime) in triggers.enumerated()
        where runtime.key.observedKeyCode == event.keyCode {
            if runtime.key.isModifier {
                return event.kind == .flagsChanged ? slot : nil
            }
            return event.kind == .flagsChanged ? nil : slot
        }
        return nil
    }

    @inline(__always)
    private mutating func handleTrigger(
        slot: Int,
        event: InputEvent,
        emit: (SyntheticKey) -> Void
    ) -> Disposition {
        let runtime = triggers[slot]
        let isDown =
            runtime.key.isModifier
            ? (runtime.key.modifierFlag.map { event.flags.contains($0) } ?? false)
            : event.kind == .keyDown

        if isDown {
            if !runtime.isDown || !event.isRepeat {
                triggers[slot].isDown = true
                triggers[slot].downTimestamp = event.timestamp
                triggers[slot].wasUsed = false
            }
        } else if runtime.isDown {
            triggers[slot].isDown = false
            fireTapIfEarned(slot: slot, releasedAt: event.timestamp, emit: emit)
        }

        recomputeActiveLayers(flags: event.flags, emit: emit)

        return runtime.key.isModifier ? .passThrough : .suppress
    }

    @inline(__always)
    private mutating func fireTapIfEarned(
        slot: Int,
        releasedAt timestamp: UInt64,
        emit: (SyntheticKey) -> Void
    ) {
        let runtime = triggers[slot]
        guard let action = runtime.tapAction, !runtime.wasUsed else { return }
        guard timestamp >= runtime.downTimestamp else { return }
        guard timestamp - runtime.downTimestamp <= tapThresholdNanoseconds else { return }

        emit(SyntheticKey(keyCode: action.keyCode, flags: action.flags, isKeyDown: true))
        emit(SyntheticKey(keyCode: action.keyCode, flags: action.flags, isKeyDown: false))
    }

    @inline(__always)
    private mutating func recomputeActiveLayers(
        flags: EventFlags,
        emit: (SyntheticKey) -> Void
    ) {
        var mask = baseMask
        var bestSpecificity = [Int](repeating: -1, count: triggers.count)

        for layer in layers {
            guard let trigger = layer.trigger, layer.triggerSlot >= 0 else { continue }
            guard triggers[layer.triggerSlot].isDown, trigger.matches(flags: flags) else {
                continue
            }
            bestSpecificity[layer.triggerSlot] =
                max(bestSpecificity[layer.triggerSlot], trigger.specificity)
        }

        var highest: Int?
        for (index, layer) in layers.enumerated() {
            guard let trigger = layer.trigger, layer.triggerSlot >= 0 else { continue }
            guard triggers[layer.triggerSlot].isDown, trigger.matches(flags: flags) else {
                continue
            }
            guard trigger.specificity == bestSpecificity[layer.triggerSlot] else { continue }
            mask |= UInt32(1) << UInt32(index)
            highest = max(highest ?? index, index)
        }

        guard mask != activeMask else { return }
        activeMask = mask
        activeLayerIndex = highest

        if !held.isEmpty { releaseHeldOutputs(emit: emit) }
    }

    @inline(__always)
    private mutating func handleKey(
        _ event: InputEvent,
        emit _: (SyntheticKey) -> Void
    ) -> Disposition {
        switch event.kind {
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        case .flagsChanged:
            return .passThrough
        }
    }

    @inline(__always)
    private mutating func handleKeyDown(_ event: InputEvent) -> Disposition {
        if !event.isRepeat { discardStrandedEntry(for: event.keyCode) }

        guard activeMask != 0 else { return .passThrough }

        var index = layers.count - 1
        while index >= 0 {
            defer { index -= 1 }
            guard activeMask & (UInt32(1) << UInt32(index)) != 0 else { continue }
            let layer = layers[index]
            guard layer.holdMode.appliesMappings else { continue }
            guard let action = layer.mappings[event.keyCode], action != .transparent else {
                continue
            }

            markUsed()
            switch action {
            case let .key(binding):
                guard let output = binding.keyCode else { return .passThrough }
                let flags = outputFlags(
                    from: event.flags,
                    adding: binding.flags,
                    consumedBy: layer.consumedFlags)
                remember(source: event.keyCode, output: output, flags: flags)
                return .rewrite(keyCode: output, flags: flags)
            case .blocked:
                remember(
                    source: event.keyCode, output: event.keyCode, flags: [],
                    awaitingSourceRelease: true)
                return .suppress
            case .transparent:
                continue
            }
        }

        guard let injecting = highestInjectingLayer() else { return .passThrough }
        markUsed()
        let flags = outputFlags(
            from: event.flags,
            adding: Modifier.hyperFlags,
            consumedBy: layers[injecting].consumedFlags)
        remember(source: event.keyCode, output: event.keyCode, flags: flags)
        return .rewrite(keyCode: event.keyCode, flags: flags)
    }

    @inline(__always)
    private mutating func handleKeyUp(_ event: InputEvent) -> Disposition {
        guard let position = held.firstIndex(where: { $0.source == event.keyCode }) else {
            return .passThrough
        }
        let entry = held[position]
        held.remove(at: position)

        if entry.awaitingSourceRelease {
            return .suppress
        }
        return .rewrite(
            keyCode: entry.output,
            flags: outputFlags(
                from: event.flags,
                adding: entry.flags.subtracting(.arrowIntrinsic),
                consumedBy: []))
    }

    @inline(__always)
    private func highestInjectingLayer() -> Int? {
        var index = layers.count - 1
        while index >= 0 {
            if activeMask & (UInt32(1) << UInt32(index)) != 0, layers[index].holdMode.injectsHyper {
                return index
            }
            index -= 1
        }
        return nil
    }

    @inline(__always)
    private mutating func markUsed() {
        for slot in triggers.indices where triggers[slot].isDown {
            triggers[slot].wasUsed = true
        }
    }

    @inline(__always)
    private mutating func remember(
        source: UInt16,
        output: UInt16,
        flags: EventFlags,
        awaitingSourceRelease: Bool = false
    ) {
        let entry = HeldKey(
            source: source, output: output, flags: flags,
            awaitingSourceRelease: awaitingSourceRelease)
        if let position = held.firstIndex(where: { $0.source == source }) {
            held[position] = entry
        } else {
            held.append(entry)
        }
    }

    @inline(__always)
    private mutating func discardStrandedEntry(for source: UInt16) {
        guard
            let position = held.firstIndex(where: {
                $0.source == source && $0.awaitingSourceRelease
            })
        else { return }
        held.remove(at: position)
    }

    @inline(__always)
    private func outputFlags(
        from flags: EventFlags,
        adding added: EventFlags,
        consumedBy consumed: EventFlags
    ) -> EventFlags {
        var result = flags
        result.remove(.alphaShift)
        result.remove(.allDeviceBits)
        result.remove(consumed)
        result.formUnion(added)
        return result
    }

    @inline(__always)
    private mutating func releaseHeldOutputs(emit: (SyntheticKey) -> Void) {
        for position in held.indices where !held[position].awaitingSourceRelease {
            emit(
                SyntheticKey(
                    keyCode: held[position].output,
                    flags: held[position].flags,
                    isKeyDown: false))
            held[position].awaitingSourceRelease = true
        }
    }

    mutating func reset(emit: (SyntheticKey) -> Void) {
        releaseHeldOutputs(emit: emit)
        held.removeAll(keepingCapacity: true)
        for slot in triggers.indices {
            triggers[slot].isDown = false
            triggers[slot].wasUsed = true
        }
        activeMask = baseMask
        activeLayerIndex = nil
    }

    var isLayerActive: Bool { activeMask & ~baseMask != 0 }
    var hasKeysHeld: Bool { !held.isEmpty }

    func isActive(layerIndex: Int) -> Bool {
        activeMask & (UInt32(1) << UInt32(layerIndex)) != 0
    }
}
