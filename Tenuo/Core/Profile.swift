import Foundation

enum ModifierRequirement: String, Codable, CaseIterable, Hashable, Sendable {
    case shift, leftShift, rightShift
    case control, leftControl, rightControl
    case option, leftOption, rightOption
    case command, leftCommand, rightCommand
    case function

    var generalFlag: EventFlags {
        switch self {
        case .shift, .leftShift, .rightShift: return .shift
        case .control, .leftControl, .rightControl: return .control
        case .option, .leftOption, .rightOption: return .option
        case .command, .leftCommand, .rightCommand: return .command
        case .function: return .secondaryFn
        }
    }

    var sideFlag: EventFlags? {
        switch self {
        case .leftShift: return .deviceLeftShift
        case .rightShift: return .deviceRightShift
        case .leftControl: return .deviceLeftControl
        case .rightControl: return .deviceRightControl
        case .leftOption: return .deviceLeftOption
        case .rightOption: return .deviceRightOption
        case .leftCommand: return .deviceLeftCommand
        case .rightCommand: return .deviceRightCommand
        default: return nil
        }
    }

    @inline(__always)
    func isSatisfied(by flags: EventFlags) -> Bool {
        guard flags.contains(generalFlag) else { return false }
        guard let sideFlag else { return true }
        return flags.contains(sideFlag)
    }

    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .leftShift: return "⇧L"
        case .rightShift: return "⇧R"
        case .control: return "⌃"
        case .leftControl: return "⌃L"
        case .rightControl: return "⌃R"
        case .option: return "⌥"
        case .leftOption: return "⌥L"
        case .rightOption: return "⌥R"
        case .command: return "⌘"
        case .leftCommand: return "⌘L"
        case .rightCommand: return "⌘R"
        case .function: return "fn"
        }
    }

    var displayName: String {
        switch self {
        case .shift: return "Shift"
        case .leftShift: return "Left Shift"
        case .rightShift: return "Right Shift"
        case .control: return "Control"
        case .leftControl: return "Left Control"
        case .rightControl: return "Right Control"
        case .option: return "Option"
        case .leftOption: return "Left Option"
        case .rightOption: return "Right Option"
        case .command: return "Command"
        case .leftCommand: return "Left Command"
        case .rightCommand: return "Right Command"
        case .function: return "Fn"
        }
    }
}

struct LayerTrigger: Codable, Equatable, Hashable, Sendable {
    var key: TriggerKey
    var modifiers: [ModifierRequirement]

    init(key: TriggerKey = .capsLock, modifiers: [ModifierRequirement] = []) {
        self.key = key
        self.modifiers = modifiers
    }

    enum CodingKeys: String, CodingKey { case key, modifiers }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(TriggerKey.self, forKey: .key)
        modifiers =
            try container.decodeIfPresent(
                [ModifierRequirement].self,
                forKey: .modifiers) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        if !modifiers.isEmpty { try container.encode(modifiers, forKey: .modifiers) }
    }

    @inline(__always)
    func matches(flags: EventFlags) -> Bool {
        for modifier in modifiers where !modifier.isSatisfied(by: flags) { return false }
        return true
    }

    var specificity: Int { modifiers.count }

    var consumedFlags: EventFlags {
        var flags = key.flagToStripWhileHeld
        for modifier in modifiers { flags.formUnion(modifier.generalFlag) }
        return flags
    }

    var displayLabel: String {
        modifiers.map(\.symbol).joined() + key.shortSymbol
    }
}

struct ApplicationOverride: Codable, Equatable, Sendable {
    var name: String
    var mappings: [String: LayerMapping]
    var gestures: [String: LayerMapping] = [:]

    private enum CodingKeys: String, CodingKey { case name, mappings, gestures }

    init(name: String, mappings: [String: LayerMapping], gestures: [String: LayerMapping] = [:]) {
        self.name = name
        self.mappings = mappings
        self.gestures = gestures
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        mappings = try container.decode([String: LayerMapping].self, forKey: .mappings)
        gestures =
            try container.decodeIfPresent([String: LayerMapping].self, forKey: .gestures) ?? [:]
    }
}

