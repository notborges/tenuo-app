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

struct LayerActivity: Equatable, Sendable {
    let index: Int
    let isHeld: Bool
    let isToggled: Bool
    let isOneShot: Bool

    var isStateful: Bool { isToggled || isOneShot }
}

private struct LayerActivationState {
    private(set) var isHeld: Bool
    private(set) var isToggled: Bool
    private(set) var isOneShotArmed: Bool

    init(isBaseLayer: Bool = false) {
        isHeld = isBaseLayer
        isToggled = false
        isOneShotArmed = false
    }

    var isActive: Bool { isHeld || isToggled || isOneShotArmed }

    mutating func setHeld(_ value: Bool) {
        isHeld = value
    }

    mutating func toggle() {
        isToggled.toggle()
    }

    mutating func armOneShot() {
        isOneShotArmed = true
    }

    mutating func consumeOneShot() {
        isOneShotArmed = false
    }

    mutating func reset(isBaseLayer: Bool) {
        isHeld = isBaseLayer
        isToggled = false
        isOneShotArmed = false
    }
}

struct LayerEngine {

    private struct CompiledLayer {
        var id: UUID
        var trigger: LayerTrigger?
        var outputMode: LayerOutputMode
        var activation: LayerActivationState
        var tapAction: Action?
        var mappings: [UInt16: LayerMapping]
        var consumedFlags: EventFlags
        var triggerSlot: Int
    }

    private struct TapCandidate {
        var action: Action
        var layerIndex: Int
    }

    private struct TriggerRuntime {
        var key: TriggerKey
        var isDown = false
        var downTimestamp: UInt64 = 0
        var wasUsed = false
        var tapCandidate: TapCandidate?
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

    private let actionAvailability: any ActionAvailability

    var isEnabled: Bool

    private(set) var activeLayerIndex: Int?
    private(set) var activeLayerStates: [LayerActivity] = []

    init(
        profile: Profile = Presets.default,
        isEnabled: Bool = true,
        actionAvailability: any ActionAvailability = DefaultActionAvailability.current
    ) {
        self.isEnabled = isEnabled
        self.actionAvailability = actionAvailability
        held.reserveCapacity(16)
        apply(profile: profile)
    }

    mutating func apply(profile: Profile) {
        tapThresholdNanoseconds =
            UInt64(max(0, profile.tapThresholdMilliseconds)) * 1_000_000

        var keyOrder: [TriggerKey] = []
        for layer in profile.layers {
            guard let trigger = layer.trigger else { continue }
            if !keyOrder.contains(trigger.key) { keyOrder.append(trigger.key) }
        }
        triggers = keyOrder.map { TriggerRuntime(key: $0) }

        baseMask = 0
        layers = profile.layers.enumerated().map { index, layer in
            var mappings: [UInt16: LayerMapping] = [:]
            mappings.reserveCapacity(layer.mappings.count)
            for (name, action) in layer.mappings {
                guard let code = KeyCatalog.code(for: name) else { continue }
                if case let .action(.sendKey(binding)) = action, binding.keyCode == nil {
                    continue
                }
                mappings[code] = action
            }
            if layer.trigger == nil { baseMask |= UInt32(1) << UInt32(index) }
            return CompiledLayer(
                id: layer.id,
                trigger: layer.trigger,
                outputMode: layer.trigger == nil ? .layer : layer.outputMode,
                activation: LayerActivationState(isBaseLayer: layer.trigger == nil),
                tapAction: layer.tapAction,
                mappings: mappings,
                consumedFlags: layer.trigger?.consumedFlags ?? [],
                triggerSlot: layer.trigger.flatMap { keyOrder.firstIndex(of: $0.key) } ?? -1
            )
        }

        held.removeAll(keepingCapacity: true)
        activeMask = baseMask
        activeLayerIndex = nil
        activeLayerStates = []
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
            if !runtime.isDown {
                triggers[slot].isDown = true
                triggers[slot].downTimestamp = event.timestamp
                triggers[slot].wasUsed = false
                triggers[slot].tapCandidate = tapCandidate(for: slot, flags: event.flags)
            }
        } else if runtime.isDown {
            triggers[slot].isDown = false
            let candidate = runtime.tapCandidate
            triggers[slot].tapCandidate = nil
            fireTapIfEarned(
                candidate: candidate,
                wasUsed: runtime.wasUsed,
                downTimestamp: runtime.downTimestamp,
                releasedAt: event.timestamp,
                emit: emit)
        }

        recomputeActiveLayers(flags: event.flags, emit: emit)

