import SwiftUI

enum DS {

    enum Surface {
        static let window = Color(red: 0.059, green: 0.059, blue: 0.071)
        static let sidebar = Color(red: 0.082, green: 0.082, blue: 0.098)

        static let raised = Color.white.opacity(0.055)
        static let raisedHover = Color.white.opacity(0.090)

        static let deck = Color(red: 0.204, green: 0.204, blue: 0.227)
    }

    enum Line {
        static let hairline = Color.white.opacity(0.090)
        static let strong = Color.white.opacity(0.160)
    }

    enum Ink {
        static let primary = Color.white.opacity(0.95)
        static let secondary = Color.white.opacity(0.60)
        static let tertiary = Color.white.opacity(0.36)
    }

    enum Selection {
        static let fill = Color.white.opacity(0.10)
        static let hover = Color.white.opacity(0.055)
        static let solid = Color.white.opacity(0.92)
        static let solidInk = Color(red: 0.063, green: 0.063, blue: 0.075)
    }

    enum Signal {
        static let destructive = Color(red: 1.0, green: 0.42, blue: 0.376)
        static let warning = Color(red: 1.0, green: 0.635, blue: 0.227)
        static let ok = Color(red: 0.306, green: 0.820, blue: 0.486)
    }

    enum Cap {
        static let face = Color(red: 0.118, green: 0.118, blue: 0.137)
        static let wall = Color(red: 0.051, green: 0.051, blue: 0.063)
        static let edge = Color.white.opacity(0.10)
        static let ink = Color.white.opacity(0.85)
        static let inkDim = Color.white.opacity(0.30)
        static let sub = Color.white.opacity(0.34)

        static let faceInactive = Color(red: 0.086, green: 0.086, blue: 0.102)
        static let edgeInactive = Color.white.opacity(0.05)
        static let inkInactive = Color.white.opacity(0.24)

        static let inherited = Color.white.opacity(0.26)

        static let faceLit = Color(red: 0.949, green: 0.957, blue: 0.973)
        static let wallLit = Color(red: 0.573, green: 0.588, blue: 0.627)
        static let edgeLit = Color.white.opacity(0.85)
        static let inkLit = Color(red: 0.078, green: 0.078, blue: 0.094)
        static let subLit = Color.black.opacity(0.52)
    }

    enum Radius {
        static let small: CGFloat = 6
        static let key: CGFloat = 7
        static let chip: CGFloat = 7
        static let card: CGFloat = 10
        static let panel: CGFloat = 14
    }

    enum Space {
        static let tight: CGFloat = 6
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 22
    }

    enum Metrics {
        static let row: CGFloat = 26
        static let sidebarWidth: CGFloat = 244
        static let inspectorWidth: CGFloat = 320
        static let header: CGFloat = 44
        static let titlebar: CGFloat = 28
    }

    enum Typography {
        static let display = Font.system(size: 17, weight: .semibold)
        static let title = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 12, weight: .regular)
        static let label = Font.system(size: 11, weight: .medium)
        static let caption = Font.system(size: 10, weight: .semibold)
        static let footnote = Font.system(size: 10, weight: .regular)
        static let mono = Font.system(size: 10).monospacedDigit()
    }

    enum Icon {
        static let tiny: CGFloat = 8
        static let small: CGFloat = 10
        static let regular: CGFloat = 12
    }

    enum Motion {
        static let travel = Animation.easeOut(duration: 0.09)
        static let fill = Animation.easeOut(duration: 0.12)
        static let hover = Animation.easeOut(duration: 0.10)
    }
}

extension View {
    func sectionLabel() -> some View {
        font(DS.Typography.caption)
            .tracking(0.7)
            .foregroundStyle(DS.Ink.tertiary)
            .textCase(.uppercase)
    }
}

struct TooltipModifier: ViewModifier {
    let title: String?

    @State private var isVisible = false
    @State private var isHovering = false
    @State private var generation = 0

    private static let delay: Duration = .milliseconds(200)
    private static let bubbleHeight: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                guard title != nil else { return }
                if hovering {
                    generation &+= 1
                    let mine = generation
                    Task { @MainActor in
                        try? await Task.sleep(for: Self.delay)
                        guard mine == generation, isHovering else { return }
                        withAnimation(DS.Motion.hover) { isVisible = true }
                    }
                } else {
                    generation &+= 1
                    withAnimation(DS.Motion.hover) { isVisible = false }
                }
            }
            .overlay(alignment: .top) {
                if isVisible, let title {
                    bubble(title)
                        .offset(y: -(Self.bubbleHeight + 6))
                }
            }
    }

    private func bubble(_ title: String) -> some View {
        Text(title)
            .font(DS.Typography.label)
            .foregroundStyle(DS.Ink.primary)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.45), radius: 9, y: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .strokeBorder(DS.Line.strong, lineWidth: 0.5)
            }
            .transition(.opacity)
            .allowsHitTesting(false)
            .zIndex(999)
    }
}