struct Layer: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var trigger: LayerTrigger?
    var outputMode: LayerOutputMode
    var tapAction: Action?
    var mappings: [String: LayerMapping]
    var applications: [String: ApplicationOverride] = [:]
    var gestures: [String: LayerMapping] = [:]

    func gestures(for applicationID: String?) -> [String: LayerMapping] {
        guard let applicationID, let override = applications[applicationID] else { return gestures }
        return gestures.merging(override.gestures) { _, override in override }
    }

    func mappings(for applicationID: String?) -> [String: LayerMapping] {
        guard let applicationID, let override = applications[applicationID] else { return mappings }
        return mappings.merging(override.mappings) { _, override in override }
    }

    var mappedSourceCodes: Set<UInt16> {
        Set(
            ([mappings] + applications.values.map(\.mappings)).flatMap { mappings in
                mappings.compactMap { source, mapping in
                    mapping == .transparent ? nil : SourceKeyCatalog.observedCode(for: source)
                }
            })
    }

    init(
        id: UUID = UUID(),
        name: String,
        trigger: LayerTrigger? = nil,
        outputMode: LayerOutputMode = .layer,
        tapAction: Action? = nil,
        mappings: [String: LayerMapping] = [:]
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.outputMode = outputMode
        self.tapAction = tapAction
        self.mappings = mappings
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, trigger, holdMode, tapAction, mappings, applications, gestures
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        gestures =
            try container.decodeIfPresent([String: LayerMapping].self, forKey: .gestures) ?? [:]
        applications =
            try container.decodeIfPresent(
                [String: ApplicationOverride].self, forKey: .applications) ?? [:]
        trigger = try container.decodeIfPresent(LayerTrigger.self, forKey: .trigger)
        outputMode =
            try container.decodeIfPresent(LayerOutputMode.self, forKey: .holdMode)
            ?? .layer
        tapAction = try container.decodeIfPresent(Action.self, forKey: .tapAction)
        mappings =
            try container.decodeIfPresent([String: LayerMapping].self, forKey: .mappings) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(trigger, forKey: .trigger)
        try container.encode(outputMode, forKey: .holdMode)
        try container.encodeIfPresent(tapAction, forKey: .tapAction)
        try container.encode(mappings, forKey: .mappings)
        if !gestures.isEmpty { try container.encode(gestures, forKey: .gestures) }
        if !applications.isEmpty { try container.encode(applications, forKey: .applications) }
    }

    var isBase: Bool { trigger == nil }
}