        return runtime.key.isModifier ? .passThrough : .suppress
    }

    @inline(__always)
    private func tapCandidate(for slot: Int, flags: EventFlags) -> TapCandidate? {
        let candidates = layers.indices.compactMap { index -> TapCandidate? in
            guard let trigger = layers[index].trigger,
                trigger.key == triggers[slot].key,
                trigger.matches(flags: flags),
                let action = layers[index].tapAction
            else { return nil }
            return TapCandidate(action: action, layerIndex: index)
        }

        return candidates.sorted { lhs, rhs in
            let lhsSpecificity = layers[lhs.layerIndex].trigger?.specificity ?? 0
            let rhsSpecificity = layers[rhs.layerIndex].trigger?.specificity ?? 0
            if lhsSpecificity != rhsSpecificity { return lhsSpecificity > rhsSpecificity }
            return lhs.layerIndex > rhs.layerIndex
        }.first
    }

    @inline(__always)
    private mutating func fireTapIfEarned(
        candidate: TapCandidate?,
        wasUsed: Bool,
        downTimestamp: UInt64,
        releasedAt timestamp: UInt64,
        emit: (SyntheticKey) -> Void
    ) {
        guard let candidate, !wasUsed else { return }
        guard timestamp >= downTimestamp else { return }
        guard timestamp - downTimestamp <= tapThresholdNanoseconds else { return }
        perform(candidate.action, from: candidate.layerIndex, emit: emit)
    }

    @inline(__always)
    private mutating func perform(
        _ action: Action,
        from sourceLayerIndex: Int,
        emit: (SyntheticKey) -> Void
    ) {
        guard actionAvailability.canUse(action.kind) else { return }

        switch action {
        case let .sendKey(binding):
            guard let keyCode = binding.keyCode else { return }
            emit(SyntheticKey(keyCode: keyCode, flags: binding.flags, isKeyDown: true))
            emit(SyntheticKey(keyCode: keyCode, flags: binding.flags, isKeyDown: false))
        case let .toggleLayer(target):
            guard let index = layerIndex(for: target, from: sourceLayerIndex) else { return }
            layers[index].activation.toggle()
        case let .oneShotLayer(target):
            guard let index = layerIndex(for: target, from: sourceLayerIndex) else { return }
            layers[index].activation.armOneShot()
        }
    }

    private func layerIndex(for target: LayerTarget, from sourceLayerIndex: Int) -> Int? {
        switch target {
        case .current:
            return sourceLayerIndex
        case let .layer(id):
            return layers.firstIndex { $0.id == id }
        }
    }

    @inline(__always)
    private mutating func recomputeActiveLayers(
        flags: EventFlags,
        emit: (SyntheticKey) -> Void
    ) {
        var eligible = [Bool](repeating: false, count: layers.count)
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
            guard let trigger = layer.trigger, layer.triggerSlot >= 0,
                triggers[layer.triggerSlot].isDown,
                trigger.matches(flags: flags),
                trigger.specificity == bestSpecificity[layer.triggerSlot]
            else { continue }
            eligible[index] = true
        }

        var mask = baseMask
        for index in layers.indices {
            if layers[index].trigger != nil {
                layers[index].activation.setHeld(eligible[index])
            }
            guard layers[index].activation.isActive else { continue }
            guard layers[index].trigger != nil else { continue }
            mask |= UInt32(1) << UInt32(index)
            highest = max(highest ?? index, index)
        }

        let nextActiveLayerStates = layers.indices.compactMap { index -> LayerActivity? in
            guard layers[index].trigger != nil,
                mask & (UInt32(1) << UInt32(index)) != 0
            else { return nil }
            let activation = layers[index].activation
            return LayerActivity(
                index: index,
                isHeld: activation.isHeld,
                isToggled: activation.isToggled,
                isOneShot: activation.isOneShotArmed)
        }

        let maskChanged = mask != activeMask
        let layerStatesChanged = nextActiveLayerStates != activeLayerStates
        guard maskChanged || layerStatesChanged else { return }
        activeMask = mask
        activeLayerIndex = highest
        activeLayerStates = nextActiveLayerStates

