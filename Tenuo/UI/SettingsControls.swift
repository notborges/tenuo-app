import SwiftUI

enum Inspector {
    static let controlWidth: CGFloat = 148
    static let rowInset: CGFloat = 12
    static let rowHeight: CGFloat = 48
}

struct InspectorCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .sectionLabel()
                    .padding(.horizontal, Inspector.rowInset)
            }

            VStack(spacing: 0) { content }
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.Surface.raised)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .strokeBorder(DS.Line.hairline, lineWidth: 0.5)
                }

            if let footer {
                Text(footer)
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Inspector.rowInset)
            }
        }
    }
}

struct InspectorRow<Control: View>: View {
    var label: String
    var divider: Bool = true
    @ViewBuilder var control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.small) {
                Text(label)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                control
                    .controlSize(.regular)
                    .labelsHidden()
                    .accessibilityLabel(label)
                    .frame(width: Inspector.controlWidth, alignment: .trailing)
            }
            .padding(.horizontal, Inspector.rowInset)
            .frame(minHeight: Inspector.rowHeight)

            if divider {
                Divider().opacity(0.35).padding(.leading, Inspector.rowInset)
            }
        }
    }
}

struct InspectorStatusRow<Action: View>: View {
    var text: String
    var ink: Color = DS.Ink.secondary
    var divider: Bool = false
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.small) {
                Text(text)
                    .font(DS.Typography.body)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: DS.Space.tight)
                action
            }
            .padding(.horizontal, Inspector.rowInset)
            .frame(minHeight: Inspector.rowHeight)

            if divider {
                Divider().opacity(0.35).padding(.leading, Inspector.rowInset)
            }
        }
    }
}

struct InspectorWideRow<Content: View>: View {
    var label: String
    var divider: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text(label)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Ink.primary)
                content.controlSize(.regular)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Inspector.rowInset)
            .padding(.vertical, 10)

            if divider {
                Divider().opacity(0.35).padding(.leading, Inspector.rowInset)
            }
        }
    }
}

struct InspectorDestructiveButton: View {
    var title: String
    var confirm: String?
    var action: () -> Void
    @State private var isHovering = false
    @State private var isConfirming = false

    var body: some View {
        Button {
            if confirm != nil { isConfirming = true } else { action() }
        } label: {
            Text(title)
                .font(DS.Typography.body)
                .foregroundStyle(isHovering ? DS.Signal.destructive : DS.Ink.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: DS.Metrics.controlHeight)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(isHovering ? DS.Signal.destructive.opacity(0.12) : DS.Surface.raised)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(DS.Motion.hover, value: isHovering)
        .confirmationDialog(confirm ?? "", isPresented: $isConfirming) {
            Button(title, role: .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct ModifierChips: View {
    @Binding var trigger: LayerTrigger

    private static let families = ["shift", "control", "option", "command"]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Self.families, id: \.self) { family in
                chip(family: family)
            }
        }
    }

    private func chip(family: String) -> some View {
        let plain = ModifierRequirement(rawValue: family)!
        let left = ModifierRequirement(rawValue: "left\(family.capitalized)")!
        let right = ModifierRequirement(rawValue: "right\(family.capitalized)")!
        let options: [ModifierRequirement?] = [nil, plain, left, right]
        let current = [plain, left, right].first { trigger.modifiers.contains($0) }
        let detail: String? = current == left ? "L" : (current == right ? "R" : nil)

        return CycleChip(symbol: plain.symbol, detail: detail, isOn: current != nil) {
            let index = options.firstIndex(of: current) ?? 0
            let next = options[(index + 1) % options.count]
            trigger.modifiers.removeAll { [plain, left, right].contains($0) }
            if let next { trigger.modifiers.append(next) }
        }
        .tooltip("\(plain.displayName) · click to cycle through any, left, and right")
    }
}

struct KeyChooser: View {
    @ObservedObject private var keyboard = KeyboardPresentation.shared
    @Binding var selection: String
    var columns: Int = 8
    var height: CGFloat? = 170
    @State private var query = ""

    private var groups: [(KeyCatalog.Group, [KeyCatalog.Key])] {
        KeyCatalog.Group.allCases.compactMap { group in
            let keys = KeyCatalog.keys(in: group).filter(matches)
            return keys.isEmpty ? nil : (group, keys)
        }
    }

    private func matches(_ key: KeyCatalog.Key) -> Bool {
        guard !query.isEmpty else { return true }
        let needle = query.lowercased()
        return key.name.lowercased().contains(needle)
            || keyboard.label(for: key.name).lowercased().contains(needle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: DS.Icon.small))
                    .foregroundStyle(DS.Ink.tertiary)
                TextField("Search keys", text: $query)
                    .textFieldStyle(.plain)
                    .font(DS.Typography.body)
            }
            .padding(.horizontal, 8)
            .frame(height: DS.Metrics.controlHeight)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .fill(DS.Surface.raised)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .strokeBorder(DS.Line.hairline, lineWidth: 0.5)
            }