struct Profile: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var layers: [Layer]
    var tapThresholdMilliseconds: Int

    init(
        id: UUID = UUID(),
        name: String,
        layers: [Layer],
        tapThresholdMilliseconds: Int = 200
    ) {
        self.id = id
        self.name = name
        self.layers = layers
        self.tapThresholdMilliseconds = tapThresholdMilliseconds
    }

    func copy(named newName: String) -> Profile {
        var newIDs: [UUID: UUID] = [:]
        for layer in layers { newIDs[layer.id] = UUID() }

        return Profile(
            id: UUID(), name: newName,
            layers: layers.map { layer in
                var copy = layer
                copy.id = newIDs[layer.id]!
                copy.tapAction = copy.tapAction?.remappingLayerIDs(newIDs)
                copy.gestures = copy.gestures.mapValues { $0.remappingLayerIDs(newIDs) }
                copy.mappings = copy.mappings.mapValues { $0.remappingLayerIDs(newIDs) }
                copy.applications = copy.applications.mapValues { app in
                    ApplicationOverride(
                        name: app.name,
                        mappings: app.mappings.mapValues { $0.remappingLayerIDs(newIDs) },
                        gestures: app.gestures.mapValues { $0.remappingLayerIDs(newIDs) })
                }
                return copy
            },
            tapThresholdMilliseconds: tapThresholdMilliseconds)
    }

    var hasGestures: Bool {
        layers.contains {
            !$0.gestures.isEmpty || $0.applications.values.contains { !$0.gestures.isEmpty }
        }
    }

    static let maxTriggeredLayers = 6
    static let validTapThresholdMilliseconds = 80...500

    var baseLayer: Layer? { layers.first(where: \.isBase) }
    var triggeredLayers: [Layer] { layers.filter { !$0.isBase } }

    var canAddLayer: Bool { triggeredLayers.count < Self.maxTriggeredLayers }

    var requiresCapsLockRemap: Bool {
        layers.contains { layer in
            if layer.trigger?.key == .capsLock { return true }
            return ([layer.mappings] + layer.applications.values.map(\.mappings)).contains {
                $0.contains { source, mapping in
                    SourceKeyCatalog.key(named: source)?.code == KeyCode.capsLock
                        && mapping != .transparent
                }
            }
        }
    }

    var mappedSourceCodes: Set<UInt16> {
        layers.reduce(into: []) { $0.formUnion($1.mappedSourceCodes) }
    }

    func reservingLayers(for source: String) -> [Layer] {
        guard let code = SourceKeyCatalog.observedCode(for: source) else { return [] }
        return triggeredLayers.filter { $0.trigger?.key.observedKeyCode == code }
    }

    // These are assignment diagnostics, not structural errors. Older profiles
    // with unreachable mappings must still load, sync and support undo.
    var mappingConflicts: [MappingReservationConflict] {
        layers.flatMap { layer in
            let contexts: [(String?, [String: LayerMapping])] =
                [(nil, layer.mappings)]
                + layer.applications.keys.sorted().map { ($0, layer.applications[$0]!.mappings) }
            return contexts.flatMap { applicationID, mappings in
                mappings.keys.sorted().flatMap { source -> [MappingReservationConflict] in
                    guard let mapping = mappings[source], mapping != .transparent else { return [] }
                    return reservingLayers(for: source).map {
                        MappingReservationConflict(
                            source: source, mappingLayerID: layer.id, triggerLayerID: $0.id,
                            applicationID: applicationID, mapping: mapping)
                    }
                }
            }
        }
    }

    func newMappingConflict(comparedTo previous: Profile) -> MappingReservationConflict? {
        let existing = Set(previous.mappingConflicts)
        return mappingConflicts.first { !existing.contains($0) }
    }

    func validate() throws {
        let baseLayerCount = layers.filter(\.isBase).count
        guard baseLayerCount == 1 else {
            throw ProfileError.invalidBaseLayerCount(found: baseLayerCount)
        }

        let ids = layers.map(\.id)
        guard Set(ids).count == ids.count else {
            throw ProfileError.duplicateLayerIDs
        }

        let triggeredCount = triggeredLayers.count
        guard triggeredCount <= Self.maxTriggeredLayers else {
            throw ProfileError.tooManyLayers(found: triggeredCount)
        }

        guard Self.validTapThresholdMilliseconds.contains(tapThresholdMilliseconds) else {
            throw ProfileError.invalidTapThreshold(milliseconds: tapThresholdMilliseconds)
        }

        for layer in layers {
            if let trigger = layer.trigger, trigger.key.observedKeyCode == nil {
                throw ProfileError.unknownTriggerKey(layer: layer.name)
            }

            try validate(layer.tapAction, in: layer)

            let gestureMappings = [layer.gestures] + layer.applications.values.map(\.gestures)
            for (source, mapping) in gestureMappings.flatMap({ Array($0) }) {
                guard !layer.isBase, TrackpadGesture(rawValue: source) != nil else {
                    throw ProfileError.invalidActionTarget(layer: layer.name)
                }
                try validate(mapping.action, in: layer)
            }

            let allMappings = [layer.mappings] + layer.applications.values.map(\.mappings)
            for (source, action) in allMappings.flatMap({ Array($0) }) {
                guard SourceKeyCatalog.observedCode(for: source) != nil else {
                    throw ProfileError.unknownSourceKey(layer: layer.name, key: source)
                }
                if let binding = action.binding, binding.keyCode == nil {
                    throw ProfileError.unknownDestinationKey(
                        layer: layer.name, key: binding.key)
                }
                try validate(action.action, in: layer)
            }
        }
    }

    private func validate(_ action: Action?, in layer: Layer) throws {
        guard let action else { return }
        switch action {
        case let .macAction(destination):
            guard destination.isValid else {
                throw ProfileError.invalidActionTarget(layer: layer.name)
            }
        case let .sendKey(binding):
            guard binding.keyCode != nil else {
                throw ProfileError.unknownDestinationKey(
                    layer: layer.name, key: binding.key)
            }
        case let .toggleLayer(target), let .oneShotLayer(target):
            guard target == .current || targetLayerExists(target) else {
                throw ProfileError.invalidActionTarget(layer: layer.name)
            }
        }
    }

    private func targetLayerExists(_ target: LayerTarget) -> Bool {
        guard case let .layer(id) = target else { return true }
        return layers.contains { $0.id == id }
    }

    func conflicts() -> [(Layer, Layer)] {
        var found: [(Layer, Layer)] = []
        let triggered = triggeredLayers
        for (index, layer) in triggered.enumerated() {
            for other in triggered.dropFirst(index + 1)
            where layer.trigger == other.trigger {
                found.append((layer, other))
            }
        }
        return found
    }
}

