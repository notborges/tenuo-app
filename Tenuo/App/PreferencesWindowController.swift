import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController {
    private var window: NSWindow?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if let window {
            window.showOnActiveSpace()
            return
        }

        let hosting = NSHostingController(
            rootView: PreferencesView(model: model, updates: model.updates)
        )
        hosting.safeAreaRegions = []
        let created = NSWindow(contentViewController: hosting)
        created.title = "Settings"
        created.styleMask = [.titled, .closable, .fullSizeContentView]
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.isMovableByWindowBackground = true
        created.isReleasedWhenClosed = false
        created.backgroundColor = NSColor(DS.Surface.sidebar)
        created.isRestorable = false
        hosting.view.layoutSubtreeIfNeeded()
        created.setContentSize(hosting.view.fittingSize)
        created.center()
        created.showOnActiveSpace()
        window = created
    }
}

private struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateController

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.medium) {
            group(
                "General",
                footer: model.launchNeedsApproval
                    ? "Approve in System Settings → General → Login Items."
                    : nil
            ) {
                InspectorRow(label: "Enable Tenuo") {
                    AppSwitch(
                        isOn: Binding(
                            get: { model.isEnabled },
                            set: { model.isEnabled = $0 }),
                        label: "Enable Tenuo")
                }
                InspectorRow(label: "Launch at login", divider: false) {
                    AppSwitch(
                        isOn: Binding(
                            get: { model.launchesAtLogin },
                            set: { _ in model.toggleLaunchAtLogin() }),
                        label: "Launch at login")
                }
            }

            group(
                "Layer hint",
                footer:
                    "The board appears after a short hold, so anyone fluent never sees it. Switch it off if you would rather nothing appeared at all."
            ) {
                InspectorRow(label: "Show while holding", divider: false) {
                    AppSwitch(
                        isOn: Binding(
                            get: { model.showsCheatSheet },
                            set: { model.showsCheatSheet = $0 }),
                        label: "Show the layer hint while holding a trigger")
                }
            }

            group(
                "Timing",
                footer: "How long a trigger may be held and still count as a tap."
            ) {
                InspectorRow(label: "Tap threshold", divider: false) {
                    HStack(spacing: DS.Space.small) {
                        AppSlider(
                            value: Binding(
                                get: { Double(model.profile.tapThresholdMilliseconds) },
                                set: { model.profile.tapThresholdMilliseconds = Int($0) }
                            ),
                            range: 80...500, step: 10, label: "Tap threshold"
                        )
                        Text("\(model.profile.tapThresholdMilliseconds) ms")
                            .font(DS.Typography.label.monospacedDigit())
                            .foregroundStyle(DS.Ink.secondary)
                            .frame(width: 46, alignment: .trailing)
                    }
                }
            }

            if model.updatesAvailable {
                group("Updates", footer: updatesFooter) {
                    InspectorRow(label: "Check automatically") {
                        AppSwitch(
                            isOn: Binding(
                                get: { model.checksForUpdates },
                                set: { model.checksForUpdates = $0 }),
                            label: "Check for updates automatically")
                    }
                    InspectorStatusRow(text: updateStatus, ink: updateStatusInk) {
                        if case let .available(version) = model.updates.status {
                            PrimaryButton(title: "Update to \(version)") {
                                model.updates.install()
                            }
                        } else {
                            QuietButton(title: "Check Now") { model.updates.check() }
                                .opacity(model.updates.status.isBusy ? 0.4 : 1)
                        }
                    }
                }
            }

            group(
                "Permission",
                footer:
                    "The only permission Tenuo asks for. It never opens a HID device, so Input Monitoring is not required."
            ) {
                InspectorRow(label: "Accessibility", divider: false) {
                    if model.isTrusted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Granted")
                        }
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Signal.ok)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        QuietButton(title: "Open Settings", action: model.openAccessibilitySettings)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }

            group("About") {
                InspectorRow(label: "Version", divider: false) {
                    Text(version)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Ink.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, DS.Space.large)
        .padding(.top, DS.Metrics.titlebar)
        .padding(.bottom, DS.Space.large)
        .frame(width: 460)
        .background(DS.Surface.sidebar)
    }

    private var updatesFooter: String {
        model.checksForUpdates
            ? "Tenuo asks tenuo.app for the latest version number, in the background. That request is the only thing it ever sends anywhere: no analytics, no accounts, nothing about you or your machine. It never installs on its own: an update appears here and in the menu bar, and waits."
            : "Tenuo will not contact anything on its own. Checking by hand does use the network. Asking tenuo.app for the latest version number is the only thing Tenuo ever sends anywhere, and it carries nothing about you or your machine."
    }

    private var updateStatus: String {
        switch model.updates.status {
        case .idle:
            guard let checked = model.updates.lastChecked else { return "Not checked" }
            return "Checked \(Self.relative.localizedString(for: checked, relativeTo: Date()))"
        case .checking: return "Checking…"
        case .upToDate: return "Up to date"
        case let .available(version): return "Version \(version) available"
        case let .downloading(done): return "Downloading \(Int(done * 100))%"
        case .installing: return "Installing…"
        case let .failed(message): return message
        }
    }

    private var updateStatusInk: Color {
        switch model.updates.status {
        case .failed: return DS.Signal.destructive
        case .available: return DS.Ink.primary
        default: return DS.Ink.secondary
        }
    }

    private static let relative = RelativeDateTimeFormatter()

    private func group<Content: View>(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        InspectorCard(title: title, footer: footer, content: content)
    }
}
