import AppKit
import SwiftUI

@MainActor
final class CheatSheetController {
    private static let revealDelay: TimeInterval = 0.55

    private let model: AppModel
    private var window: NSPanel?
    private var revealWorkItem: DispatchWorkItem?
    private var activeLayer: Int?

    var isEnabled = true {
        didSet {
            if !isEnabled { hide() }
        }
    }

    init(model: AppModel) {
        self.model = model
    }

    func setActiveLayer(_ index: Int?) {
        guard isEnabled else { return }
        activeLayer = index
        if index != nil { scheduleReveal() } else { hide() }
    }

    private func scheduleReveal() {
        cancelReveal()
        let item = DispatchWorkItem { [weak self] in self?.show() }
        revealWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.revealDelay, execute: item)
    }

    private func cancelReveal() {
        revealWorkItem?.cancel()
        revealWorkItem = nil
    }

    private func show() {
        guard window == nil else { return }
        model.refresh()

        let view = CheatSheetView(model: model, activeLayerIndex: activeLayer)
            .glassPanel()
            .padding(10)

        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.becomesKeyOnlyIfNeeded = true

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(
                NSPoint(
                    x: frame.midX - size.width / 2,
                    y: frame.minY + frame.height * 0.035
                ))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        window = panel
    }

    private func hide() {
        cancelReveal()
        guard let panel = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    deinit {
        revealWorkItem?.cancel()
    }
}

struct CheatSheetView: View {
    @ObservedObject var model: AppModel
    var activeLayerIndex: Int?

    private var layer: Layer? {
        if let index = activeLayerIndex, model.layers.indices.contains(index) {
            return model.layers[index]
        }
        return model.profile.triggeredLayers.first
    }

    private var mappings: [String: KeyAction] { layer?.mappings ?? [:] }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.small) {
            HStack(spacing: DS.Space.tight) {
                Keycap(
                    label: layer?.trigger?.displayLabel ?? "·",
                    width: 30, height: 28, legendSize: 11, isRinged: true)
                Text(layer?.name ?? "")
                    .font(DS.Typography.title)
                Spacer(minLength: DS.Space.medium)
                Text(layer?.holdMode.displayName ?? "")
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Ink.tertiary)
            }

            KeyboardLayoutView(
                mappings: mappings,
                triggerKey: layer?.trigger?.key,
                width: 420,
                isInteractive: false
            )

            if let layer {
                Text(layer.holdMode.summary)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Ink.secondary)
            }
        }
        .padding(DS.Space.medium)
    }
}
