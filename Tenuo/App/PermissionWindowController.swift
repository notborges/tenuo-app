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
        newWindow.title = "\(AppIdentity.displayName) needs Accessibility access"
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
                "This source build does not check for updates. \(AppIdentity.displayName) does not collect usage data."
        }
        return model.checksForUpdates
            ? "If you turn on automatic checks, \(AppIdentity.displayName) contacts tenuo.app in the background to look for new versions. It does not collect usage data."
            : "\(AppIdentity.displayName) only contacts tenuo.app when you ask it to check for a new version. It does not collect usage data."
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
                "\(AppIdentity.displayName) needs Accessibility access to remap keys. Turn it on in System Settings, then come back here."
            )
            .font(DS.Typography.body)
            .foregroundStyle(DS.Ink.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 400)
            .padding(.bottom, DS.Space.medium)

            PrimaryButton(title: "Open System Settings", action: onOpenSettings)
                .padding(.bottom, DS.Space.medium)

            optionalSettings

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
        .frame(width: 400, alignment: .leading)
        .padding(.bottom, DS.Space.medium)
    }
}

private struct OnboardingSettingRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: DS.Space.small) {
                Text(title)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Ink.primary)
                Spacer(minLength: DS.Space.small)
                OnboardingSwitch(isOn: isOn)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

private struct OnboardingSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? DS.Selection.solid : Color.white.opacity(0.14))
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? DS.Selection.solidInk : Color.white.opacity(0.55))
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 2)
            }
            .animation(DS.Motion.fill, value: isOn)
            .accessibilityHidden(true)
    }
}
