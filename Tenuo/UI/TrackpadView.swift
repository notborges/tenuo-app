import SwiftUI

struct TrackpadView: View {
    var mappings: [String: LayerMapping]
    var inherited: [String: LayerMapping] = [:]
    var selected: TrackpadGesture?
    var hasPro = true
    var onSelect: ((TrackpadGesture) -> Void)?
    @State private var hovered: TrackpadGesture?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var highlighted: TrackpadGesture? { hovered ?? selected }

    private func mapping(for gesture: TrackpadGesture) -> LayerMapping? {
        mappings[gesture.rawValue] ?? inherited[gesture.rawValue]
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                ZStack {
                    // A narrow recessed seam surrounds the glass surface.
                    shape.fill(.black.opacity(colorScheme == .dark ? 0.7 : 0.22))
                    shape.inset(by: 1)
                        .fill(DS.Surface.deck)
                        .overlay {
                            shape.inset(by: 1).fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.07), .clear, .black.opacity(0.10)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    shape.strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(
                                    color: .black.opacity(colorScheme == .dark ? 0.55 : 0.16),
                                    location: 0),
                                .init(color: .white.opacity(0.06), location: 0.5),
                                .init(color: .white.opacity(0.24), location: 1),
                            ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    shape.inset(by: 1.5).strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.12), .clear],
                            startPoint: .top, endPoint: .bottom), lineWidth: 0.5)

                    if let highlighted {
                        let point = position(highlighted, in: proxy.size)
                        shape.inset(by: 1).fill(
                            RadialGradient(
                                colors: [DS.Ink.primary.opacity(0.055), .clear],
                                center: UnitPoint(
                                    x: point.x / proxy.size.width,
                                    y: point.y / proxy.size.height),
                                startRadius: 0, endRadius: 52)
                        )
                        .allowsHitTesting(false)
                        swipePreview(highlighted)
                            .id(highlighted)
                            .allowsHitTesting(false)
                    }
                    ForEach(TrackpadGesture.allCases, id: \.self) { gesture in
                        gestureButton(gesture)
                            .position(position(gesture, in: proxy.size))
                    }
                }
            }
            .aspectRatio(1.62, contentMode: .fit)

            Group {
                if let highlighted {
                    Text(
                        "\(highlighted.title) · \(mapping(for: highlighted)?.keyboardLabel ?? "Unassigned")"
                    )
                } else {
                    Text(hasPro ? "Two-finger swipes" : "Trackpad gestures · Pro")
                }
            }
            .font(DS.Typography.footnote)
            .foregroundStyle(DS.Ink.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trackpad, two-finger gestures")
    }

    private func swipePreview(_ gesture: TrackpadGesture) -> some View {
        let horizontal = gesture == .left || gesture == .right
        let direction: CGFloat = gesture == .left || gesture == .up ? -1 : 1
        return HStack(spacing: 5) {
            ForEach(0..<2) { _ in
                Circle()
                    .fill(DS.Ink.primary.opacity(0.18))
                    .overlay { Circle().strokeBorder(DS.Ink.primary.opacity(0.4), lineWidth: 0.75) }
                    .frame(width: 8, height: 8)
            }
        }
        .rotationEffect(.degrees(horizontal ? 90 : 0))
        .phaseAnimator(reduceMotion ? [1] : [0, 1, 2]) { contacts, phase in
            contacts
                .offset(
                    x: horizontal ? direction * (phase == 0 ? -9 : 9) : 0,
                    y: horizontal ? 0 : direction * (phase == 0 ? -9 : 9)
                )
                .opacity(phase == 1 ? 1 : 0)
        } animation: { phase in
            switch phase {
            case 1: .easeInOut(duration: 0.85)
            case 2: .easeOut(duration: 0.25)
            default: .linear(duration: 0.65)
            }
        }
    }

    private func position(_ gesture: TrackpadGesture, in size: CGSize) -> CGPoint {
        switch gesture {
        case .up: return CGPoint(x: size.width / 2, y: 25)
        case .down: return CGPoint(x: size.width / 2, y: size.height - 25)
        case .left: return CGPoint(x: 28, y: size.height / 2)
        case .right: return CGPoint(x: size.width - 28, y: size.height / 2)
        }
    }

    private func gestureButton(_ gesture: TrackpadGesture) -> some View {
        let mapping = mapping(for: gesture)
        let active = highlighted == gesture
        return Button {
            onSelect?(gesture)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: gesture.symbol)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(active ? DS.Ink.primary : DS.Ink.tertiary)
                Group {
                    if let action = mapping?.action?.macAction {
                        if let icon = action.icon {
                            Image(nsImage: icon).resizable().scaledToFit()
                        } else {
                            Image(systemName: action.symbol)
                        }
                    } else if let mapping {
                        Text(mapping.keyboardLabel)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .light))
                    }
                }
                .frame(width: 34, height: 20)
                .foregroundStyle(mapping == nil ? DS.Ink.tertiary : DS.Ink.primary)
                .opacity(mappings[gesture.rawValue] == nil && mapping != nil ? 0.6 : 1)
                .scaleEffect(active ? 1 : 0.95)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: active)
            }
            .frame(width: 48, height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? gesture : nil }
        .accessibilityLabel("\(gesture.title), \(mapping?.keyboardLabel ?? "unassigned")")
        .accessibilityAddTraits(selected == gesture ? .isSelected : [])
        .tooltip("\(gesture.title): \(mapping?.keyboardLabel ?? "Assign a shortcut or action")")
    }
}
