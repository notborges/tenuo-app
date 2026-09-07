import AppKit
import SwiftUI

enum AppIdentity {
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Tenuo"
    }
}

@main
enum TenuoApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
extension NSWindow {
    func configureEditorChrome() {
        let toolbar = NSToolbar(identifier: "TenuoEditorChrome")
        toolbar.showsBaselineSeparator = false
        toolbar.allowsUserCustomization = false
        self.toolbar = toolbar
        toolbarStyle = .unified
        (self as? EditorWindow)?.positionWindowButtons()
        DispatchQueue.main.async { [weak self] in
            (self as? EditorWindow)?.positionWindowButtons()
        }
    }

    func showOnActiveSpace() {
        collectionBehavior.insert(.moveToActiveSpace)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

/// Keeps native window controls aligned with the inset navigation panel.
@MainActor
final class EditorWindow: NSWindow {
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        positionWindowButtons()
    }

    func positionWindowButtons() {
        guard let frameView = contentView?.superview else { return }
        let controls: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in controls.enumerated() {
            guard let button = standardWindowButton(type), let parent = button.superview else {
                continue
            }
            let top: CGFloat = DS.Metrics.windowInset + DS.Metrics.panelInset
            let y =
                frameView.isFlipped
                ? top - button.frame.height / 2
                : frameView.bounds.height - top - button.frame.height / 2
            let point = NSPoint(x: top + CGFloat(index) * 20, y: y)
            button.setFrameOrigin(parent.convert(point, from: frameView))
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let previewDefaults = UserDefaults(suiteName: "app.tenuo.uipreview")!

    private let controller: TenuoController = {
        guard isUIPreview else { return TenuoController() }
        return TenuoController(
            preferences: AppPreferences(defaults: previewDefaults),
            profileStore: UserDefaultsProfileStore(defaults: previewDefaults))
    }()
    private lazy var model = AppModel(controller: controller)

    private var menuBar: MenuBarController?
    private var cheatSheet: CheatSheetController?
    private var layerStatus: LayerStatusController?
    private var editorWindow: NSWindow?
    private var onboarding: PermissionWindowController?
    private lazy var preferences = PreferencesWindowController(model: model)

    private static var isUIPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-preview")
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        MainMenu.install(target: self)
        model.onOpenProSettings = { [weak self] in self?.preferences.show(page: .pro) }

        guard !Self.isUIPreview else {
            NSApp.setActivationPolicy(.regular)

            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--history") {
                    let hosting = NSHostingController(rootView: ProfileHistoryPreview())
                    hosting.safeAreaRegions = []
                    let window = EditorWindow(contentViewController: hosting)
                    window.styleMask = [
                        .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
                    ]
                    window.title = "History preview"
                    window.titleVisibility = .hidden
                    window.titlebarAppearsTransparent = true
                    window.configureEditorChrome()
                    window.isReleasedWhenClosed = false
                    window.contentMinSize = NSSize(width: 900, height: 620)
                    window.setContentSize(NSSize(width: 1040, height: 740))
                    window.center()
                    window.showOnActiveSpace()
                    editorWindow = window
                    capturePreviewIfRequested(window)
                    return
                }
            #endif

            if ProcessInfo.processInfo.arguments.contains("--onboarding") {
                let onboarding = PermissionWindowController(
                    model: model, onOpenSettings: {}, onClose: {})
                self.onboarding = onboarding
                onboarding.show()
                if let window = onboarding.window { capturePreviewIfRequested(window) }
                return
            }

            if ProcessInfo.processInfo.arguments.contains("--settings") {
                preferences.show()
                if let window = preferences.window { capturePreviewIfRequested(window) }
                return
            }

            if ProcessInfo.processInfo.arguments.contains("--panel") {
                let menuBar = MenuBarController(model: model)
                self.menuBar = menuBar
                menuBar.presentForPreview()
                return
            }

            showEditor()
            editorWindow?.level = .floating
            editorWindow?.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            if let editorWindow { capturePreviewIfRequested(editorWindow) }
            return
        }
        if CloudProfileConfiguration.current != nil { NSApp.registerForRemoteNotifications() }
        startNormally()
    }

    private func capturePreviewIfRequested(_ window: NSWindow) {
        #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("--snapshot") else { return }
            if ProcessInfo.processInfo.arguments.contains("--light") {
                window.appearance = NSAppearance(named: .aqua)
            } else if ProcessInfo.processInfo.arguments.contains("--dark") {
                window.appearance = NSAppearance(named: .darkAqua)
            }
            if ProcessInfo.processInfo.arguments.contains("--compact") {
                window.setContentSize(window.contentMinSize)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let view = window.contentView?.superview else { return }
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    return
                }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    try? data.write(to: URL(fileURLWithPath: "/tmp/tenuo-native-preview.png"))
                }
            }
        #endif
    }

    private func startNormally() {
        model.startUpdater()

        let menuBar = MenuBarController(model: model)
        menuBar.onOpenEditor = { [weak self] in self?.showEditor() }
        menuBar.onOpenPreferences = { [weak self] in self?.preferences.show() }
        self.menuBar = menuBar

        let cheatSheet = CheatSheetController(model: model)
        cheatSheet.isEnabled = controller.preferences.showsCheatSheet
        self.cheatSheet = cheatSheet

        let layerStatus = LayerStatusController(model: model)
        self.layerStatus = layerStatus

        let onboarding = PermissionWindowController(
            model: model,
            onOpenSettings: { [weak self] in
                self?.controller.openAccessibilitySettings()
            },
            onClose: { [weak self] in self?.onboardingDidClose() }
        )
        self.onboarding = onboarding

        controller.onStateChanged = { [weak self, weak menuBar, weak cheatSheet] in
            menuBar?.refresh()
            if let self { cheatSheet?.isEnabled = controller.preferences.showsCheatSheet }
        }
        controller.onPermissionMissing = { [weak self] in self?.showOnboarding() }
        controller.onPermissionGranted = { [weak onboarding] in onboarding?.dismiss() }
        controller.onActiveLayersChanged = { [weak cheatSheet, weak layerStatus] states in
            cheatSheet?.setActiveLayer(states.last?.index)
            layerStatus?.setActiveLayers(states)
        }

        controller.start()
    }

    private func showEditor() {
        NSApp.setActivationPolicy(.regular)

        if let editorWindow {
            editorWindow.showOnActiveSpace()
            return
        }

        let hosting = NSHostingController(
            rootView: LayerEditorView(model: model) { [weak self] in self?.preferences.show() }
        )
        hosting.safeAreaRegions = []
        let window = EditorWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.configureEditorChrome()
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(DS.Surface.window)
        window.setContentSize(NSSize(width: 1180, height: 700))
        window.contentMinSize = NSSize(width: 1080, height: 620)
        window.delegate = self
        window.center()
        window.showOnActiveSpace()
        editorWindow = window
    }

    private func showOnboarding() {
        NSApp.setActivationPolicy(.regular)
        onboarding?.show()
    }

    private func onboardingDidClose() {
        guard editorWindow?.isVisible != true else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === editorWindow else { return }
        guard !Self.isUIPreview else { return }
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            if controller.isTrusted {
                showEditor()
            } else {
                showOnboarding()
            }
        }
        return true
    }

    @objc func menuOpenSettings(_: Any?) { preferences.show() }
    @objc func menuOpenEditor(_: Any?) { showEditor() }
    @objc func menuNewProfile(_: Any?) { model.newProfile() }
    @objc func menuImportProfile(_: Any?) { model.importProfileFromPanel() }
    @objc func menuExportProfile(_: Any?) { model.exportProfileToPanel() }

    @objc func menuNewFromPreset(_ sender: NSMenuItem) {
        guard Presets.all.indices.contains(sender.tag) else { return }
        let preset = Presets.all[sender.tag]
        model.addProfile(from: preset, named: preset.name)
    }

    func applicationWillTerminate(_: Notification) {
        controller.shutDown()
    }

    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool { true }
}
