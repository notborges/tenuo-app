import SwiftUI
import UniformTypeIdentifiers

struct LayersPage: View {
    @ObservedObject var model: AppModel
    @State private var selectedKey: String?

    var body: some View {
        HStack(spacing: 0) {
            canvas
            inspector
                .windowPanel()
                .padding(.trailing, DS.Metrics.windowInset)
                .padding(.vertical, DS.Metrics.windowInset)
        }
        .onChange(of: model.selectedApplicationID) { _, _ in selectedKey = nil }
        .onChange(of: model.selectedLayerID) { _, _ in selectedKey = nil }
        .background(escapeDeselects)

    }

    private var escapeDeselects: some View {
        Button("Deselect") { selectedKey = nil }
            .keyboardShortcut(.cancelAction)
            .disabled(selectedKey == nil)
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

                        KeyboardLayoutView(
                            mappings: model.selectedMappings,
                            inherited: model.inheritedMappings,
                            selected: selectedKey,
                            triggerName: model.selectedLayer.trigger?.displayLabel ?? "Base",
                            triggerKey: model.selectedLayer.trigger?.key
                        ) { key in
                            selectedKey = (selectedKey == key) ? nil : key
                        }
                        .frame(maxWidth: .infinity)

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
            .onTapGesture { selectedKey = nil }
            .accessibilityHidden(true)
    }

    private var applicationStrip: some View {
        ApplicationContextStrip(model: model)
    }

    private var header: some View {
        HStack(spacing: DS.Space.small) {
            Keycap(
                label: model.selectedLayer.isBase
                    ? "·" : (model.selectedLayer.trigger?.displayLabel ?? "·"),
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
        var parts = ["Hold \(trigger.displayLabel)"]
        if let tap = layer.tapAction {
            switch tap {
            case let .sendKey(binding):
                parts.append("tap sends \(binding.displayLabel)")
            case let .macAction(action):
                parts.append("tap: \(action.displayLabel)")
            case .toggleLayer:
                parts.append("tap toggles this layer")
            case .oneShotLayer:
                parts.append("tap uses this layer once")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var inventory: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.tight) {
                Text(model.selectedApplicationID == nil ? "Mappings" : "App overrides")
                    .sectionLabel()
                Text(countText)
                    .font(DS.Typography.mono)
                    .foregroundStyle(DS.Ink.tertiary)
                Spacer(minLength: 0)
            }

            if model.sortedMappings.isEmpty {
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
                            selectedKey = entry.source
                        } label: {
                            MappingRow(
                                source: KeyCatalog.label(
                                    for: KeyCatalog.code(for: entry.source) ?? 0),
                                destination: entry.action.displayLabel,
                                caption: Self.caption(for: entry.action),
                                macAction: entry.action.action?.macAction
                            )
                            .padding(6)
                            .background(
                                selectedKey == entry.source ? DS.Selection.fill : .clear,
                                in: RoundedRectangle(cornerRadius: DS.Radius.small)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(Self.caption(for: entry.action))
                    }
                }
                .padding(DS.Space.medium)
                .glassCard()
            }
        }
    }

    private var countText: String {
        let count = model.sortedMappings.count
        return "\(count) key\(count == 1 ? "" : "s")"
    }

    static func caption(for action: LayerMapping) -> String {
        guard let binding = action.binding else { return action.displayLabel }
        let symbols = Modifier.allCases
            .filter { binding.modifiers.contains($0) }
            .map(\.symbol)
            .joined()
        let spaced = binding.key
            .replacingOccurrences(
                of: "([a-z])([A-Z])", with: "$1 $2",
                options: .regularExpression
            )
            .capitalized
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
                    if let selectedKey {
                        KeyInspector(model: model, source: selectedKey)
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
            if let selectedKey {
                HStack(spacing: DS.Space.tight) {
                    Keycap(
                        label: KeyCatalog.label(for: KeyCatalog.code(for: selectedKey) ?? 0),
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
                        self.selectedKey = nil
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
        if let selectedKey { return model.selectedMappings[selectedKey] != nil }
        return !model.selectedLayer.isBase
    }

    @ViewBuilder
    private var destructiveAction: some View {
        if let selectedKey, model.selectedMappings[selectedKey] != nil {
            InspectorDestructiveButton(
                title: model.selectedApplicationID == nil ? "Clear mapping" : "Use Default"
            ) {
                model.selectedMappings.removeValue(forKey: selectedKey)
            }
        } else if selectedKey == nil, !model.selectedLayer.isBase {
            InspectorDestructiveButton(
                title: "Remove layer",
                confirm: removalConfirmation
            ) {
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

private struct KeyInspector: View {
    @ObservedObject var model: AppModel
    let source: String

    @State private var modifiers: Set<Modifier> = []
    @State private var output = MappingOutput.key

    private var current: LayerMapping? {
        model.selectedMappings[source] ?? model.inheritedMappings[source]
    }
    private var ordered: [Modifier] { Modifier.allCases.filter { modifiers.contains($0) } }

    var body: some View {
        let layerID = model.selectedLayer.id
        let applicationID = model.selectedApplicationID
        VStack(alignment: .leading, spacing: DS.Space.medium) {
            if let name = model.editingApplicationName {
                VStack(alignment: .leading, spacing: 6) {
                    Text(name).sectionLabel()
                    Text(
                        "Default: \(model.selectedLayer.mappings[source]?.displayLabel ?? "Normal key")"
                    )
                    .font(DS.Typography.label).foregroundStyle(DS.Ink.tertiary)
                    if model.selectedMappings[source] == nil && model.license.hasProAccess {
                        Text("Using Default. Choose an output to customize this key.")
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
                                model.selectedMappings[source] =
                                    .action(.sendKey(KeyBinding(key: $0, modifiers: ordered)))
                            }
                        ),
                        columns: 5,
                        height: nil
                    )
                }
            } else {
                MacActionEditor(
                    output: output, current: current, hasPro: model.canUse(.macAction),
                    activate: { model.onOpenProSettings?() }
                ) { action in
                    guard model.canUse(.macAction), model.selectedLayer.id == layerID,
                        model.selectedApplicationID == applicationID
                    else { return }
                    model.selectedMappings[source] = .action(.macAction(action))
                }
                .id(output)
            }
        }
        .onAppear {
            modifiers = Set(current?.binding?.modifiers ?? [])
            output = MappingOutput(mapping: current)
        }
        .onChange(of: source) { _, newSource in
            modifiers = Set(model.selectedMappings[newSource]?.binding?.modifiers ?? [])
        }
    }

    private func reassignIfMapped() {
        guard let key = current?.binding?.key else { return }
        model.selectedMappings[source] =
            .action(.sendKey(KeyBinding(key: key, modifiers: ordered)))
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
                            Text(action.displayLabel).padding(12)
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
        var sentence = "Hold \(trigger.wrappedValue.displayLabel) to activate this layer."
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
                    title: "One key, different jobs",
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
