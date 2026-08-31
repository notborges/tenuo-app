import SwiftUI

struct KeyboardLayoutView: View {

    let mappings: [String: KeyAction]
    var inherited: [String: KeyAction] = [:]
    var selected: String?
    var triggerName: String = ""
    var triggerKey: TriggerKey?
    var width: CGFloat?
    var isInteractive: Bool = true
    var onSelect: (String) -> Void = { _ in }

    @State private var pressed: String?

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / KeyboardLayout.widthInUnits
            let gap = unit * KeyboardLayout.gapRatio

            Deck(
                padding: unit * KeyboardLayout.bezelRatio,
                cornerRadius: unit * 0.42,
                isElevated: width == nil
            ) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(Array(KeyboardLayout.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: gap) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, element in
                                view(for: element, unit: unit, gap: gap)
                            }
                        }
                    }
                }
            }
        }
        .aspectRatio(KeyboardLayout.aspectRatio, contentMode: .fit)
        .modifier(BoardSizing(width: width))
    }

    @ViewBuilder
    private func view(
        for element: KeyboardLayout.Element,
        unit: CGFloat,
        gap: CGFloat
    ) -> some View {
        switch element {
        case .key(let key):
            keycap(
                for: key, width: span(key.width, unit: unit, gap: gap),
                height: unit, unit: unit)
        case .arrows:
            arrowCluster(unit: unit, gap: gap)
        }
    }

    private func span(_ units: CGFloat, unit: CGFloat, gap: CGFloat) -> CGFloat {
        units * unit + (units - 1) * gap
    }

    private func arrowCluster(unit: CGFloat, gap: CGFloat) -> some View {
        let half = (unit - gap) / 2
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                Color.clear.frame(width: unit, height: half)
                keycap(
                    for: KeyboardLayout.Key(name: "upArrow", label: "↑"),
                    width: unit, height: half, unit: unit)
                Color.clear.frame(width: unit, height: half)
            }
            HStack(spacing: gap) {
                keycap(
                    for: KeyboardLayout.Key(name: "leftArrow", label: "←"),
                    width: unit, height: half, unit: unit)
                keycap(
                    for: KeyboardLayout.Key(name: "downArrow", label: "↓"),
                    width: unit, height: half, unit: unit)
                keycap(
                    for: KeyboardLayout.Key(name: "rightArrow", label: "→"),
                    width: unit, height: half, unit: unit)
            }
        }
        .frame(width: span(3, unit: unit, gap: gap), height: unit)
    }

    private func keycap(
        for key: KeyboardLayout.Key,
        width: CGFloat,
        height: CGFloat,
        unit: CGFloat
    ) -> some View {
        let action = key.name.flatMap { mappings[$0] }
        let inheritedAction = key.name.flatMap { inherited[$0] }
        let shown = action ?? inheritedAction
        let isTrigger =
            (key.trigger != nil && key.trigger == triggerKey)
            || (key.name != nil && triggerKey == .key(key.name!))

        let legend = secondaryLegend(for: key, shown: shown)

        return Keycap(
            label: key.label,
            symbol: key.symbol,
            secondary: legend.text,
            secondarySymbol: legend.symbol,
            secondaryAbove: legend.above,
            secondaryIsMapping: legend.isMapping,
            width: width,
            height: height,
            legendSize: max(7, min(14, unit * 0.28)),
            cornerRadius: unit * 0.16,
            alignment: alignment(for: key.legend),
            isLit: action != nil,
            isRinged: isTrigger,
            hasIndicator: key.hasIndicator && isTrigger,
            isInactive: !key.isMappable,
            isGhosted: action == nil && inheritedAction != nil,
            isSelected: key.name != nil && key.name == selected,
            isPressed: key.name != nil && key.name == pressed
        )
        .contentShape(RoundedRectangle(cornerRadius: unit * 0.16, style: .continuous))
        .modifier(
            KeyInteraction(
                isEnabled: isInteractive,
                name: key.name,
                isMappable: key.isMappable,
                pressed: $pressed,
                onSelect: onSelect
            )
        )
        .tooltip(
            isInteractive
                ? tooltip(
                    for: key, action: action, inherited: inheritedAction,
                    isTrigger: isTrigger)
                : nil)
    }

    private func secondaryLegend(
        for key: KeyboardLayout.Key,
        shown: KeyAction?
    ) -> (text: String?, symbol: String?, above: Bool, isMapping: Bool) {
        if let shown { return (shown.displayLabel, nil, false, true) }
        if let glyph = key.glyph { return (nil, glyph, true, false) }
        if let shifted = key.shifted { return (shifted, nil, true, false) }
        if let word = key.word { return (word, nil, false, false) }
        return (nil, nil, false, false)
    }

    private func alignment(for position: KeyboardLayout.LegendPosition) -> HorizontalAlignment {
        switch position {
        case .center: return .center
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    private func tooltip(
        for key: KeyboardLayout.Key,
        action: KeyAction?,
        inherited: KeyAction?,
        isTrigger: Bool
    ) -> String? {
        if isTrigger { return "\(triggerName) holds this layer open" }
        guard key.isMappable, action == nil else { return nil }
        if inherited != nil { return "Inherited. Click to override" }
        return nil
    }
}

private struct BoardSizing: ViewModifier {
    let width: CGFloat?

    func body(content: Content) -> some View {
        if let width {
            content.frame(width: width, height: width / KeyboardLayout.aspectRatio)
        } else {
            content.frame(maxWidth: KeyboardLayout.maxWidth)
        }
    }
}

private struct KeyInteraction: ViewModifier {
    let isEnabled: Bool
    let name: String?
    let isMappable: Bool
    @Binding var pressed: String?
    let onSelect: (String) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onHover { inside in
                    guard isMappable else { return }
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .onTapGesture {
                    guard let name else { return }
                    onSelect(name)
                }
                .onLongPressGesture(
                    minimumDuration: 0,
                    pressing: { isPressing in
                        pressed = isPressing && isMappable ? name : nil
                    }, perform: {})
        } else {
            content
        }
    }
}
