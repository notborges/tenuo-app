import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController {
    private(set) var window: NSWindow?
    private let model: AppModel
    private let navigation = PreferencesNavigation()

    init(model: AppModel) {
        self.model = model
    }

    func show(page: PreferencesPage? = nil) {
        if let page { navigation.page = page }
        if let window {
            window.showOnActiveSpace()
            return
        }

        let hosting = NSHostingController(
            rootView: PreferencesView(model: model, updates: model.updates, navigation: navigation)
        )
        hosting.safeAreaRegions = []
        let created = EditorWindow(contentViewController: hosting)
        created.title = "Settings"
        created.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        created.titleVisibility = .hidden
        created.titlebarAppearsTransparent = true
        created.configureEditorChrome()
        created.isMovableByWindowBackground = true
        created.isReleasedWhenClosed = false
        created.backgroundColor = NSColor(DS.Surface.sidebar)
        created.isRestorable = false
        hosting.view.layoutSubtreeIfNeeded()
        created.setContentSize(NSSize(width: 560, height: 620))
        created.center()
        created.showOnActiveSpace()
        window = created
    }
}

enum PreferencesPage: String, CaseIterable {
    case general = "General", pro = "Tenuo Pro", about = "About & Updates"
}

@MainActor
private final class PreferencesNavigation: ObservableObject {
    @Published var page: PreferencesPage = {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-preview") {
                if arguments.contains("--settings-pro") { return .pro }
                if arguments.contains("--settings-about") { return .about }
            }
        #endif
        return .general
    }()

}

private struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateController

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    @ObservedObject var navigation: PreferencesNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppMark(size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(AppIdentity.displayName)
                        .font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                }
                Spacer()
            }
            .padding(.top, 52)
            .padding(.bottom, 20)

            HStack(spacing: 4) {
                ForEach(PreferencesPage.allCases, id: \.self) { item in
                    Button {
                        navigation.page = item
                    } label: {
                        Text(item.rawValue)
                            .font(DS.Typography.label)
                            .foregroundStyle(
                                navigation.page == item ? DS.Ink.primary : DS.Ink.secondary
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                navigation.page == item ? DS.Selection.fill : .clear,
                                in: RoundedRectangle(
                                    cornerRadius: DS.Radius.field, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(navigation.page == item ? .isSelected : [])
                }
            }
            .padding(4)
            .background(DS.Surface.sidebar, in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch navigation.page {
                    case .general: general
                    case .pro: LicenseSettingsView(model: model, license: model.license)
                    case .about: about
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 24)
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .background(DS.Surface.window)
        .foregroundStyle(DS.Ink.primary)
        .tint(DS.Selection.solid)
    }

    private var general: some View {
        Group {
            group("Everyday") {
                SettingsPreferenceRow(
                    title: "Enable Tenuo", detail: "Apply your keyboard mappings."
                ) {
                    AppSwitch(
                        isOn: Binding(get: { model.isEnabled }, set: { model.isEnabled = $0 }),
                        label: "Enable Tenuo")
                }
                settingsDivider
                SettingsPreferenceRow(
                    title: "Launch at login",
                    detail: model.launchNeedsApproval
                        ? "Allow Tenuo in System Settings → General → Login Items."
                        : "Ready when you sign in to your Mac."
                ) {
                    AppSwitch(
                        isOn: Binding(
                            get: { model.launchesAtLogin },
                            set: { _ in model.toggleLaunchAtLogin() }),
                        label: "Launch at login")
                }
            }
            group("Keyboard") {
                SettingsPreferenceRow(
                    title: "Show active layer",
                    detail: "Preview the layer while holding its trigger."
                ) {
                    AppSwitch(
                        isOn: Binding(
                            get: { model.showsCheatSheet }, set: { model.showsCheatSheet = $0 }),
                        label: "Show active layer while holding its trigger")
                }
                settingsDivider
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Tap or hold").font(DS.Typography.body)
                        Spacer()
                        Text("\(model.profile.tapThresholdMilliseconds) ms")
                            .font(DS.Typography.label.monospacedDigit())
                            .foregroundStyle(DS.Ink.primary)
                    }
                    AppSlider(
                        value: Binding(
                            get: { Double(model.profile.tapThresholdMilliseconds) },
                            set: { model.profile.tapThresholdMilliseconds = Int($0) }),
                        range: 80...500, step: 10, label: "Tap window for \(model.profile.name)")
                    Text(
                        "Release within this time to count as a tap. Applies to “\(model.profile.name)”."
                    )
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            HStack(spacing: 8) {
                Image(systemName: model.isTrusted ? "checkmark.shield" : "exclamationmark.shield")
                    .foregroundStyle(model.isTrusted ? DS.Ink.secondary : DS.Signal.warning)
                Text(
                    model.isTrusted
                        ? "Accessibility access granted" : "Accessibility access is required"
                )
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Ink.secondary)
                Spacer(minLength: 4)
                if !model.isTrusted {
                    Button("Open Settings", action: model.openAccessibilitySettings)
                        .buttonStyle(RoundedActionStyle())
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var about: some View {
        Group {
            group("App") {
                SettingsPreferenceRow(
                    title: AppIdentity.displayName, detail: "Keyboard layers for your Mac."
                ) {
                    Text("Version \(version)").font(DS.Typography.label).foregroundStyle(
                        DS.Ink.secondary)
                }
            }
            if model.updatesAvailable {
                group("Updates", footer: updatesFooter) {
                    SettingsPreferenceRow(
                        title: "Automatic checks",
                        detail: "Look for new versions in the background."
                    ) {
                        AppSwitch(
                            isOn: Binding(
                                get: { model.checksForUpdates },
                                set: { model.checksForUpdates = $0 }),
                            label: "Check for updates automatically")
                    }
                    settingsDivider
                    InspectorStatusRow(text: updateStatus, ink: updateStatusInk) {
                        if case let .available(version) = updates.status {
                            Button("Update to \(version)") { updates.install() }
                                .buttonStyle(RoundedActionStyle(prominent: true))
                        } else {
                            Button("Check now") { updates.check() }
                                .buttonStyle(RoundedActionStyle())
                                .disabled(updates.status.isBusy)
                        }
                    }
                }
            }
            group(
                "Permissions",
                footer: "Accessibility lets Tenuo remap keys. Input Monitoring is not required."
            ) {
                SettingsPreferenceRow(
                    title: "Accessibility",
                    detail: model.isTrusted
                        ? "Tenuo can remap your keyboard."
                        : "Allow access to enable keyboard mappings."
                ) {
                    if model.isTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(DS.Typography.label).foregroundStyle(DS.Signal.ok)
                    } else {
                        Button("Open Settings", action: model.openAccessibilitySettings)
                            .buttonStyle(RoundedActionStyle())
                    }
                }
            }
        }
    }

    private var settingsDivider: some View {
        Divider().opacity(0.35).padding(.horizontal, 16)
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

private struct SettingsPreferenceRow<Control: View>: View {
    var title: String
    var detail: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DS.Typography.body).foregroundStyle(DS.Ink.primary)
                Text(detail).font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            control.fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 60)
    }
}
