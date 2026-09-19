import AppKit
import SwiftUI

enum DS {

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let value =
                    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(
                    srgbRed: CGFloat((value >> 16) & 255) / 255,
                    green: CGFloat((value >> 8) & 255) / 255,
                    blue: CGFloat(value & 255) / 255, alpha: 1)
            })
    }

    enum Surface {
        static let window = adaptive(0xF5F6F8, 0x111114)
        static let sidebar = adaptive(0xECEEF2, 0x1A1A1F)
        static let raised = adaptive(0xFFFFFF, 0x25252B)
        static let raisedHover = adaptive(0xE7EAF0, 0x303037)
        static let deck = adaptive(0xE5E8EE, 0x303036)
    }

    enum Line {
        static let hairline = adaptive(0xDCDFE6, 0x37373E)
        static let strong = adaptive(0xBDC4CE, 0x5A5A64)
    }

    enum Ink {
        static let primary = adaptive(0x222731, 0xF3F3F5)
        static let secondary = adaptive(0x566071, 0xB9B9C2)
        static let tertiary = adaptive(0x626D7D, 0x93939F)
    }

    enum Selection {
        static let accent = adaptive(0x0868D9, 0xE5E5ED)
        static let fill = adaptive(0xDCEAFF, 0x323239)
        static let hover = adaptive(0xE3E7EE, 0x29292F)
        static let solid = adaptive(0x303038, 0xECECF2)
        static let solidInk = adaptive(0xFFFFFF, 0x202026)
    }

    enum Signal {
        static let destructive = Color(nsColor: .systemRed)
        static let warning = Color(nsColor: .systemOrange)
        static let ok = Color(nsColor: .systemGreen)
    }

    enum Cap {
        static let face = adaptive(0xFFFFFF, 0x24242A)
        static let wall = adaptive(0xC7CDD7, 0x101013)
        static let edge = adaptive(0xCDD3DD, 0x41414A)
        static let ink = adaptive(0x3C4657, 0xDFDFE5)
        static let inkDim = adaptive(0x747F91, 0x8D8D9A)
        static let sub = adaptive(0x59667A, 0xB9B9C4)
        static let faceInactive = adaptive(0xDCE1E9, 0x1B1B20)
        static let edgeInactive = adaptive(0xCDD3DD, 0x303037)
        static let inkInactive = adaptive(0x748094, 0x858591)
        static let inherited = adaptive(0x465A75, 0xB9B9C8)
        static let faceLit = adaptive(0xDCEAFF, 0xECECF2)
        static let wallLit = adaptive(0xA9C6EF, 0x9999A6)
        static let edgeLit = adaptive(0xA2C3EF, 0xFFFFFF)
        static let inkLit = adaptive(0x124987, 0x25252D)
        static let subLit = adaptive(0x124987, 0x25252D)
    }

    enum Radius {
        static let small: CGFloat = 12
        static let key: CGFloat = 7
        static let chip: CGFloat = 14
        static let card: CGFloat = 20
        static let field: CGFloat = 8
        static let panel: CGFloat = 24
    }

    enum Space {
        static let tight: CGFloat = 6
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }

    enum Metrics {
        static let windowInset: CGFloat = 12
        static let panelInset: CGFloat = 16
        static let footerHeight: CGFloat = 64
        static let row: CGFloat = 38
        static let sidebarWidth: CGFloat = 220
        static let inspectorWidth: CGFloat = 320
        static let header: CGFloat = 44
        static let titlebar: CGFloat = 36
        static let controlHeight: CGFloat = 32
    }

    enum Typography {
        static let display = Font.system(size: 19, weight: .semibold, design: .rounded)
        static let title = Font.system(size: 14, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let label = Font.system(size: 12, weight: .medium)
        static let caption = Font.system(size: 11, weight: .semibold)
        static let footnote = Font.system(size: 11, weight: .regular)
        static let mono = Font.system(size: 11).monospacedDigit()
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

private struct WindowPanel: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(8)))
            content.clipShape(shape)
                .overlay { shape.stroke(DS.Line.hairline.opacity(0.6), lineWidth: 0.5) }
        } else {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            content.clipShape(shape)
                .overlay { shape.strokeBorder(DS.Line.hairline.opacity(0.6), lineWidth: 0.5) }
        }
    }
}

extension View {
    func windowPanel() -> some View { modifier(WindowPanel()) }

    func navigationSurface() -> some View {
        background(DS.Surface.sidebar)
    }

    func sectionLabel() -> some View {
        font(DS.Typography.caption)
            .foregroundStyle(DS.Ink.secondary)
    }
}

struct TooltipModifier: ViewModifier {
    let title: String?

