import SwiftUI

struct LicenseSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var license: LicenseManager
    @State private var key = ""
    @FocusState private var isLicenseKeyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 14) {
                AppMark(size: 44)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(license.hasProAccess ? "Tenuo Pro is yours" : "Make every key yours")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        ProBadge()
                    }
                    Text(
                        license.hasProAccess
                            ? "Your tools for a more personal keyboard."
                            : "More ways to use your keys. One purchase."
                    )
                    .font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                }
            }
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading,
                spacing: 18
            ) {
                benefit("app.badge", "Mac actions", "Apps, files, links & Shortcuts")
                benefit(
                    "square.stack.3d.up", "App-specific mappings", "A different job in every app")
                benefit("clock.arrow.circlepath", "Profile history", "Return to an earlier setup")
                benefit("icloud", "iCloud sync", "Your profiles, on your Macs")
            }
            .padding(18)
            .background(DS.Surface.raised, in: RoundedRectangle(cornerRadius: 20))
            if !license.hasProAccess {
                Link(destination: URL(string: "https://tenuo.app/#pricing")!) {
                    HStack {
                        Text("Get Tenuo Pro")
                        Image(systemName: "arrow.up.right").font(
                            .system(size: 11, weight: .semibold))
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(RoundedActionStyle(prominent: true))
            }
            if license.hasProAccess {
                InspectorCard(
                    title: "Dock icon",
                    footer:
                        "A graphite finish with a silver Pro detail. Only changes the icon while Tenuo is running."
                ) {
                    HStack(spacing: 12) {
                        if let url = Bundle.main.url(
                            forResource: "TenuoPro", withExtension: "icns"),
                            let icon = NSImage(contentsOf: url)
                        {
                            Image(nsImage: icon).resizable().frame(width: 52, height: 52)
                                .accessibilityHidden(true)
                        }
                        Text("Use the Pro icon").font(DS.Typography.label)
                        Spacer()
                        Toggle("Use the Pro icon", isOn: $model.usesProDockIcon)
                            .toggleStyle(.switch).labelsHidden()
                    }.padding(12)
                }
            }
            licenseCard
        }
    }

    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 19, weight: .regular))
                .foregroundStyle(DS.Ink.secondary).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DS.Typography.label.weight(.medium))
                Text(detail).font(DS.Typography.footnote).foregroundStyle(DS.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var licenseCard: some View {
        InspectorCard(
            title: license.hasProAccess ? "License" : "Already purchased?", footer: footer
        ) {
            if license.isDevelopmentPreview {
                InspectorStatusRow(text: "Debug build", divider: false) {
                    Text("Pro preview enabled")
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Ink.tertiary)
                }
            } else if license.state == .notConfigured {
                InspectorStatusRow(text: "Source build", divider: false) {
                    Text("Licensing is not configured")
                        .font(DS.Typography.label)
                        .foregroundStyle(DS.Ink.tertiary)
                }
            } else if license.hasProAccess {
                InspectorStatusRow(text: statusText) {
                    QuietButton(title: "Check now", action: model.checkLicense)
                        .disabled(license.isBusy)
                }

                InspectorRow(label: "License", divider: false) {
                    Text(license.displayKey ?? "Active")
                        .font(DS.Typography.mono)
                        .foregroundStyle(DS.Ink.secondary)
                }

                InspectorWideRow(label: "This Mac", divider: false) {
                    InspectorDestructiveButton(
                        title: "Deactivate license",
                        confirm: "Deactivate Tenuo Pro on this Mac?",
                        action: model.deactivateLicense
                    )
                    .disabled(license.isBusy)
                }
            } else {
                licenseEntry
            }
        }
    }

    private var licenseEntry: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 15)).foregroundStyle(DS.Ink.tertiary)
                    .accessibilityHidden(true)
                TextField("Paste your license key", text: $key)
                    .textFieldStyle(.plain)
                    .font(DS.Typography.body)
                    .frame(height: DS.Metrics.controlHeight)
                    .focused($isLicenseKeyFocused)
                    .disabled(license.isBusy)
                    .accessibilityLabel("License key")
                    .onSubmit(activateLicense)
                Button("Activate", action: activateLicense)
                    .buttonStyle(RoundedActionStyle(prominent: true))
                    .disabled(!canActivate)
            }
            .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)

            if license.isBusy {
                Text(progressText)
                    .font(DS.Typography.footnote).foregroundStyle(DS.Ink.tertiary)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            } else if let message = license.message {
                Text(message)
                    .font(DS.Typography.footnote)
                    .foregroundStyle(
                        license.state == .invalid || license.state == .failed
                            ? DS.Signal.destructive : DS.Ink.tertiary
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(
                    isLicenseKeyFocused ? DS.Line.strong : .clear, lineWidth: 1
                )
                .allowsHitTesting(false)
        }
    }

    private var canActivate: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !license.isBusy
    }

    private func activateLicense() {
        guard canActivate else { return }
        model.activateLicense(key)
    }

    private var statusText: String {
        switch license.state {
        case .offlinePro: return "Pro · offline"
        case .validating: return "Checking license…"
        case .deactivating: return "Deactivating…"
        default: return "Pro is active"
        }
    }

    private var progressText: String {
        switch license.state {
        case .activating: return "Activating license…"
        case .validating: return "Checking license…"
        case .deactivating: return "Deactivating license…"
        default: return "Working…"
        }
    }

    private var footer: String {
        if license.isDevelopmentPreview {
            return "Pro features are enabled locally for this Debug build. No license is used."
        }

        if license.hasProAccess && license.state != .offlinePro {
            return
                "Mac actions, app-specific mappings, profile history, and iCloud profile sync are unlocked."
        }

        switch license.state {
        case .notConfigured:
            return "This source build has no official license configuration."
        case .invalid:
            return license.message ?? "Enter a valid Tenuo Pro license key."
        case .failed:
            return license.message ?? "Tenuo could not verify the license."
        case .offlinePro:
            return "Tenuo will check again when you are back online."
        default:
            return
                "Use the license key from your purchase confirmation."
        }
    }
}
