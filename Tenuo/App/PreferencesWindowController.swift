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
                    ? "Allow \(AppIdentity.displayName) in System Settings → General → Login Items."
                    : nil
            ) {
                InspectorRow(label: "Enable \(AppIdentity.displayName)") {
                    AppSwitch(
                        isOn: Binding(
                            get: { model.isEnabled },
                            set: { model.isEnabled = $0 }),
                        label: "Enable \(AppIdentity.displayName)")
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
                "Active layer",
                footer:
                    "Show the active layer after you hold its trigger for a moment."
            ) {
                InspectorRow(label: "Show active layer while holding", divider: false) {
                    AppSwitch(
                        isOn: Binding(
                            get: { model.showsCheatSheet },
                            set: { model.showsCheatSheet = $0 }),
                        label: "Show the active layer while holding a trigger")
                }
            }

            group(
                "Timing",
                footer:
                    "How long you can hold a trigger before \(AppIdentity.displayName) treats it as a hold instead of a tap."
            ) {
                InspectorRow(label: "Tap window", divider: false) {
                    HStack(spacing: DS.Space.small) {
                        AppSlider(
                            value: Binding(
                                get: { Double(model.profile.tapThresholdMilliseconds) },
                                set: { model.profile.tapThresholdMilliseconds = Int($0) }
                            ),
                            range: 80...500, step: 10, label: "Tap window"
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
                    InspectorRow(label: "Check for updates automatically") {
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
                            QuietButton(title: "Check now") { model.updates.check() }
                                .opacity(model.updates.status.isBusy ? 0.4 : 1)
                        }
                    }
                }
            }

            group(
                "Permission",
                footer:
                    "\(AppIdentity.displayName) only needs Accessibility access to remap keys. It does not need Input Monitoring."
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
                        QuietButton(
                            title: "Open System Settings", action: model.openAccessibilitySettings
                        )
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
            ? "\(AppIdentity.displayName) checks tenuo.app in the background for new versions. It does not collect usage data or install updates without asking you."
            : "\(AppIdentity.displayName) checks tenuo.app only when you ask it to look for a new version. It does not collect usage data."
    }

    private var updateStatus: String {
        switch model.updates.status {
        case .idle:
            guard let checked = model.updates.lastChecked else { return "Not checked" }
            return "Checked \(Self.relative.localizedString(for: checked, relativeTo: Date()))"
        case .checking: return "Checking…"
        case .upToDate: return "Up to date"
        case let .available(version): return "Version \(version) is available"
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
