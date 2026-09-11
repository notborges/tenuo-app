import SwiftUI

enum GlassStyle {
    static let cornerRadius: CGFloat = DS.Radius.panel
    static let cardCornerRadius: CGFloat = DS.Radius.card
}

extension View {
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = GlassStyle.cornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(DS.Line.hairline, lineWidth: 0.5))
        }
    }

    func glassCard(cornerRadius: CGFloat = GlassStyle.cardCornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(DS.Surface.raised, in: shape)
            .overlay(shape.strokeBorder(DS.Line.hairline, lineWidth: 0.5))
    }
}

struct ChordBadge: View {
    let layer: Layer
    var isSelected: Bool = false
    var width: CGFloat = 30
    var height: CGFloat = 19

    var body: some View {
        Text(layer.isBase ? "·" : (layer.trigger?.displayLabel ?? "·"))
            .font(DS.Typography.label.weight(.semibold))
            .foregroundStyle(
                layer.isBase
                    ? DS.Ink.tertiary
                    : (isSelected ? DS.Ink.primary : DS.Ink.secondary)
            )
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(minWidth: width, minHeight: height)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .fill(isSelected ? DS.Surface.raisedHover : DS.Surface.raised)
            }
    }
}

struct MappingRow: View {
    let source: String
    let destination: String
    var caption: String?
    var macAction: MacAction?

    var body: some View {
        HStack(spacing: DS.Space.tight) {
            Keycap(label: source, width: 24, height: 24, legendSize: 10, isLit: true)
            Image(systemName: "arrow.right")
                .font(.system(size: DS.Icon.tiny, weight: .semibold))
                .foregroundStyle(DS.Ink.tertiary)
            if let macAction {
                if let icon = macAction.icon {
                    Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: macAction.symbol).foregroundStyle(DS.Ink.secondary)
                        .accessibilityHidden(true)
                }
            }
            Text(caption ?? destination)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Ink.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