struct MappingReservationConflict: Hashable {
    let source: String
    let mappingLayerID: UUID
    let triggerLayerID: UUID
    let applicationID: String?
    let mapping: LayerMapping

    func message(in profile: Profile) -> String {
        let key = TriggerKey(rawValue: source).displayName
        let mappingLayer = profile.layers.first { $0.id == mappingLayerID }
        let triggerLayer = profile.layers.first { $0.id == triggerLayerID }?.name ?? "Layer"
        let context =
            applicationID.flatMap { mappingLayer?.applications[$0]?.name }
            .map { " for \($0)" } ?? ""
        return
            "\(key) activates “\(triggerLayer)”. Clear its mapping in “\(mappingLayer?.name ?? "Layer")”\(context), or choose another trigger key."
    }
}

enum ProfileError: LocalizedError, Equatable {
    case tooManyLayers(found: Int)
    case invalidBaseLayerCount(found: Int)
    case duplicateLayerIDs
    case invalidTapThreshold(milliseconds: Int)
    case unknownTriggerKey(layer: String)
    case unknownSourceKey(layer: String, key: String)
    case unknownDestinationKey(layer: String, key: String)
    case invalidActionTarget(layer: String)

    var errorDescription: String? {
        switch self {
        case let .tooManyLayers(found):
            return """
                This profile has \(found) triggered layers. Profiles can have up to \
                \(Profile.maxTriggeredLayers).
                """
        case let .invalidBaseLayerCount(found):
            return "This profile needs exactly one base layer. It currently has \(found)."
        case .duplicateLayerIDs:
            return "This profile contains duplicate layers and cannot be imported."
        case .invalidTapThreshold:
            return "The tap window must be between 80 and 500 ms."
        case let .unknownTriggerKey(layer):
            return "Layer “\(layer)” has an unsupported trigger key."
        case let .unknownSourceKey(layer, key):
            return "Layer “\(layer)” uses an unsupported source key: \(key)."
        case let .unknownDestinationKey(layer, key):
            return "Layer “\(layer)” uses an unsupported destination key: \(key)."
        case let .invalidActionTarget(layer):
            return
                "Layer “\(layer)” has an invalid action target. Check its layer, app, file, link, or Shortcut mapping."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .tooManyLayers:
            return "Remove a layer or split this setup into more than one profile."
        case .invalidBaseLayerCount, .duplicateLayerIDs, .invalidTapThreshold,
            .unknownTriggerKey, .unknownSourceKey, .unknownDestinationKey,
            .invalidActionTarget:
            return "Use a profile exported by Tenuo, or fix the unsupported value and try again."
        }
    }
}
