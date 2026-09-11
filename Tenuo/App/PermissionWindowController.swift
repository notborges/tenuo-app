import AppKit
import SwiftUI

@MainActor
final class PermissionWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
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
        let newWindow = EditorWindow(contentViewController: hosting)
        newWindow.title = "\(AppIdentity.displayName) needs Accessibility access"
        newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.configureEditorChrome()
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
                "This source build does not check for updates. \(AppIdentity.displayName) does not collect usage data."
        }
        return model.checksForUpdates
            ? "With automatic checks on, \(AppIdentity.displayName) contacts tenuo.app in the background to look for new versions. It does not collect usage data."
            : "\(AppIdentity.displayName) only contacts tenuo.app when you ask it to check for a new version. It does not collect usage data."
    }

    private var shipped: Layer? { Presets.library.first?.triggeredLayers.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                AppMark(size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Tenuo")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Set up your keyboard layers.")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Ink.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Hold Caps Lock, then press H, J, K or L")
                        .font(DS.Typography.label.weight(.semibold))
                    Spacer()
                    Text("←  ↓  ↑  →")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Ink.secondary)
                }

                KeyboardLayoutView(
                    mappings: shipped?.mappings ?? [:],
                    triggerKey: shipped?.trigger?.key,
                    width: 472,
                    isInteractive: false
                )

                Text("Tap Caps Lock for Escape. Customize your keys in the layer editor.")
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised")
                    Text("Allow keyboard remapping")
                }
                .font(DS.Typography.title)

                Text(
                    "Enable \(AppIdentity.displayName) in System Settings → Accessibility. This window closes automatically when access is ready."
                )
                .font(DS.Typography.body)
                .foregroundStyle(DS.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button("Open System Settings", action: onOpenSettings)
                    .buttonStyle(RoundedActionStyle(prominent: true))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Metrics.panelInset)
            .glassCard()

            optionalSettings

            Text(updatesLine)
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DS.Ink.primary)
        .padding(.horizontal, 24)
        .padding(.top, 52)
        .padding(.bottom, 24)
        .frame(width: 520)
        .background(DS.Surface.window)
    }

    private var optionalSettings: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            Text("Optional").sectionLabel()

            VStack(spacing: 0) {
                OnboardingSettingRow(
                    title: "Start \(AppIdentity.displayName) at login",
                    isOn: Binding(
                        get: { model.launchesAtLogin },
                        set: { _ in model.toggleLaunchAtLogin() })
                )

                if model.updatesAvailable {
                    Divider()
                        .opacity(0.35)
                        .padding(.leading, 14)

                    OnboardingSettingRow(
                        title: "Check for updates automatically",
                        isOn: Binding(
                            get: { model.checksForUpdates },
                            set: { model.checksForUpdates = $0 })
                    )
                }
            }
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Surface.raised)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.Line.hairline, lineWidth: 0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingSettingRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: DS.Space.small) {
            Text(title)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Ink.primary)
            Spacer(minLength: DS.Space.small)
            AppSwitch(isOn: $isOn, label: title)
        }
        .padding(.horizontal, DS.Metrics.panelInset)
        .frame(minHeight: 44)
    }
}