    @State private var tooltipReference = TooltipReference()

    func body(content: Content) -> some View {
        content
            .overlay {
                if title != nil {
                    TooltipAnchorRepresentable(reference: tooltipReference)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }
            .onHover { hovering in
                guard let title else { return }
                if hovering {
                    TooltipWindowController.shared.schedule(
                        title: title, from: tooltipReference)
                } else {
                    TooltipWindowController.shared.hide(from: tooltipReference)
                }
            }
            .accessibilityHint(title ?? "")
    }
}

private final class TooltipReference {
    weak var view: TooltipAnchorNSView?
}

private final class TooltipAnchorNSView: NSView {
}

private struct TooltipAnchorRepresentable: NSViewRepresentable {
    let reference: TooltipReference

    func makeNSView(context: Context) -> TooltipAnchorNSView {
        let view = TooltipAnchorNSView()
        reference.view = view
        return view
    }

    func updateNSView(_ nsView: TooltipAnchorNSView, context: Context) {
        reference.view = nsView
    }
}

@MainActor
private final class TooltipWindowController {
    static let shared = TooltipWindowController()

    private static let delay: TimeInterval = 0.2

    private var generation = 0
    private var showWorkItem: DispatchWorkItem?
    private var panel: NSPanel?
    private var hosting: NSHostingView<TooltipBubble>?
    private var activeReference: TooltipReference?

    func schedule(title: String, from reference: TooltipReference) {
        showWorkItem?.cancel()
        generation &+= 1
        let currentGeneration = generation

        if activeReference !== reference {
            dismiss(animated: false)
        }
        activeReference = reference

        let workItem = DispatchWorkItem { [weak self, weak reference] in
            guard let self,
                self.generation == currentGeneration,
                let reference,
                let anchor = reference.view,
                anchor.window != nil
            else { return }

            self.present(title: title, from: anchor)
        }

        showWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.delay,
            execute: workItem)
    }

    func hide(from reference: TooltipReference) {
        guard activeReference === reference else { return }
        generation &+= 1
        showWorkItem?.cancel()
        showWorkItem = nil
        activeReference = nil
        dismiss()
    }

    private func present(title: String, from anchor: TooltipAnchorNSView) {
        guard anchor.window != nil else { return }

        let hosting: NSHostingView<TooltipBubble>
        let panel: NSPanel

        if let existingHosting = self.hosting, let existingPanel = self.panel {
            hosting = existingHosting
            panel = existingPanel
        } else {
            hosting = NSHostingView(rootView: TooltipBubble(title: title))
            hosting.setFrameSize(hosting.fittingSize)

            panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false)
            panel.contentView = hosting
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .canJoinAllApplications,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle,
            ]
            panel.becomesKeyOnlyIfNeeded = true

            self.hosting = hosting
            self.panel = panel
        }

        let size = layout(hosting: hosting, panel: panel, title: title, around: anchor)
        guard size.width > 0, size.height > 0 else { return }

        panel.orderFrontRegardless()

        if panel.alphaValue == 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    private func dismiss(animated: Bool = true) {
        guard let panel else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        } else {
            panel.orderOut(nil)
            panel.alphaValue = 0
        }
    }

    private func layout(
        hosting: NSHostingView<TooltipBubble>,
        panel: NSPanel,
        title: String,
        around anchor: TooltipAnchorNSView
    ) -> CGSize {
        hosting.rootView = TooltipBubble(title: title)
        hosting.invalidateIntrinsicContentSize()
        hosting.layoutSubtreeIfNeeded()

        let size = hosting.fittingSize
        guard let window = anchor.window else { return size }

        let anchorInWindow = anchor.convert(anchor.bounds, to: nil)
        let anchorRect = window.convertToScreen(anchorInWindow)
        let screen =
            NSScreen.screens.first {
                $0.frame.contains(NSPoint(x: anchorRect.midX, y: anchorRect.midY))
            } ?? window.screen ?? NSScreen.main
        guard let screen else { return size }

        let visibleFrame = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let gap: CGFloat = 6
        let canShowAbove = anchorRect.maxY + gap + size.height <= visibleFrame.maxY

        let proposedX = anchorRect.midX - size.width / 2
        let x = min(
            max(proposedX, visibleFrame.minX),
            max(visibleFrame.minX, visibleFrame.maxX - size.width))
        let proposedY =
            canShowAbove
            ? anchorRect.maxY + gap
            : anchorRect.minY - gap - size.height
        let y = min(
            max(proposedY, visibleFrame.minY),
            max(visibleFrame.minY, visibleFrame.maxY - size.height))
        hosting.setFrameSize(size)
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        return size
    }
}

