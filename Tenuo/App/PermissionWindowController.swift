import AppKit
import SwiftUI

@MainActor
final class PermissionWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: AppModel
    private let onOpenSettings: () -> Void
    private let onClose: () -> Void

    init(
        model: AppModel,
        onOpenSettings: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.model = model
        self.onOpenSettings = onOpenSettings
        self.onClose = onClose
        super.init()
    }

    func show() {
        if let window {
            window.showOnActiveSpace()
            return
        }

        let hosting = NSHostingController(
            rootView: PermissionView(model: model, onOpenSettings: onOpenSettings)
        )
        hosting.safeAreaRegions = []
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Tenuo needs Accessibility access"
        newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false
        newWindow.backgroundColor = NSColor(DS.Surface.window)
        newWindow.isRestorable = false
        newWindow.delegate = self
        hosting.view.layoutSubtreeIfNeeded()
        newWindow.setContentSize(hosting.view.fittingSize)
        newWindow.center()
        newWindow.showOnActiveSpace()
        window = newWindow
    }

    func dismiss() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
        onClose()
    }
}

private struct PermissionView: View {
    @ObservedObject var model: AppModel
    let onOpenSettings: () -> Void

    private var updatesLine: String {
        guard model.updatesAvailable else {
            return
                "This source build does not check for updates. Tenuo does not collect usage data."
        }
        return model.checksForUpdates
            ? "If you turn on automatic checks, Tenuo contacts tenuo.app in the background to look for new versions. It does not collect usage data."
            : "Tenuo only contacts tenuo.app when you ask it to check for a new version. It does not collect usage data."
    }

    private var shipped: Layer? { Presets.library.first?.triggeredLayers.first }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .padding(.bottom, DS.Space.small)

            Text("Use a layer key for more shortcuts.")
                .font(DS.Typography.display)
                .multilineTextAlignment(.center)
                .padding(.bottom, DS.Space.tight)

            Text(
                "Hold the layer key, then press one of the highlighted keys. Caps Lock is the default and sends Escape when tapped; you can choose a different layer key in Settings."
            )
            .font(DS.Typography.body)
            .foregroundStyle(DS.Ink.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 380)
            .padding(.bottom, DS.Space.large)

            KeyboardLayoutView(
                mappings: shipped?.mappings ?? [:],
                triggerKey: shipped?.trigger?.key,
                width: 424,
                isInteractive: false
            )

            Divider()
                .opacity(0.35)
                .padding(.vertical, DS.Space.large)

            Text(
                "Tenuo needs Accessibility access to remap keys. Turn on Tenuo in System Settings, then come back here."
            )
            .font(DS.Typography.body)
            .foregroundStyle(DS.Ink.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 400)
            .padding(.bottom, DS.Space.medium)

            PrimaryButton(title: "Open System Settings", action: onOpenSettings)
                .padding(.bottom, DS.Space.medium)

            if model.updatesAvailable {
                Button {
                    model.checksForUpdates.toggle()
                } label: {
                    HStack(spacing: DS.Space.tight) {
                        Image(
                            systemName: model.checksForUpdates
                                ? "checkmark.square.fill" : "square"
                        )
                        .font(.system(size: DS.Icon.regular))
                        .foregroundStyle(
                            model.checksForUpdates
                                ? DS.Ink.primary : DS.Ink.tertiary)
                        Text("Check for updates automatically")
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Ink.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, DS.Space.tight)

            }

            Text(updatesLine)
                .font(DS.Typography.label)
                .foregroundStyle(DS.Ink.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 400)
        }
        .padding(.horizontal, 28)
        .padding(.top, DS.Metrics.titlebar)
        .padding(.bottom, 28)
        .frame(width: 480)
        .background(DS.Surface.window)
    }
}
