import SwiftUI

struct LicenseSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var license: LicenseManager
    @State private var key = ""

    var body: some View {
        InspectorCard(title: "Tenuo Pro", footer: footer) {
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
                InspectorWideRow(label: "License key", divider: false) {
                    VStack(alignment: .leading, spacing: DS.Space.small) {
                        HStack(spacing: DS.Space.small) {
                            TextField("Paste your license key", text: $key)
                                .textFieldStyle(.roundedBorder)

                            PrimaryButton(title: "Activate") {
                                model.activateLicense(key)
                            }
                            .disabled(
                                key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || license.isBusy)
                        }

                        if license.isBusy {
                            Text(progressText)
                                .font(DS.Typography.footnote)
                                .foregroundStyle(DS.Ink.tertiary)
                        } else if let message = license.message {
                            Text(message)
                                .font(DS.Typography.footnote)
                                .foregroundStyle(
                                    license.state == .invalid || license.state == .failed
                                        ? DS.Signal.destructive : DS.Ink.tertiary
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
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
            return "Mac actions, app-specific layers, and profile history are unlocked."
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
                "Unlock Mac actions, app-specific layers, and profile history with a Tenuo Pro license."
        }
    }
}
