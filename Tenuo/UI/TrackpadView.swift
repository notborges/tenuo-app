import SwiftUI

struct TrackpadView: View {
    var mappings: [String: LayerMapping]
    var inherited: [String: LayerMapping] = [:]
    var selected: TrackpadGesture?
    var hasPro = true
    var showsCaption = true
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
            .overlay(alignment: .topTrailing) {
                if !hasPro {
                    ProBadge().padding(8).allowsHitTesting(false)
                }
            }

            if showsCaption {
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
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trackpad, two-finger gestures")
    }

    private func swipePreview(_ gesture: TrackpadGesture) -> some View {
        SwipePreview(gesture: gesture, reduceMotion: reduceMotion)
            .frame(width: 40, height: 40)
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
        let horizontal = gesture == .left || gesture == .right
        let layout =
            horizontal
            ? AnyLayout(HStackLayout(spacing: 3)) : AnyLayout(VStackLayout(spacing: 3))
        let arrowFirst = gesture == .up || gesture == .left
        let arrow = Image(systemName: gesture.symbol)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(active ? DS.Ink.primary : DS.Ink.tertiary)
        return Button {
            onSelect?(gesture)
        } label: {
            layout {
                if arrowFirst { arrow }
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
                    } else if onSelect != nil {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .light))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 34, height: 20)
                .foregroundStyle(mapping == nil ? DS.Ink.tertiary : DS.Ink.primary)
                .opacity(mappings[gesture.rawValue] == nil && mapping != nil ? 0.6 : 1)
                .scaleEffect(active ? 1 : 0.95)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: active)
                if !arrowFirst { arrow }
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

/// Animate only the contacts, without driving layout of the surrounding editor.
private struct SwipePreview: NSViewRepresentable {
    var gesture: TrackpadGesture
    var reduceMotion: Bool

    func makeNSView(context: Context) -> SwipePreviewView { SwipePreviewView() }

    func updateNSView(_ view: SwipePreviewView, context: Context) {
        view.configure(gesture: gesture, reduceMotion: reduceMotion)
    }
}

private final class SwipePreviewView: NSView {
    private let contacts = CALayer()
    private var gesture: TrackpadGesture?
    private var reduceMotion = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        contacts.bounds = CGRect(x: 0, y: 0, width: 21, height: 21)
        contacts.opacity = 0
        for _ in 0..<2 {
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
            dot.cornerRadius = 4
            dot.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
            dot.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
            dot.borderWidth = 0.75
            contacts.addSublayer(dot)
        }
        layer?.addSublayer(contacts)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contacts.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            for name in [
                NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification,
            ] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(windowVisibilityChanged(_:)), name: name,
                    object: window)
            }
        }
        updateAnimation()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func configure(gesture: TrackpadGesture, reduceMotion: Bool) {
        guard self.gesture != gesture || self.reduceMotion != reduceMotion else { return }
        self.gesture = gesture
        self.reduceMotion = reduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let horizontal = gesture == .left || gesture == .right
        for (index, dot) in (contacts.sublayers ?? []).enumerated() {
            let offset = CGFloat(index) * 13 + 4
            dot.position = horizontal ? CGPoint(x: 10.5, y: offset) : CGPoint(x: offset, y: 10.5)
        }
        contacts.opacity = reduceMotion ? 1 : 0
        CATransaction.commit()
        updateAnimation()
    }

    @objc private func windowVisibilityChanged(_ notification: Notification) {
        if notification.name == NSWindow.willCloseNotification {
            contacts.removeAllAnimations()
        } else {
            updateAnimation()
        }
    }

    private func updateAnimation() {
        contacts.removeAllAnimations()
        guard let gesture, !reduceMotion, window?.occlusionState.contains(.visible) == true else {
            return
        }
        let horizontal = gesture == .left || gesture == .right
        // AppKit's vertical axis points upwards.
        let direction: CGFloat = gesture == .left || gesture == .down ? -1 : 1
        let movement = CAKeyframeAnimation(
            keyPath: horizontal ? "transform.translation.x" : "transform.translation.y")
        movement.values = [-9 * direction, 9 * direction, 9 * direction]
        movement.keyTimes = [0, 0.77, 1]
        movement.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear),
        ]
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 0]
        opacity.keyTimes = [0, 0.77, 1]
        let animation = CAAnimationGroup()
        animation.animations = [movement, opacity]
        animation.duration = 1.1
        contacts.add(animation, forKey: "swipe")
    }
}
