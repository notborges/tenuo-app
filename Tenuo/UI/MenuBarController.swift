import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private var popover: NSPopover?
    private var hosting: NSHostingController<MenuPanelView>?
    private var contentObserver: AnyCancellable?

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
        if popover?.isShown == true {
            closePanel()
        } else {
            openPanel()
        }
    }

    private func openPanel(isTransient: Bool = true) {
        refresh()
        guard let button = statusItem.button else { return }

        let view = MenuPanelView(model: model, updates: model.updates) { [weak self] in
            self?.closePanel()
            self?.onOpenEditor?()
        } onOpenPreferences: { [weak self] in
            self?.closePanel()
            self?.onOpenPreferences?()
        }

        let hosting = NSHostingController(rootView: view)
        let popover = NSPopover()
        popover.behavior = isTransient ? .transient : .applicationDefined
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = hosting
        popover.contentSize = hosting.view.fittingSize
        popover.delegate = self

        self.popover = popover
        self.hosting = hosting
        contentObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.resizePopover() }
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func presentForPreview() {
        openPanel(isTransient: false)
    }

    private func resizePopover() {
        guard let popover, let hosting, popover.isShown else { return }
        let size = hosting.view.fittingSize
        guard size.width > 1, size.height > 1, size != popover.contentSize else { return }
        popover.contentSize = size
    }

    func closePanel() {
        contentObserver = nil
        popover?.close()
        popover = nil
        hosting = nil
        refresh()
    }

    func popoverDidClose(_ notification: Notification) {
        guard (notification.object as? NSPopover) === popover else { return }
        contentObserver = nil
        popover = nil
        hosting = nil
        refresh()
    }
}
