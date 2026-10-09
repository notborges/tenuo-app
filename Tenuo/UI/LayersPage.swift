import SwiftUI
import UniformTypeIdentifiers

struct LayersPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var keyboard = KeyboardPresentation.shared
    @State private var choosingSource = false
    private var selectedKey: String? { model.selectedKey }

    var body: some View {
        HStack(spacing: 0) {
            canvas
            inspector
                .windowPanel()
                .padding(.trailing, DS.Metrics.windowInset)
                .padding(.vertical, DS.Metrics.windowInset)
        }
        .onChange(of: model.profile.id) { _, _ in model.selectedKeys = [] }

        .background(escapeDeselects)

    }

    private var escapeDeselects: some View {
        Button("Deselect") {
            model.selectedKeys = []
            model.selectedGesture = nil
        }
        .keyboardShortcut(.cancelAction)
        .disabled(model.selectedKeys.isEmpty && model.selectedGesture == nil)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var rule: some View {
        Rectangle().fill(DS.Line.hairline).frame(height: 1)
    }

    private var canvas: some View {
        VStack(spacing: 0) {
            ColumnHeader { header }
                .padding(.top, DS.Metrics.windowInset)
                .padding(.horizontal, DS.Space.large)

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.large) {
                        applicationStrip

                        if let conflict = model.profile.mappingConflicts.first {
                            reservationDiagnostic(conflict)
                        }

                        KeyboardLayoutView(
                            mappings: model.selectedMappings,
                            inherited: model.inheritedMappings,
                            selectedKeys: model.selectedKeys,
                            editingModel: model,
                            triggerName: model.selectedLayer.trigger?.keyboardLabel ?? "Base",
                            triggerKey: model.selectedLayer.trigger?.key
                        ) { key in
                            model.selectKey(key)
                        }
                        .frame(maxWidth: .infinity)

                        if !model.selectedLayer.isBase {
                            TrackpadView(
                                mappings: model.selectedGestures,
                                inherited: model.inheritedGestures,
                                selected: model.selectedGesture,
                                hasPro: model.license.hasProAccess,
                                onSelect: model.selectGesture
                            )
                            .frame(width: min(320, (proxy.size.width - DS.Space.large * 2) * 0.46))
                            .frame(maxWidth: .infinity)
                        }

                        if let trigger = model.selectedLayer.trigger,
                            case let .key(name) = trigger.key,
                            !KeyboardGeometry.visibleKeys(for: keyboard.shape).contains(name)
                        {
                            Text(
                                "The layer trigger is not shown on this keyboard. Its assignment is preserved."
                            )
                            .font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                        }
                        inventory
                    }
                    .padding(.horizontal, DS.Space.large)
                    .padding(.vertical, DS.Space.large)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .background(deselectionSurface)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            DS.Surface.window
            deselectionSurface
        }
    }

    // A background hit target lets key and mapping buttons handle their own clicks.
    // It is confined to the canvas so editing in the inspector keeps the selection.
    private var deselectionSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                model.selectedKeys = []
                model.selectedGesture = nil
            }
            .accessibilityHidden(true)
    }

    private var applicationStrip: some View {
        ApplicationContextStrip(model: model)
    }

    private var header: some View {
        HStack(spacing: DS.Space.small) {
            Keycap(
                label: model.selectedLayer.isBase
                    ? "·" : (model.selectedLayer.trigger?.keyboardLabel ?? "·"),
                width: 40, height: 40, legendSize: 13,
                isRinged: !model.selectedLayer.isBase,
                hasIndicator: model.selectedLayer.trigger?.key == .capsLock)

            VStack(alignment: .leading, spacing: 1) {
                LayerNameField(
                    text: Binding(
                        get: { model.selectedLayer.name },
                        set: { model.selectedLayer.name = $0 }),
                    isEditable: !model.selectedLayer.isBase
                )
                Text(sentence)
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Ink.tertiary)
                    .lineLimit(1)
                    .padding(.leading, 6)
            }

            Spacer(minLength: 0)
        }
    }

    private var sentence: String {
        let layer = model.selectedLayer
        guard let trigger = layer.trigger else {
            return "Always active · used when no other layer is active"
        }
        var parts = ["Hold \(trigger.keyboardLabel)"]
        if let tap = layer.tapAction {
            switch tap {
            case let .sendKey(binding):
                parts.append("tap sends \(binding.keyboardLabel)")
            case let .macAction(action):
                parts.append("tap: \(action.keyboardLabel)")
            case .toggleLayer:
                parts.append("tap toggles this layer")
            case .oneShotLayer:
                parts.append("tap uses this layer once")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var inventory: some View {
        let visibleKeys = KeyboardGeometry.visibleKeys(for: keyboard.shape)
        return VStack(alignment: .leading, spacing: DS.Space.tight) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.tight) {
                Text(model.selectedApplicationID == nil ? "Mappings" : "App overrides")
                    .sectionLabel()
                Text(countText)
                    .font(DS.Typography.mono)
                    .foregroundStyle(DS.Ink.tertiary)
                Spacer(minLength: 0)
                Button {
                    choosingSource = true
                } label: {
                    Label("Add mapping", systemImage: "plus")
                        .font(DS.Typography.label)
                        .padding(.horizontal, DS.Space.tight)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ApplicationControlStyle())
                .foregroundStyle(DS.Ink.secondary)
                .help("Choose a key, including keys outside the keyboard view")
                .popover(isPresented: $choosingSource) {
                    KeyChooser(
                        selection: Binding(
                            get: { model.selectedKey ?? "" },
                            set: {
                                model.selectKey($0); choosingSource = false
                            }),
                        isSource: true
                    )
                    .frame(width: 300).padding(DS.Space.small)
                }
            }

            if model.sortedMappings.isEmpty && model.selectedGestures.isEmpty {
                Text(
                    model.selectedApplicationID == nil
                        ? "No mappings yet. Select a key to add one."
                        : "Everything uses Default. Select a key to customize it for this app."
                )
                .font(DS.Typography.body)
                .foregroundStyle(DS.Ink.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.medium)
                .glassCard()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: DS.Space.medium)],
                    alignment: .leading,
                    spacing: DS.Space.tight
                ) {
                    ForEach(model.sortedMappings, id: \.source) { entry in
                        Button {
                            model.selectKey(entry.source)
                        } label: {
                            MappingRow(
                                source: KeyboardPresentation.shared.label(
                                    for: entry.source),
                                destination: entry.action.keyboardLabel,
                                caption: Self.caption(for: entry.action)
                                    + (visibleKeys.contains(entry.source)
                                        ? "" : " · Not shown on this keyboard"),
                                macAction: entry.action.action?.macAction
                            )
                            .padding(6)
                            .background(
                                model.selectedKeys.contains(entry.source)
                                    ? DS.Selection.fill : .clear,
                                in: RoundedRectangle(cornerRadius: DS.Radius.small)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { MappingSelectionMenu(model: model, key: entry.source) }
                        .accessibilityAddTraits(
                            model.selectedKeys.contains(entry.source) ? .isSelected : []
                        )
                        .help(Self.caption(for: entry.action))
                    }
                    ForEach(TrackpadGesture.allCases, id: \.self) { gesture in
                        if let mapping = model.selectedGestures[gesture.rawValue] {
                            Button {
                                model.selectGesture(gesture)
                            } label: {
                                HStack(spacing: DS.Space.small) {
                                    Image(systemName: gesture.symbol)
                                        .frame(width: 28, height: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mapping.keyboardLabel).font(DS.Typography.body)
                                            .lineLimit(1)
                                        Text(gesture.title).font(DS.Typography.footnote)
                                            .foregroundStyle(DS.Ink.tertiary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(6)
                                .background(
                                    model.selectedGesture == gesture ? DS.Selection.fill : .clear,
                                    in: RoundedRectangle(cornerRadius: DS.Radius.small)
                                )
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(DS.Space.medium)
                .glassCard()
            }
        }
    }

    private var countText: String {
        let count = model.sortedMappings.count
        let gestures = model.selectedGestures.count
        let keys = "\(count) key\(count == 1 ? "" : "s")"
        return gestures == 0 ? keys : "\(keys) · \(gestures) gesture\(gestures == 1 ? "" : "s")"
    }

    private func reservationDiagnostic(_ conflict: MappingReservationConflict) -> some View {
        HStack(alignment: .top, spacing: DS.Space.small) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(DS.Ink.secondary)
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text("Mapping uses a layer trigger").font(DS.Typography.body.weight(.medium))
                Text(conflict.message(in: model.profile))
                    .font(DS.Typography.label).foregroundStyle(DS.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Review mapping") {
                    model.selectedLayerID = conflict.mappingLayerID
                    model.selectedApplicationID = conflict.applicationID
                    model.selectedKeys = [conflict.source]
                }
                .buttonStyle(.plain)
                .font(DS.Typography.label)
                .foregroundStyle(DS.Selection.solid)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.medium)
        .glassCard()
    }

    static func caption(for action: LayerMapping) -> String {
        guard let binding = action.binding else { return action.keyboardLabel }
        let symbols = Modifier.allCases
            .filter { binding.modifiers.contains($0) }
            .map(\.symbol)
            .joined()
        let spaced =
            binding.modifiers.contains(.command)
            ? KeyboardPresentation.shared.shortcutKeyLabel(for: binding)
            : KeyboardPresentation.shared.displayName(for: binding.key)
        return symbols.isEmpty ? spaced : "\(symbols) \(spaced)"
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            ColumnHeader { inspectorTitle }
                .padding(.bottom, DS.Space.small)
                .padding(.horizontal, DS.Space.medium)

            rule

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.medium) {
                    if let gesture = model.selectedGesture {
                        if model.license.hasProAccess {
                            MappingInspector(
                                model: model, source: gesture.rawValue, isGesture: true
                            )
                            .id(
                                "gesture/\(gesture.rawValue)/\(model.selectedApplicationID ?? "default")"
                            )
                        } else {
                            ProFeaturePrompt(
                                title: "Trackpad layers",
                                detail:
                                    "Assign swipes to shortcuts and Mac actions alongside your keyboard mappings with Tenuo Pro.",
                                visual: "trackpad"
                            ) { model.onOpenProSettings?() }
                        }
                    } else if model.selectedKeys.count > 1 {
                        MappingGroupInspector(model: model)
                    } else if let selectedKey {
                        MappingInspector(model: model, source: selectedKey)
                            .id("\(selectedKey)/\(model.selectedApplicationID ?? "default")")
                    } else {
                        LayerInspector(model: model)
                    }
                }
                .padding(DS.Space.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            if hasDestructiveAction {
                rule
                destructiveAction
                    .padding(.horizontal, DS.Metrics.panelInset)
                    .frame(height: DS.Metrics.footerHeight)
            }
        }
        .frame(width: DS.Metrics.inspectorWidth)
        .frame(maxHeight: .infinity)
        .background(DS.Surface.sidebar)
    }

    private var inspectorTitle: some View {
        Group {
            if let gesture = model.selectedGesture {
                HStack(spacing: DS.Space.small) {
                    Image(systemName: gesture.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Two fingers").sectionLabel()
                        Text(gesture.title).font(DS.Typography.title)
                    }
                    Spacer()
                    Button {
                        model.selectedGesture = nil
                    } label: {
                        Image(systemName: "xmark").foregroundStyle(DS.Ink.tertiary)
                    }.buttonStyle(.plain).tooltip("Deselect")
                }
            } else if model.selectedKeys.count > 1 {
                HStack {
                    Text("\(model.selectedKeys.count) keys selected")
                        .font(DS.Typography.title)
                    Spacer()
                    Button {
                        model.selectedKeys = []
                    } label: {
                        Image(systemName: "xmark").foregroundStyle(DS.Ink.tertiary)
                    }
                    .buttonStyle(.plain)
                    .tooltip("Deselect")
                }
            } else if let selectedKey {
                HStack(spacing: DS.Space.tight) {
                    Keycap(
                        label: KeyboardPresentation.shared.label(
                            for: selectedKey),
                        width: 30, height: 30, legendSize: 11,
                        isLit: model.selectedMappings[selectedKey] != nil)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Key").sectionLabel()
                        Text(
                            (model.selectedMappings[selectedKey]
                                ?? model.inheritedMappings[selectedKey])
                                .map(Self.caption(for:)) ?? "Unmapped"
                        )
                        .font(DS.Typography.title)
                        .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Button {
                        model.selectedKeys = []
                    } label: {
                        Image(systemName: "xmark").font(
                            .system(size: DS.Icon.small, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.Ink.tertiary)
                    .tooltip("Deselect")
                }
            } else {
                Text(model.selectedLayer.isBase ? "Base layer" : "Layer")
                    .font(DS.Typography.title)
            }
        }
    }

    private var hasDestructiveAction: Bool {
        if let gesture = model.selectedGesture {
            return model.license.hasProAccess && model.selectedGestures[gesture.rawValue] != nil
        }
        return model.canClearMappings || (model.selectedKeys.isEmpty && !model.selectedLayer.isBase)
    }

    @ViewBuilder
    private var destructiveAction: some View {
        if let gesture = model.selectedGesture {
            InspectorDestructiveButton(
                title: model.selectedApplicationID == nil ? "Clear gesture" : "Use Default"
            ) { model.selectedGestures[gesture.rawValue] = nil }
        } else if model.canClearMappings {
            InspectorDestructiveButton(
                title: model.selectedApplicationID == nil
                    ? (model.selectedKeys.count == 1 ? "Clear mapping" : "Clear mappings")
                    : "Use Default"
            ) { model.clearMappings() }
        } else if model.selectedKeys.isEmpty, !model.selectedLayer.isBase {
            InspectorDestructiveButton(title: "Remove layer", confirm: removalConfirmation) {
                model.removeSelectedLayer()
            }
        }
    }

    private var removalConfirmation: String {
        let layer = model.selectedLayer
        guard !layer.mappings.isEmpty else { return "Remove “\(layer.name)”?" }
        let mappingWord = layer.mappings.count == 1 ? "mapping" : "mappings"
        return "Remove “\(layer.name)” and its \(layer.mappings.count) \(mappingWord)?"
    }
}

private struct LayerNameField: View {
    @Binding var text: String
    var isEditable: Bool

    @State private var isEditing = false
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("Name this layer", text: $text)
                    .textFieldStyle(.plain)
                    .font(DS.Typography.display)
                    .focused($isFocused)
                    .onAppear { isFocused = true }
                    .onSubmit { isEditing = false }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { isEditing = false }
                    }
            } else {
                HStack(spacing: 5) {
                    Text(text.isEmpty ? "Name this layer" : text)
                        .font(DS.Typography.display)
                        .foregroundStyle(text.isEmpty ? DS.Ink.tertiary : DS.Ink.primary)
                        .lineLimit(1)
                    if isEditable {
                        Image(systemName: "pencil")
                            .font(.system(size: DS.Icon.small))
                            .foregroundStyle(DS.Ink.tertiary)
                            .opacity(isHovering ? 1 : 0)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                .fill(isEditing || (isHovering && isEditable) ? DS.Surface.raised : .clear)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { if isEditable { isEditing = true } }
        .animation(DS.Motion.fill, value: isEditing)
        .animation(DS.Motion.hover, value: isHovering)
    }
}

private struct MappingInspector: View {
    @ObservedObject var model: AppModel
    let source: String
    var isGesture = false

    private func assign(_ mapping: LayerMapping) {
        if isGesture {
            model.selectedGestures[source] = mapping
        } else {
            model.selectedMappings[source] = mapping
        }
    }

    @State private var modifiers: Set<Modifier> = []
    @State private var output = MappingOutput.key

    private var current: LayerMapping? {
        isGesture
            ? (model.selectedGestures[source] ?? model.inheritedGestures[source])
            : (model.selectedMappings[source] ?? model.inheritedMappings[source])
    }
    private var ordered: [Modifier] { Modifier.allCases.filter { modifiers.contains($0) } }

    var body: some View {
        let layerID = model.selectedLayer.id
        let applicationID = model.selectedApplicationID
        VStack(alignment: .leading, spacing: DS.Space.medium) {
            if !isGesture, let message = model.reservationMessage(for: source) {
                reservedCard(message)
            } else {
                editor(layerID: layerID, applicationID: applicationID)
            }
        }
        .onAppear {
            modifiers = Set(current?.binding?.modifiers ?? [])
            output = MappingOutput(mapping: current)
        }
        .onChange(of: current) { _, mapping in
            modifiers = Set(mapping?.binding?.modifiers ?? [])
            output = MappingOutput(mapping: mapping)
        }
    }

    private func reservedCard(_ message: String) -> some View {
        InspectorCard(title: "Layer trigger") {
            VStack(alignment: .leading, spacing: DS.Space.small) {
                Text(message)
                    .font(DS.Typography.body).foregroundStyle(DS.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let current, current != .transparent {
                    Text(
                        "Saved mapping: \(current.keyboardLabel). This mapping cannot run while the key is a layer trigger."
                    )
                    .font(DS.Typography.label).foregroundStyle(DS.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Button("Edit trigger") {
                    if let layer = model.profile.reservingLayers(for: source).first {
                        model.selectedLayerID = layer.id
                    }
                }
                .buttonStyle(RoundedActionStyle())
            }
            .padding(Inspector.rowInset)
        }
    }

    @ViewBuilder
    private func editor(layerID: UUID, applicationID: String?) -> some View {
        if isGesture {
            Text(
                "Swipe with two fingers while the layer is active. Unassigned directions scroll normally."
            )
            .font(DS.Typography.label).foregroundStyle(DS.Ink.secondary)
        }
        if let name = model.editingApplicationName {
            VStack(alignment: .leading, spacing: 6) {
                Text(name).sectionLabel()
                Text(
                    "Default: \((isGesture ? model.selectedLayer.gestures[source] : model.selectedLayer.mappings[source])?.keyboardLabel ?? (isGesture ? "Unassigned" : "Normal key"))"
                )
                .font(DS.Typography.label).foregroundStyle(DS.Ink.tertiary)
                if (isGesture
                    ? model.selectedGestures[source] : model.selectedMappings[source])
                    == nil && model.license.hasProAccess
                {
                    Text(
                        isGesture
                            ? "Using Default. Choose an output to customize this swipe."
                            : "Using Default. Choose an output to customize this key."
                    )
                    .font(DS.Typography.label).foregroundStyle(DS.Ink.secondary)
                }
            }
        }
        MappingOutputPicker(selection: $output, hasPro: model.canUse(.macAction))
        if output == .key {
            if applicationID != nil && !model.license.hasProAccess {
                ProFeaturePrompt(
                    title: "App overrides are inactive",
                    detail:
                        "Your saved overrides are preserved. Activate Tenuo Pro to use or edit them; this app currently uses Default."
                ) {
                    model.onOpenProSettings?()
                }
            } else {
                InspectorCard(title: "Output") {
                    InspectorWideRow(label: "Modifiers", divider: false) {
                        HStack(spacing: 5) {
                            ForEach(Modifier.allCases, id: \.self) { modifier in
                                CycleChip(
                                    symbol: modifier.symbol,
                                    isOn: modifiers.contains(modifier)
                                ) {
                                    if modifiers.contains(modifier) {
                                        modifiers.remove(modifier)
                                    } else {
                                        modifiers.insert(modifier)
                                    }
                                    reassignIfMapped()
                                }
                            }
                        }
                    }
                }

                KeyChooser(
                    selection: Binding(
                        get: { current?.binding?.key ?? "" },
                        set: {
                            assign(
                                .action(.sendKey(KeyBinding(key: $0, modifiers: ordered))))
                        }
                    ),
                    columns: 5,
                    height: nil
                )
            }
        } else {
            MacActionEditor(
                output: output, current: current, hasPro: model.canUse(.macAction),
                assignmentLabel: isGesture
                    ? "Assigned to this gesture" : "Assigned to this key",
                activate: { model.onOpenProSettings?() }
            ) { action in
                guard model.canUse(.macAction), model.selectedLayer.id == layerID,
                    model.selectedApplicationID == applicationID,
                    !isGesture || model.selectedGesture?.rawValue == source
                else { return }
                assign(.action(.macAction(action)))
            }
            .id(output)
        }
    }

    private func reassignIfMapped() {
        guard let key = current?.binding?.key else { return }
        assign(.action(.sendKey(KeyBinding(key: key, modifiers: ordered))))
    }
}

private enum TapActionChoice: String, CaseIterable, Hashable {
    case none
    case macAction
    case sendKey
    case toggleLayer
    case oneShotLayer

    var title: String {
        switch self {
        case .none: return "Do nothing"
        case .macAction: return "Mac action"
        case .sendKey: return "Send key"
        case .toggleLayer: return "Toggle layer"
        case .oneShotLayer: return "One-shot layer"
        }
    }

    var kind: ActionKind? {
        switch self {
        case .none: return nil
        case .macAction: return .macAction
        case .sendKey: return .sendKey
        case .toggleLayer: return .toggleLayer
        case .oneShotLayer: return .oneShotLayer
        }
    }

    init(action: Action?) {
        switch action {
        case nil: self = .none
        case .sendKey: self = .sendKey
        case .toggleLayer: self = .toggleLayer
        case .oneShotLayer: self = .oneShotLayer
        case .macAction: self = .macAction
        }
    }
}

private struct LayerInspector: View {
    @ObservedObject var model: AppModel

    private var trigger: Binding<LayerTrigger> {
        Binding(
            get: { model.selectedLayer.trigger ?? LayerTrigger() },
            set: { model.selectedLayer.trigger = $0 })
    }

    private var tapChoice: TapActionChoice {
        TapActionChoice(action: model.selectedLayer.tapAction)
    }

    private var availableTapChoices: [TapActionChoice] {
        TapActionChoice.allCases.filter { choice in
            if choice == .macAction { return tapChoice == .macAction }
            guard let kind = choice.kind else { return true }
            return model.canUse(kind)
        }
    }

    private var hasTapDetails: Bool { model.selectedLayer.tapAction?.binding != nil }

    var body: some View {
        if model.selectedLayer.isBase {
            Text(
                "Always active. Its mappings apply when no higher layer handles a key; other keys behave normally."
            )
            .font(DS.Typography.body)
            .foregroundStyle(DS.Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: DS.Space.medium) {
                InspectorCard(title: "Trigger", footer: chordSentence) {
                    InspectorRow(label: "Key") {
                        TriggerKeyField(trigger: trigger.key)
                    }
                    InspectorWideRow(label: "Modifiers", divider: false) {
                        ModifierChips(trigger: trigger)
                    }
                }

                InspectorCard(
                    title: "Other keys",
                    footer: model.selectedLayer.outputMode.injectsHyper
                        ? "Without a mapping in an active layer, Q sends ⌃⌥⌘⇧Q. Hyper holds Control, Option, Command and Shift together."
                        : "Without a mapping in an active layer, keys work normally. Another active layer’s Hyper setting can still apply."
                ) {
                    InspectorRow(label: "Send", divider: false) {
                        InspectorPicker(
                            title: model.selectedLayer.outputMode.displayName,
                            selection: Binding(
                                get: {
                                    switch model.selectedLayer.outputMode {
                                    case .layer: return .layer
                                    case .inject, .injectAndLayer: return .injectAndLayer
                                    }
                                },
                                set: { model.selectedLayer.outputMode = $0 }
                            )
                        ) {
                            ForEach(
                                [LayerOutputMode.layer, .injectAndLayer],
                                id: \.self
                            ) {
                                Text($0.displayName).tag($0)
                            }
                        }
                    }
                }

                InspectorCard(title: "Tap action") {
                    InspectorRow(label: "On tap", divider: hasTapDetails) {
                        InspectorPicker(
                            title: tapChoice.title,
                            selection: Binding(
                                get: { tapChoice },
                                set: { setTapAction($0) }
                            )
                        ) {
                            ForEach(availableTapChoices, id: \.self) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                    }

                    if let tap = model.selectedLayer.tapAction {
                        switch tap {
                        case let .sendKey(binding):
                            InspectorRow(label: "Sends", divider: false) {
                                CompactKeyField(
                                    selection: Binding(
                                        get: { binding.key },
                                        set: {
                                            model.selectedLayer.tapAction = .sendKey(
                                                KeyBinding(key: $0, modifiers: binding.modifiers))
                                        }
                                    ))
                            }
                        case let .macAction(action):
                            Text(action.keyboardLabel).padding(12)
                        case .toggleLayer, .oneShotLayer:
                            EmptyView()
                        }
                    }
                }
            }
        }
    }

    private func setTapAction(_ choice: TapActionChoice) {
        guard choice.kind.map({ model.canUse($0) }) ?? true else { return }

        let current = model.selectedLayer.tapAction
        switch choice {
        case .macAction: break
        case .none:
            model.selectedLayer.tapAction = nil
        case .sendKey:
            model.selectedLayer.tapAction = .sendKey(
                current?.binding ?? KeyBinding(key: "escape"))
        case .toggleLayer:
            model.selectedLayer.tapAction = .toggleLayer(.current)
        case .oneShotLayer:
            model.selectedLayer.tapAction = .oneShotLayer(.current)
        }
    }

    private var chordSentence: String {
        var sentence = "Hold \(trigger.wrappedValue.keyboardLabel) to activate this layer."
        if trigger.wrappedValue.key.isConsumedWhileHeld,
            model.selectedLayer.tapAction == nil
        {
            sentence +=
                " This key is consumed while held. Add a tap action if you want it to do something when tapped."
        }
        return sentence
    }
}

private struct ApplicationContextStrip: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsPicker = false
    @State private var showsProInfo = false
    @State private var removalID: String?

    private var applications: [String] {
        model.selectedLayer.applications.keys.sorted {
            (model.selectedLayer.applications[$0]?.name ?? $0)
                .localizedStandardCompare(model.selectedLayer.applications[$1]?.name ?? $1)
                == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.small) {
            strip
            HStack(spacing: 6) {
                if let name = model.editingApplicationName {
                    Text("Editing \(name) · Unchanged keys use Default")
                } else {
                    Text("Default mappings apply in every app")
                }
                Spacer(minLength: 8)
                if let app = model.liveApplication, let name = app.localizedName {
                    if let icon = app.icon {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                            .accessibilityHidden(true)
                    }
                    Text("Active in \(name)").lineLimit(1)
                }
            }
            .font(DS.Typography.footnote)
            .foregroundStyle(DS.Ink.tertiary)
        }
        .sheet(isPresented: $showsPicker) {
            ApplicationPicker { model.addApplication(url: $0) }
        }
        .alert(
            "Remove app overrides?",
            isPresented: Binding(
                get: { removalID != nil }, set: { if !$0 { removalID = nil } })
        ) {
            Button("Remove", role: .destructive) {
                if let id = removalID {
                    model.selectedLayer.applications.removeValue(forKey: id)
                    if model.selectedApplicationID == id { model.selectedApplicationID = nil }
                }
                removalID = nil
            }
            Button("Cancel", role: .cancel) { removalID = nil }
        } message: {
            Text("This app will use the default mappings for this layer.")
        }
    }

    private var strip: some View {
        HStack(spacing: 6) {
            contextButton(id: nil, name: "Default")
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(applications, id: \.self) { id in
                            contextButton(
                                id: id, name: model.selectedLayer.applications[id]?.name ?? id
                            )
                            .id(id)
                            .contextMenu {
                                Button("Remove app overrides…", role: .destructive) {
                                    removalID = id
                                }
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: 44)
                .onChange(of: model.selectedApplicationID, initial: true) { _, id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        proxy.scrollTo(id)
                    }
                }
                .onChange(of: model.selectedLayerID) { _, _ in
                    if let id = model.selectedApplicationID ?? applications.first {
                        proxy.scrollTo(id, anchor: .leading)
                    }
                }
                .accessibilityLabel("Application contexts")
            }
            Button {
                if model.license.hasProAccess { showsPicker = true } else { showsProInfo = true }
            } label: {
                HStack(spacing: 5) {
                    Label("Add app", systemImage: "plus")
                    if !model.license.hasProAccess {
                        Text("Pro").font(.system(size: 9, weight: .medium))
                    }
                }
                .font(DS.Typography.label)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.small))
            }
            .buttonStyle(ApplicationControlStyle()).foregroundStyle(DS.Ink.secondary)
            .fixedSize()
            .popover(isPresented: $showsProInfo) {
                ProFeaturePrompt(
                    title: "App-specific mappings",
                    detail:
                        "Give the same key a different job in Safari, Finder, or any other app.",
                    visual: "app.dashed", presentation: .popover
                ) {
                    showsProInfo = false
                    model.onOpenProSettings?()
                }
                .frame(width: 300)
            }
        }
    }

    private func contextButton(id: String?, name: String) -> some View {
        ApplicationContextButton(
            id: id, name: name, isSelected: model.selectedApplicationID == id
        ) {
            model.selectedApplicationID = id
        }
    }
}
