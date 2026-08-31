import SwiftUI

struct LayersPage: View {
    @ObservedObject var model: AppModel
    @State private var selectedKey: String?

    var body: some View {
        HStack(spacing: 0) {
            canvas
            ColumnDivider()
            inspector
        }
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
                .padding(.horizontal, DS.Space.large)

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.large) {
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
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Surface.window)
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
            return "Always active · applies when no chord is held"
        }
        var parts = ["Hold \(trigger.displayLabel)"]
        if let tap = layer.tapAction {
            parts.append("tap for \(tap.displayLabel)")
        }
        switch layer.holdMode {
        case .inject: parts.append("held keys send ⌃⌥⌘⇧")
        case .layer: parts.append("unmapped keys pass through")
        case .injectAndLayer: parts.append("unmapped keys send ⌃⌥⌘⇧")
        }
        return parts.joined(separator: " · ")
    }

    private var inventory: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.tight) {
                Text("Mappings").sectionLabel()
                Text(countText)
                    .font(DS.Typography.mono)
                    .foregroundStyle(DS.Ink.tertiary)
                Spacer(minLength: 0)
            }

            if model.sortedMappings.isEmpty {
                Text("No mappings yet. Click any key to bind it.")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Ink.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.medium)
                    .glassCard()
            } else {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: DS.Space.large),
                        count: 3),
                    alignment: .leading,
                    spacing: DS.Space.tight
                ) {
                    ForEach(model.sortedMappings, id: \.source) { entry in
                        MappingRow(
                            source: KeyCatalog.label(for: KeyCatalog.code(for: entry.source) ?? 0),
                            destination: entry.action.displayLabel,
                            caption: Self.caption(for: entry.action)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedKey = entry.source }
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

    static func caption(for action: KeyAction) -> String {
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
                .padding(.horizontal, DS.Space.medium)

            rule

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.medium) {
                    if let selectedKey {
                        KeyInspector(model: model, source: selectedKey)
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
                destructiveAction.padding(DS.Space.medium)
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
                        isLit: model.selectedLayer.mappings[selectedKey] != nil)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Key").sectionLabel()
                        Text(
                            model.selectedLayer.mappings[selectedKey]
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
                Text(model.selectedLayer.isBase ? "Base Layer" : "Layer")
                    .font(DS.Typography.title)
            }
        }
    }

    private var hasDestructiveAction: Bool {
        if let selectedKey { return model.selectedLayer.mappings[selectedKey] != nil }
        return !model.selectedLayer.isBase
    }

    @ViewBuilder
    private var destructiveAction: some View {
        if let selectedKey, model.selectedLayer.mappings[selectedKey] != nil {
            InspectorDestructiveButton(title: "Clear Mapping") {
                model.selectedLayer.mappings.removeValue(forKey: selectedKey)
            }
        } else if selectedKey == nil, !model.selectedLayer.isBase {
            InspectorDestructiveButton(
                title: "Remove Layer",
                confirm:
                    "Remove “\(model.selectedLayer.name)” and its \(model.selectedLayer.mappings.count) mappings?"
            ) {
                model.removeSelectedLayer()
            }
        }
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
                TextField("Layer name", text: $text)
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
                    Text(text.isEmpty ? "Layer name" : text)
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

    private var current: KeyAction? { model.selectedLayer.mappings[source] }
    private var ordered: [Modifier] { Modifier.allCases.filter { modifiers.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.medium) {
            InspectorCard(title: "Sends with") {
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
                        model.selectedLayer.mappings[source] =
                            .key(KeyBinding(key: $0, modifiers: ordered))
                    }
                ),
                columns: 5,
                height: nil
            )
        }
        .onAppear { modifiers = Set(current?.binding?.modifiers ?? []) }
        .onChange(of: source) { _, newSource in
            modifiers = Set(model.selectedLayer.mappings[newSource]?.binding?.modifiers ?? [])
        }
    }

    private func reassignIfMapped() {
        guard let key = current?.binding?.key else { return }
        model.selectedLayer.mappings[source] = .key(KeyBinding(key: key, modifiers: ordered))
    }
}

private struct LayerInspector: View {
    @ObservedObject var model: AppModel

    private var trigger: Binding<LayerTrigger> {
        Binding(
            get: { model.selectedLayer.trigger ?? LayerTrigger() },
            set: { model.selectedLayer.trigger = $0 })
    }

    private var sendsKeyOnTap: Bool { model.selectedLayer.tapAction != nil }

    var body: some View {
        if model.selectedLayer.isBase {
            Text(
                "Always active. Keys mapped here apply when no chord is held, and every other layer falls through to it."
            )
            .font(DS.Typography.body)
            .foregroundStyle(DS.Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: DS.Space.medium) {
                InspectorCard(title: "Trigger", footer: chordSentence) {
                    InspectorRow(label: "Hold") {
                        TriggerKeyField(trigger: trigger.key)
                    }
                    InspectorWideRow(label: "Together with", divider: false) {
                        ModifierChips(trigger: trigger)
                    }
                }

                InspectorCard(
                    title: "Behaviour",
                    footer: model.selectedLayer.holdMode.summary
                ) {
                    InspectorRow(label: "Unmapped keys") {
                        Picker(
                            "",
                            selection: Binding(
                                get: { model.selectedLayer.holdMode },
                                set: { model.selectedLayer.holdMode = $0 }
                            )
                        ) {
                            ForEach(HoldMode.allCases, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                    }

                    InspectorRow(label: "On tap", divider: sendsKeyOnTap) {
                        Picker(
                            "",
                            selection: Binding(
                                get: { sendsKeyOnTap },
                                set: {
                                    model.selectedLayer.tapAction =
                                        $0 ? KeyBinding(key: "escape") : nil
                                }
                            )
                        ) {
                            Text("Do nothing").tag(false)
                            Text("Send a key").tag(true)
                        }
                    }

                    if let tap = model.selectedLayer.tapAction {
                        InspectorRow(label: "Sends", divider: false) {
                            CompactKeyField(
                                selection: Binding(
                                    get: { tap.key },
                                    set: {
                                        model.selectedLayer.tapAction =
                                            KeyBinding(key: $0, modifiers: tap.modifiers)
                                    }
                                ))
                        }
                    }
                }
            }
        }
    }

    private var chordSentence: String {
        var sentence = "Hold \(trigger.wrappedValue.displayLabel) to reach this layer."
        if trigger.wrappedValue.key.isConsumedWhileHeld,
            model.selectedLayer.tapAction == nil
        {
            sentence += " It will stop typing on its own, so give it a tap action below to keep it."
        }
        return sentence
    }
}