        if maskChanged, !held.isEmpty { releaseHeldOutputs(emit: emit) }
    }

    @inline(__always)
    private mutating func handleKey(
        _ event: InputEvent,
        emit: (SyntheticKey) -> Void
    ) -> Disposition {
        switch event.kind {
        case .keyDown:
            return handleKeyDown(event, emit: emit)
        case .keyUp:
            return handleKeyUp(event)
        case .flagsChanged:
            return .passThrough
        }
    }

    @inline(__always)
    private mutating func handleKeyDown(
        _ event: InputEvent,
        emit: (SyntheticKey) -> Void
    ) -> Disposition {
        if !event.isRepeat { discardStrandedEntry(for: event.keyCode) }

        guard activeMask != 0 else { return .passThrough }
        let hasArmedOneShots = layers.contains { $0.activation.isOneShotArmed }

        var index = layers.count - 1
        while index >= 0 {
            defer { index -= 1 }
            guard activeMask & (UInt32(1) << UInt32(index)) != 0 else { continue }
            let layer = layers[index]
            guard layer.outputMode.appliesMappings else { continue }
            guard let action = layer.mappings[event.keyCode], action != .transparent else {
                continue
            }

            markUsed()
            switch action {
            case let .action(action):
                if event.isRepeat, action.kind != .sendKey {
                    return finishKeyDown(
                        .suppress, hasArmedOneShots: hasArmedOneShots,
                        flags: event.flags, emit: emit)
                }
                guard actionAvailability.canUse(action.kind) else {
                    remember(
                        source: event.keyCode, output: event.keyCode, flags: [],
                        awaitingSourceRelease: true)
                    return finishKeyDown(
                        .suppress, hasArmedOneShots: hasArmedOneShots,
                        flags: event.flags, emit: emit)
                }

                switch action {
                case let .sendKey(binding):
                    guard let output = binding.keyCode else {
                        return finishKeyDown(
                            .passThrough, hasArmedOneShots: hasArmedOneShots,
                            flags: event.flags, emit: emit)
                    }
                    let flags = outputFlags(
                        from: event.flags,
                        adding: binding.flags,
                        consumedBy: layer.consumedFlags)
                    remember(source: event.keyCode, output: output, flags: flags)
                    return finishKeyDown(
                        .rewrite(keyCode: output, flags: flags),
                        hasArmedOneShots: hasArmedOneShots,
                        flags: event.flags,
                        emit: emit)
                case .toggleLayer, .oneShotLayer:
                    perform(action, from: index, emit: emit)
                    remember(
                        source: event.keyCode, output: event.keyCode, flags: [],
                        awaitingSourceRelease: true)
                    recomputeActiveLayers(flags: event.flags, emit: emit)
                    return finishKeyDown(
                        .suppress, hasArmedOneShots: hasArmedOneShots,
                        flags: event.flags, emit: emit)
                }
            case .blocked:
                remember(
                    source: event.keyCode, output: event.keyCode, flags: [],
                    awaitingSourceRelease: true)
                return finishKeyDown(
                    .suppress, hasArmedOneShots: hasArmedOneShots,
                    flags: event.flags, emit: emit)
            case .transparent:
                continue
            }
        }

        guard let injecting = highestInjectingLayer() else {
            return finishKeyDown(
                .passThrough, hasArmedOneShots: hasArmedOneShots,
                flags: event.flags, emit: emit)
        }
        markUsed()
        let flags = outputFlags(
            from: event.flags,
            adding: Modifier.hyperFlags,
            consumedBy: layers[injecting].consumedFlags)
        remember(source: event.keyCode, output: event.keyCode, flags: flags)
        return finishKeyDown(
            .rewrite(keyCode: event.keyCode, flags: flags),
            hasArmedOneShots: hasArmedOneShots,
            flags: event.flags,
            emit: emit)
    }

    @inline(__always)
    private mutating func finishKeyDown(
        _ disposition: Disposition,
        hasArmedOneShots: Bool,
        flags: EventFlags,
        emit: (SyntheticKey) -> Void
    ) -> Disposition {
        guard hasArmedOneShots else { return disposition }
        for index in layers.indices where layers[index].activation.isOneShotArmed {
            layers[index].activation.consumeOneShot()
        }
        recomputeActiveLayers(flags: flags, emit: emit)
        return disposition
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
            if activeMask & (UInt32(1) << UInt32(index)) != 0,
                layers[index].outputMode.injectsHyper
            {
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
        for index in layers.indices {
            layers[index].activation.reset(isBaseLayer: layers[index].trigger == nil)
        }
        activeMask = baseMask
        activeLayerIndex = nil
        activeLayerStates = []
    }

    var isLayerActive: Bool { activeMask & ~baseMask != 0 }
    var hasKeysHeld: Bool { !held.isEmpty }

    func isActive(layerIndex: Int) -> Bool {
        activeMask & (UInt32(1) << UInt32(layerIndex)) != 0
    }
}
