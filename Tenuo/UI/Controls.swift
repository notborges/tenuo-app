import SwiftUI

struct AppSwitch: View {
    @Binding var isOn: Bool
    var label: String
    var isEnabled: Bool = true

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .tint(DS.Selection.solid)
            .disabled(!isEnabled)
            .accessibilityLabel(label)
    }
}

struct AppSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var label: String

    var body: some View {
        Slider(value: $value, in: range, step: step) { Text(label) }
            .labelsHidden()
            .controlSize(.small)
            .tint(DS.Selection.solid)
            .accessibilityLabel(label)
    }
}

struct SidebarRow<Leading: View, Trailing: View>: View {
    var title: String
    var isSelected: Bool = false
    var isMuted: Bool = false
    var isDestructive: Bool = false
    var isEnabled: Bool = true
    var action: () -> Void
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            if isEnabled { action() }
        } label: {
            HStack(spacing: 8) {
                leading
                Text(title)
                    .font(DS.Typography.body)
                    .fontWeight(isSelected ? .medium : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                trailing
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .frame(height: DS.Metrics.row)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .fill(fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                            .strokeBorder(
                                isSelected ? DS.Line.strong.opacity(0.5) : .clear, lineWidth: 0.5)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .focused($isFocused)
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .strokeBorder(DS.Selection.accent, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .help(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
        .animation(DS.Motion.hover, value: isHovering)
    }

    private var fill: Color {
        guard isEnabled else { return .clear }
        if isSelected { return DS.Selection.fill }
        return isHovering ? DS.Selection.hover : .clear
    }

    private var ink: Color {
        if isDestructive { return DS.Signal.destructive }
        if isMuted { return DS.Ink.tertiary }
        return isSelected ? DS.Ink.primary : DS.Ink.secondary
    }
}

extension SidebarRow where Trailing == EmptyView {
    init(
        title: String,
        isSelected: Bool = false,
        isMuted: Bool = false,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder leading: () -> Leading
    ) {
        self.init(
            title: title, isSelected: isSelected, isMuted: isMuted,
            isDestructive: isDestructive, isEnabled: isEnabled, action: action,
            leading: leading, trailing: { EmptyView() })
    }
}

struct SidebarAddRow: View {
    var title: String
    var isEnabled: Bool = true
    var reason: String?
    var action: () -> Void

    var body: some View {
        SidebarRow(title: title, isMuted: true, isEnabled: isEnabled, action: action) {
            Image(systemName: "plus")
                .font(.system(size: DS.Icon.small, weight: .semibold))
                .frame(width: 15)
        }
        .tooltip(isEnabled ? nil : reason)
        .accessibilityHint(isEnabled ? "" : (reason ?? ""))
    }
}

struct FooterRow<Leading: View>: View {
    var title: String
    var height: CGFloat = 32
    var action: () -> Void
    @ViewBuilder var leading: Leading

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                leading
                Text(title).font(DS.Typography.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovering ? DS.Ink.primary : DS.Ink.secondary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(isHovering ? DS.Selection.hover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(DS.Motion.hover, value: isHovering)
    }
}

extension FooterRow where Leading == EmptyView {
    init(title: String, action: @escaping () -> Void) {
        self.init(title: title, action: action, leading: { EmptyView() })
    }
}

struct SectionHeader: View {
    var title: String
    var detail: String?

    var body: some View {
        HStack(spacing: DS.Space.tight) {
            Text(title).sectionLabel()
            Spacer(minLength: 0)
            if let detail {
                Text(detail).sectionLabel()
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppMark: View {
    var size: CGFloat

    var body: some View {
        Group {
            if let art = NSImage(named: "TenuoMark") {
                Image(nsImage: art).resizable().interpolation(.high)
            } else {
                Image(nsImage: NSApp.applicationIconImage).resizable()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    var color: Color
    var title: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Ink.secondary)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: 19)
        .background {
            Capsule().fill(DS.Surface.raised)
        }
        .accessibilityElement()
        .accessibilityLabel("Status: \(title)")
    }
}

struct CycleChip: View {
    var symbol: String
    var detail: String?
    var isOn: Bool
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(symbol).font(DS.Typography.label)
                if let detail {
                    Text(detail)
                        .font(DS.Typography.caption)
                        .opacity(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(
                        isOn
                            ? DS.Selection.solid
                            : (isHovering ? DS.Surface.raisedHover : DS.Surface.raised))
            }
            .foregroundStyle(isOn ? DS.Selection.solidInk : DS.Ink.secondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(DS.Motion.fill, value: isOn)
    }
}

struct PrimaryButton: View {
    var title: String
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Typography.body.weight(.medium))
                .foregroundStyle(DS.Selection.solidInk)
                .padding(.horizontal, 14)
                .frame(height: DS.Metrics.controlHeight)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Selection.solid.opacity(isHovering ? 1 : 0.92))
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(DS.Motion.hover, value: isHovering)
    }
}

struct QuietButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .font(DS.Typography.body)
    }
}

struct RoundedActionStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.label)
            .padding(.horizontal, 16)
            .frame(height: DS.Metrics.controlHeight)
            .foregroundStyle(prominent ? DS.Selection.solidInk : DS.Ink.primary)
            .background {
                Capsule(style: .continuous)
                    .fill(prominent ? DS.Selection.solid : DS.Surface.raisedHover)
                    .overlay {
                        Capsule().strokeBorder(DS.Line.strong.opacity(0.4), lineWidth: 0.5)
                    }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : DS.Motion.travel, value: configuration.isPressed)
    }
}
