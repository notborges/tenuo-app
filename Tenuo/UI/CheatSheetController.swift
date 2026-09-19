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

        let screen = NSScreen.main
        let keyboardWidth = min(480, (screen?.visibleFrame.width ?? 640) - 72)
        let view = CheatSheetView(
            model: model, activeLayerIndex: activeLayer, keyboardWidth: keyboardWidth
        )
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

        if let screen {
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
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            panel.animator().alphaValue = 1
        }
        window = panel
    }

    private func hide() {
        cancelReveal()
        guard let panel = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
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
    var keyboardWidth: CGFloat = 480

    private var layer: Layer? {
        if let index = activeLayerIndex, model.layers.indices.contains(index) {
            return model.layers[index]
        }
        return model.profile.triggeredLayers.first
    }

    private var mappings: [String: LayerMapping] {
        layer.map { model.liveMappings(for: $0) } ?? [:]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.medium) {
            HStack(spacing: DS.Space.tight) {
                Keycap(
                    label: layer?.trigger?.keyboardLabel ?? "·",
                    width: 30, height: 28, legendSize: 11, isRinged: true)
                Text(layer?.name ?? "")
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.medium)
                Text("\(mappings.count) mapped \(mappings.count == 1 ? "key" : "keys")")
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Ink.tertiary)
            }

            KeyboardLayoutView(
                mappings: mappings,
                triggerKey: layer?.trigger?.key,
                width: keyboardWidth,
                isInteractive: false
            )

            if let layer {
                HStack(spacing: DS.Space.tight) {
                    Text("Other keys")
                    Spacer()
                    Text(
                        layer.outputMode.injectsHyper ? "⌃ ⌥ ⌘ ⇧  Hyper shortcuts" : "Use normally")
                }
                .font(DS.Typography.label)
                .foregroundStyle(DS.Ink.secondary)
            }
        }
        .frame(width: keyboardWidth)
        .padding(DS.Space.medium)
    }
}
