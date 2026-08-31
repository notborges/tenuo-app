import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private var panel: NSPanel?
    private var hosting: NSHostingView<MenuPanelView>?
    private var dismissMonitor: Any?
    private var localDismissMonitor: Any?
    private var contentObserver: AnyCancellable?

    private static let menuBarGap: CGFloat = 8

    var onOpenEditor: (() -> Void)?
    var onOpenPreferences: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.setAccessibilityLabel("Tenuo")
        }
        refresh()
    }

    func refresh() {
        model.refresh()
        guard let button = statusItem.button else { return }

        let active = model.isActive && model.isTrusted
        if model.isTrusted, let mark = NSImage(named: "TenuoTemplate") {
            button.image = mark
        } else {
            button.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "Tenuo")
        }
        button.image?.isTemplate = true
        button.appearsDisabled = !active

        button.toolTip =
            model.isTrusted
            ? (model.isEnabled ? "Tenuo is active" : "Tenuo is disabled")
            : "Tenuo needs Accessibility access"
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel() {
        refresh()

        let view = MenuPanelView(model: model, updates: model.updates) { [weak self] in
            self?.closePanel()
            self?.onOpenEditor?()
        } onOpenPreferences: { [weak self] in
            self?.closePanel()
            self?.onOpenPreferences?()
        }

        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)

        let backdrop = NSVisualEffectView(frame: NSRect(origin: .zero, size: hosting.fittingSize))
        backdrop.material = .menu
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.maskImage = Self.roundedMask(radius: DS.Radius.panel)
        hosting.autoresizingMask = [.width, .height]
        backdrop.addSubview(hosting)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = backdrop
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.panel = panel
        self.hosting = hosting
        contentObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizeToFitContent() }
        }
        position(panel)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        NSApp.activate(ignoringOtherApps: true)
        startWatchingForDismissal()
    }

    func presentForPreview() {
        openPanel()
        stopWatchingForDismissal()
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.set()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func position(_ panel: NSPanel) {
        guard let button = statusItem.button,
            let buttonWindow = button.window
        else { return }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let size = panel.frame.size
        var origin = NSPoint(
            x: buttonFrame.midX - size.width / 2,
            y: buttonFrame.minY - size.height - Self.menuBarGap
        )

        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrameOrigin(origin)
    }

    private func resizeToFitContent() {
        guard let panel, let hosting, panel.isVisible else { return }
        let size = hosting.fittingSize
        guard size.height > 1, size != panel.frame.size else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
        panel.invalidateShadow()
    }

    func closePanel() {
        stopWatchingForDismissal()
        contentObserver = nil
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        refresh()
    }

    private func startWatchingForDismissal() {
        stopWatchingForDismissal()

        dismissMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePanel()
        }

        localDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            guard event.window !== panel,
                event.window !== statusItem.button?.window
            else { return event }
            closePanel()
            return event
        }
    }

    private func stopWatchingForDismissal() {
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        if let localDismissMonitor { NSEvent.removeMonitor(localDismissMonitor) }
        dismissMonitor = nil
        localDismissMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        closePanel()
    }

    deinit {
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor) }
        if let localDismissMonitor { NSEvent.removeMonitor(localDismissMonitor) }
    }
}
