import AppKit
import SwiftUI

@MainActor
final class ActionFeedbackController {
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func show(_ message: String) {
        dismissal?.cancel()
        panel?.orderOut(nil)
        let content = NSHostingView(
            rootView:
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(DS.Ink.secondary)
                    Text(message).font(DS.Typography.label).foregroundStyle(DS.Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16).frame(width: 360)
                .background(DS.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.card))
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = content
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(
                NSPoint(
                    x: frame.midX - panel.frame.width / 2,
                    y: frame.maxY - panel.frame.height - 20))
        }
        self.panel = panel
        panel.orderFrontRegardless()
        dismissal = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }
}
