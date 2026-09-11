import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private var menuItem: NSMenuItem?
    private var hosting: NSHostingView<MenuPanelView>?
    private var contentObserver: AnyCancellable?

    var onOpenEditor: (() -> Void)?
    var onOpenPreferences: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu(title: AppIdentity.displayName)
        super.init()

        menu.autoenablesItems = false
        menu.showsStateColumn = false
        menu.delegate = self
        statusItem.menu = menu

        if let button = statusItem.button {
            button.setAccessibilityLabel(AppIdentity.displayName)
        }

        installContent()
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
                accessibilityDescription: AppIdentity.displayName)
        }
        button.image?.isTemplate = true
        button.appearsDisabled = !active

        button.toolTip =
            model.isTrusted
            ? (model.isEnabled
                ? "\(AppIdentity.displayName) is active"
                : "\(AppIdentity.displayName) is disabled")
            : "\(AppIdentity.displayName) needs Accessibility access"
    }

    private func installContent() {
        let hosting = NSHostingView(rootView: makePanelView())
        hosting.autoresizingMask = [.width, .height]
        hosting.setFrameSize(hosting.fittingSize)

        let item = NSMenuItem()
        item.view = hosting
        menu.addItem(item)

        self.menuItem = item
        self.hosting = hosting
        contentObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateContentSize() }
        }
    }

    private func makePanelView() -> MenuPanelView {
        MenuPanelView(model: model, updates: model.updates) { [weak self] in
            self?.closePanel()
            self?.onOpenEditor?()
        } onOpenPreferences: { [weak self] in
            self?.closePanel()
            self?.onOpenPreferences?()
        } onViewUpdate: { [weak self] in
            self?.closePanel()
            self?.model.updates.check()
        }
    }

    private func updateContentSize() {
        guard let hosting, let menuItem else { return }
        hosting.layoutSubtreeIfNeeded()

        let size = hosting.fittingSize
        guard size.width > 1, size.height > 1, size != hosting.frame.size else { return }

        hosting.setFrameSize(size)
        menu.itemChanged(menuItem)
    }

    func presentForPreview() {
        refresh()
        guard let button = statusItem.button else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.menu.popUp(
                positioning: nil,
                at: NSPoint(x: button.bounds.midX, y: button.bounds.minY),
                in: button)
        }
    }

    func closePanel() {
        menu.cancelTrackingWithoutAnimation()
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        refresh()
        updateContentSize()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        refresh()
    }
}
