import AppKit
import SwiftUI

@MainActor
final class LayerStatusController {
    private let model: AppModel
    private var panel: NSPanel?
    private var hosting: NSHostingView<LayerStatusView>?
    private var surface: NSView?
    private var items: [LayerStatusItem] = []

    init(model: AppModel) {
        self.model = model
    }

    func setActiveLayers(_ states: [LayerActivity]) {
        let statefulLayers = states.filter(\.isStateful)
        let nextItems =
            statefulLayers
            .compactMap { state -> LayerStatusItem? in
                guard model.layers.indices.contains(state.index) else { return nil }
                let layer = model.layers[state.index]
                return LayerStatusItem(
                    id: layer.id,
                    name: layer.name,
                    trigger: layer.trigger?.displayLabel ?? "·",
                    status: state.isOneShot ? .nextKey : .on)
            }

        guard nextItems != items else { return }
        items = nextItems

        guard !nextItems.isEmpty else {
            hide()
            return
        }

        if let panel, let hosting, let surface {
            hosting.rootView = LayerStatusView(items: nextItems)
            hosting.invalidateIntrinsicContentSize()
            hosting.layoutSubtreeIfNeeded()
            let size = hosting.fittingSize
            panel.setContentSize(size)
            surface.layoutSubtreeIfNeeded()
            position(panel)
        } else {
            show(nextItems)
        }
    }

    private func show(_ items: [LayerStatusItem]) {
        let hosting = NSHostingView(rootView: LayerStatusView(items: items))
        hosting.setFrameSize(hosting.fittingSize)
        let surface = makeSurface(for: hosting)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.contentView = surface
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary,
            .stationary, .ignoresCycle,
        ]
        panel.becomesKeyOnlyIfNeeded = true

        self.hosting = hosting
        self.surface = surface
        self.panel = panel

        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    private func makeSurface(for hosting: NSHostingView<LayerStatusView>) -> NSView {
        let size = hosting.fittingSize

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = DS.Radius.panel
            glass.contentView = hosting
            glass.setFrameSize(size)
            return glass
        }

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = DS.Radius.panel
        effect.layer?.masksToBounds = true
        effect.addSubview(hosting)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let margin = DS.Space.medium
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.maxY - panel.frame.height - margin))
    }

    private func hide() {
        guard let panel else { return }
        self.panel = nil
        hosting = nil
        surface = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}

private struct LayerStatusItem: Equatable, Identifiable {
    enum Status: Equatable {
        case on
        case nextKey

        var label: String {
            switch self {
            case .on: return "On until tapped again"
            case .nextKey: return "Next key only"
            }
        }

        var symbol: String {
            switch self {
            case .on: return "checkmark.circle.fill"
            case .nextKey: return "1.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .on: return DS.Signal.ok
            case .nextKey: return DS.Signal.warning
            }
        }
    }

    let id: UUID
    let name: String
    let trigger: String
    let status: Status
}

private struct LayerStatusView: View {
    let items: [LayerStatusItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                if offset > 0 {
                    Rectangle()
                        .fill(DS.Line.hairline)
                        .frame(height: 1)
                        .padding(.vertical, 8)
                }

                HStack(spacing: DS.Space.small) {
                    Keycap(
                        label: item.trigger,
                        width: 34,
                        height: 28,
                        legendSize: 10,
                        isRinged: true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(DS.Typography.title)
                            .foregroundStyle(DS.Ink.primary)
                        Text(item.status.label)
                            .font(DS.Typography.label)
                            .foregroundStyle(DS.Ink.secondary)
                    }

                    Spacer(minLength: 14)

                    Image(systemName: item.status.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(item.status.color)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .fixedSize(horizontal: true, vertical: true)
    }
}