extension View {
    func tooltip(_ title: String?) -> some View {
        modifier(TooltipModifier(title: title))
    }
}

struct Keycap: View {
    var label: String
    var symbol: String?
    var secondary: String?
    var secondarySymbol: String?
    var secondaryAbove: Bool = false
    var secondaryIsMapping: Bool = false
    var width: CGFloat = 34
    var height: CGFloat = 34
    var legendSize: CGFloat?
    var cornerRadius: CGFloat?
    var alignment: HorizontalAlignment = .center
    var isLit: Bool = false
    var isRinged: Bool = false
    var hasIndicator: Bool = false
    var isInactive: Bool = false
    var isGhosted: Bool = false
    var isSelected: Bool = false
    var isPressed: Bool = false

    private var legend: CGFloat { legendSize ?? 11 }
    private var radius: CGFloat { cornerRadius ?? max(3, DS.Radius.key * height / 34) }

    private var depth: CGFloat { max(1.2, height * 0.075) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        face(shape)
            .offset(y: isPressed ? depth * 0.6 : 0)
            .frame(width: width, height: height, alignment: .top)
            .background(alignment: .top) {
                shape.fill(isLit ? DS.Cap.wallLit : DS.Cap.wall)
                    .frame(width: width, height: height)
                    .opacity(isInactive ? 0.55 : 1)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: radius + 2.5, style: .continuous)
                        .strokeBorder(DS.Ink.primary, lineWidth: 2)
                        .padding(-2.5)
                }
            }
            .animation(DS.Motion.travel, value: isPressed)
            .animation(DS.Motion.fill, value: isLit)
    }

    private func face(_ shape: RoundedRectangle) -> some View {
        VStack(alignment: alignment, spacing: legend * 0.08) {
            if secondaryAbove { secondaryContent }

            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: legend * 1.05))
                } else {
                    Text(label).font(.system(size: legend, weight: .medium))
                }
            }
            .foregroundStyle(legendColor)

            if !secondaryAbove { secondaryContent }
        }
        .padding(.horizontal, alignment == .center ? 2 : legend * 0.55)
        .frame(width: width, height: height - depth, alignment: frameAlignment)
        .clipped()
        .background { shape.fill(faceColor) }
        .overlay { shape.strokeBorder(edgeColor, lineWidth: 0.5) }
        .overlay(alignment: .topTrailing) {
            if hasIndicator {
                Circle()
                    .fill(isLit ? DS.Cap.inkLit : DS.Ink.primary)
                    .frame(width: max(2.5, legend * 0.26), height: max(2.5, legend * 0.26))
                    .padding(.top, legend * 0.42)
                    .padding(.trailing, legend * 0.34)
            }
        }
        .overlay {
            if isRinged {
                shape.strokeBorder(isLit ? DS.Cap.inkLit : DS.Ink.primary, lineWidth: 1.5)
            }
        }
    }

    @ViewBuilder
    private var secondaryContent: some View {
        if let secondarySymbol {
            Image(systemName: secondarySymbol)
                .font(.system(size: legend * 0.78))
                .foregroundStyle(secondaryColor)
        } else if let secondary {
            Text(secondary)
                .font(
                    .system(
                        size: legend * (secondaryIsMapping ? 0.82 : 0.76),
                        weight: secondaryIsMapping ? .semibold : .regular)
                )
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private var frameAlignment: Alignment {
        if alignment == .leading { return .leading }
        if alignment == .trailing { return .trailing }
        return .center
    }

    private var faceColor: Color {
        if isLit { return DS.Cap.faceLit }
        return isInactive ? DS.Cap.faceInactive : DS.Cap.face
    }

    private var edgeColor: Color {
        if isLit { return DS.Cap.edgeLit }
        return isInactive ? DS.Cap.edgeInactive : DS.Cap.edge
    }

    private var legendColor: Color {
        if isLit { return DS.Cap.inkLit }
        return isInactive ? DS.Cap.inkInactive : DS.Cap.ink
    }

    private var secondaryColor: Color {
        if isLit { return DS.Cap.subLit }
        if isGhosted { return DS.Cap.inherited }
        if isInactive { return DS.Cap.inkInactive }
        return secondaryIsMapping ? DS.Cap.sub : DS.Cap.inkDim
    }
}

struct Deck<Content: View>: View {
    var padding: CGFloat = DS.Space.small
    var cornerRadius: CGFloat = DS.Radius.card
    var isElevated: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .padding(padding)
            .background { shape.fill(DS.Surface.deck) }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.black.opacity(0.30),
                        ],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            }
            .shadow(
                color: .black.opacity(isElevated ? 0.45 : 0),
                radius: isElevated ? 18 : 0, y: isElevated ? 8 : 0)
    }
}