            if let height {
                ScrollView { list }.frame(height: height)
            } else {
                list
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups, id: \.0) { group, keys in
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.rawValue).sectionLabel()
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 4),
                            count: columns),
                        spacing: 4
                    ) {
                        ForEach(keys, id: \.name) { key in
                            keyButton(key)
                        }
                    }
                }
            }
            if groups.isEmpty {
                Text("No keys match “\(query)”")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Ink.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Space.medium)
            }
        }
        .padding(.bottom, 4)
    }

    private func keyButton(_ key: KeyCatalog.Key) -> some View {
        let isSelected = key.name == selection
        return Button {
            selection = key.name
        } label: {
            Text(keyboard.label(for: key.name))
                .font(DS.Typography.label.weight(isSelected ? .semibold : .regular))
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                        .fill(isSelected ? DS.Selection.solid : DS.Surface.raised)
                )
                .foregroundStyle(isSelected ? DS.Selection.solidInk : DS.Ink.primary)
        }
        .buttonStyle(.plain)
        .tooltip(keyboard.displayName(for: key.name))
    }
}

struct InspectorPicker<Selection: Hashable, Content: View>: View {
    var title: String
    @Binding var selection: Selection
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            Picker(title, selection: $selection) { content }
                .pickerStyle(.inline)
        } label: {
            PopupFieldLabel(title: title)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct PopupFieldLabel: View {
    var title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Ink.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 2)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: DS.Icon.small, weight: .medium))
                .foregroundStyle(DS.Ink.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: DS.Metrics.controlHeight)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous)
                .fill(DS.Surface.raisedHover)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.field, style: .continuous)
                .strokeBorder(DS.Line.hairline, lineWidth: 0.5)
        }
        .contentShape(Rectangle())
    }
}

struct CompactKeyField: View {
    @Binding var selection: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            PopupFieldLabel(title: KeyboardPresentation.shared.displayName(for: selection))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            KeyChooser(selection: $selection)
                .frame(width: 300)
                .padding(DS.Space.small)
        }
    }
}

struct TriggerKeyField: View {
    @Binding var trigger: TriggerKey
    @State private var isChoosing = false

    private enum Choice: Hashable {
        case use(TriggerKey)
        case other
    }

    private var custom: TriggerKey? {
        if case .key = trigger { return trigger }
        return nil
    }

    var body: some View {
        InspectorPicker(
            title: trigger.keyboardName,
            selection: Binding<Choice>(
                get: { .use(trigger) },
                set: { choice in
                    switch choice {
                    case .use(let key): trigger = key
                    case .other: isChoosing = true
                    }
                }
            )
        ) {
            ForEach(TriggerKey.suggested, id: \.self) { entry($0) }
            Section("Right side") {
                ForEach(TriggerKey.rightModifiers, id: \.self) { entry($0) }
            }
            Section("Left side") {
                ForEach(TriggerKey.leftModifiers, id: \.self) { entry($0) }
            }
            Section {
                if let custom { entry(custom) }
                Text("Other key…").tag(Choice.other)
            }
        }
        .popover(isPresented: $isChoosing, arrowEdge: .bottom) {
            KeyChooser(
                selection: Binding(
                    get: {
                        custom.flatMap { if case let .key(n) = $0 { return n } else { return nil } }
                            ?? ""
                    },
                    set: {
                        trigger = .key($0); isChoosing = false
                    }
                )
            )
            .frame(width: 300)
            .padding(DS.Space.small)
        }
    }

    private func entry(_ key: TriggerKey) -> some View {
        Text(key.keyboardName).tag(Choice.use(key))
    }
}