private struct TooltipBubble: View {
    let title: String

    private var textWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let measured = (title as NSString).boundingRect(
            with: NSSize(width: 10_000, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).width
        return min(300, max(1, ceil(measured)))
    }

    var body: some View {
        Text(title)
            .font(DS.Typography.label)
            .foregroundStyle(DS.Ink.primary)
            .multilineTextAlignment(.leading)
            .lineSpacing(1)
            .lineLimit(2)
            .frame(width: textWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(DS.Surface.sidebar)
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .stroke(DS.Line.strong, lineWidth: 0.5)
                    }
            }
            .shadow(color: .black.opacity(0.38), radius: 10, y: 4)
            .accessibilityHidden(true)
    }
}

extension View {
    func tooltip(_ title: String?) -> some View {
        modifier(TooltipModifier(title: title))
    }
}

struct Keycap: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var label: String
    var symbol: String?
    var secondary: String?
    var secondarySymbol: String?
    var secondaryImage: NSImage?
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
    var castsShadow: Bool = false
    var returnNotch: CGFloat = 0

    private var legend: CGFloat { legendSize ?? 11 }
    private var radius: CGFloat { cornerRadius ?? max(3, DS.Radius.key * height / 34) }

    private var depth: CGFloat { max(1, min(width, height) * 0.075) }

    var body: some View {
        let shape = KeycapOutline(radius: radius, notch: returnNotch)

        face(shape)
            .offset(y: isPressed ? depth * 0.6 : 0)
            .frame(width: width, height: height, alignment: .top)
            .background(alignment: .top) {
                shape.fill(isLit ? DS.Cap.wallLit : DS.Cap.wall)
                    .frame(width: width, height: height)
                    .opacity(isInactive ? 0.55 : 1)
                    .shadow(
                        color: .black.opacity(castsShadow ? 0.25 : 0),
                        radius: castsShadow ? depth * 0.35 : 0,
                        y: castsShadow && !isPressed ? depth * 0.4 : 0)
            }
            .overlay {
                if isSelected {
                    KeycapOutline(radius: radius + 2.5, notch: returnNotch)
                        .strokeBorder(DS.Selection.accent, lineWidth: 2)
                        .padding(-2.5)
                }
            }
            .animation(reduceMotion ? nil : DS.Motion.travel, value: isPressed)
            .animation(reduceMotion ? nil : DS.Motion.fill, value: isLit)
    }

    private func face(_ shape: KeycapOutline) -> some View {
        Group {
            if secondaryIsMapping,
                secondary != nil || secondarySymbol != nil || secondaryImage != nil
            {
                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .font(.system(size: max(7, legend * 0.72), weight: .medium))
                        .foregroundStyle(legendColor.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        if let secondaryImage {
                            Image(nsImage: secondaryImage).resizable().scaledToFit()
                                .frame(width: legend * 1.6, height: legend * 1.6)
                        } else if let secondarySymbol {
                            Image(systemName: secondarySymbol)
                        } else {
                            Text(secondary ?? "")
                        }
                    }
                    .font(.system(size: legend * 1.05, weight: .semibold))
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
            } else {
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
            }
        }
        .padding(.horizontal, alignment == .center ? 2 : legend * 0.55)
        .frame(width: width, height: height - depth, alignment: frameAlignment)
        .clipped()
        .background {
            shape.fill(faceColor)
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [.white.opacity(0.035), .clear, .black.opacity(0.045)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
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

struct KeycapOutline: InsettableShape {
    var radius: CGFloat
    var notch: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard notch > 0 else {
            return RoundedRectangle(cornerRadius: max(0, radius - insetAmount), style: .continuous)
                .path(in: r)
        }
        let middle = rect.midY
        let points = [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX + notch, y: r.maxY),
            CGPoint(x: r.minX + notch, y: middle - insetAmount),
            CGPoint(x: r.minX, y: middle - insetAmount),
        ]
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY + radius))
        for index in points.indices {
            path.addArc(
                tangent1End: points[index], tangent2End: points[(index + 1) % points.count],
                radius: max(0, radius - insetAmount))
        }
        path.closeSubpath()
        return path
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
            .background {
                shape.fill(DS.Surface.deck)
                    .overlay {
                        shape.fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .white.opacity(0.08), location: 0),
                                    .init(color: .clear, location: 0.45),
                                    .init(color: .black.opacity(0.09), location: 1),
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .shadow(
                        color: .black.opacity(isElevated ? 0.30 : 0),
                        radius: isElevated ? 18 : 0, y: isElevated ? 8 : 0)
            }
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
    }
}
