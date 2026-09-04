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
        app.appearance = NSAppearance(named: .darkAqua)
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
extension NSWindow {
    func showOnActiveSpace() {
        collectionBehavior.insert(.moveToActiveSpace)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
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
    private var editorWindow: NSWindow?
    private var onboarding: PermissionWindowController?
    private lazy var preferences = PreferencesWindowController(model: model)

    private static var isUIPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-preview")
    }

    func applicationDidFinishLaunching(_: Notification) {
        MainMenu.install(target: self)

        guard !Self.isUIPreview else {
            NSApp.setActivationPolicy(.regular)

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
            return
        }
        startNormally()
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
        controller.onActiveLayerChanged = { [weak cheatSheet] index in
            cheatSheet?.setActiveLayer(index)
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
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
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
