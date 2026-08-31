import AppKit
import SwiftUI

@MainActor
final class PermissionWindowController {
    private var window: NSWindow?
    private let model: AppModel
    private let onOpenSettings: () -> Void

    init(model: AppModel, onOpenSettings: @escaping () -> Void) {
        self.model = model
        self.onOpenSettings = onOpenSettings
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
        newWindow.title = "Welcome to Tenuo"
        newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false
        newWindow.backgroundColor = NSColor(DS.Surface.window)
        newWindow.isRestorable = false
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
}

private struct PermissionView: View {
    @ObservedObject var model: AppModel
    let onOpenSettings: () -> Void

    private var updatesLine: String {
        guard model.updatesAvailable else {
            return
                "No other permission, no accounts, no analytics. This build has no update server behind it, so it never opens a network connection at all."
        }
        return model.checksForUpdates
            ? "No other permission, no accounts, no analytics. Tenuo asks tenuo.app for the latest version number and sends nothing else, ever."
            : "No other permission, no accounts, no analytics. Tenuo uses the network only when it looks for an update, and it will not do that on its own."
    }

    private var shipped: Layer? { Presets.library.first?.triggeredLayers.first }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .padding(.bottom, DS.Space.small)

            Text("One key. A whole layer under it.")
                .font(DS.Typography.display)
                .multilineTextAlignment(.center)
                .padding(.bottom, DS.Space.tight)

            Text(
                "Hold your trigger key and the keys under your fingers become whatever you map them to. Tap it for Escape."
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
                "Tenuo needs Accessibility permission to read and replace keystrokes. It starts working the moment you grant it."
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
                        Text("Check tenuo.app for updates")
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
