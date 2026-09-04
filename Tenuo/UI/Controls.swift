import SwiftUI

struct AppSwitch: View {
    @Binding var isOn: Bool
    var label: String
    var isEnabled: Bool = true

    private static let size = CGSize(width: 32, height: 20)
    private static let knob: CGFloat = 16

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? DS.Selection.solid : Color.white.opacity(0.14))
                .frame(width: Self.size.width, height: Self.size.height)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? DS.Selection.solidInk : Color.white.opacity(0.55))
                        .frame(width: Self.knob, height: Self.knob)
                        .padding(.horizontal, 2)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .animation(DS.Motion.fill, value: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

struct AppSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var label: String

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((value - range.lowerBound) / span)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 3)
                Capsule().fill(DS.Selection.solid)
                    .frame(width: max(0, fraction * width), height: 3)
                Circle()
                    .fill(.white)
                    .frame(width: 13, height: 13)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .offset(x: fraction * width - 6.5)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { commit(at: $0.location.x, width: width) }
            )
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(value + step)
            case .decrement: set(value - step)
            @unknown default: break
            }
        }
    }

    private func commit(at x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let span = range.upperBound - range.lowerBound
        set(range.lowerBound + Double(min(max(x / width, 0), 1)) * span)
    }

    private func set(_ raw: Double) {
        let clamped = min(max(raw, range.lowerBound), range.upperBound)
        let stepped = (clamped / step).rounded() * step
        value = min(max(stepped, range.lowerBound), range.upperBound)
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
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            .frame(height: DS.Metrics.row + 8)
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
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Ink.primary)
                .padding(.horizontal, 12)
                .frame(height: DS.Metrics.controlHeight)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(isHovering ? DS.Surface.raisedHover : DS.Surface.raised)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(DS.Motion.hover, value: isHovering)
    }
}
