import SwiftUI

struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateController
    var onOpenEditor: () -> Void
    var onOpenPreferences: () -> Void

    private static let width: CGFloat = 460

    private var featured: Layer? { model.profile.triggeredLayers.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if model.isTrusted {
                if let featured {
                    separator
                    board(featured)
                }
                if !model.profile.triggeredLayers.isEmpty {
                    separator
                    layers
                }
                if model.profiles.count > 1 {
                    separator
                    profiles
                }
            } else {
                separator
                permissionNotice
            }

            if case let .available(version) = updates.status {
                separator
                updateRow(version)
            }

            separator
            footer
        }
        .frame(width: Self.width)
    }

    private var separator: some View {
        Divider().opacity(0.4).padding(.horizontal, 11)
    }

    private var header: some View {
        HStack(spacing: 9) {
            AppMark(size: 24)
                .opacity(model.isActive ? 1 : 0.45)

            VStack(alignment: .leading, spacing: 0) {
                Text("Tenuo").font(DS.Typography.title)
                Text(statusText)
                    .font(DS.Typography.label)
                    .foregroundStyle(DS.Ink.tertiary)
            }

            Spacer(minLength: 8)

            AppSwitch(
                isOn: Binding(
                    get: { model.isEnabled },
                    set: { model.isEnabled = $0 }),
                label: "Enable Tenuo",
                isEnabled: model.isTrusted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var statusText: String {
        guard model.isTrusted else { return "Needs Accessibility access" }
        guard model.isEnabled else { return "Off" }
        let count = model.profile.triggeredLayers.count
        return "On · \(count) layer\(count == 1 ? "" : "s")"
    }

    private func board(_ layer: Layer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(layer.name).sectionLabel()
                Text(layer.trigger?.displayLabel ?? "")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Ink.secondary)
                Spacer(minLength: 0)
            }

            KeyboardLayoutView(
                mappings: layer.mappings,
                triggerKey: layer.trigger?.key,
                width: Self.width - 24,
                isInteractive: false
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private var layers: some View {
        VStack(spacing: 2) {
            ForEach(model.profile.triggeredLayers) { layer in
                HStack(spacing: 8) {
                    ChordBadge(layer: layer)
                    Text(layer.name)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Ink.secondary)
                    Spacer(minLength: 8)
                    Text(detail(for: layer))
                        .font(DS.Typography.mono)
                        .foregroundStyle(DS.Ink.tertiary)
                }
                .frame(height: DS.Metrics.row)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func detail(for layer: Layer) -> String {
        guard !layer.mappings.isEmpty else {
            return layer.outputMode.injectsHyper ? "Hyper" : "Pass through"
        }
        return "\(layer.mappings.count) key\(layer.mappings.count == 1 ? "" : "s")"
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 1) {
            SectionHeader(title: "Profiles")
                .padding(.bottom, 3)

            ForEach(model.profiles) { profile in
                SidebarRow(
                    title: profile.name,
                    isSelected: profile.id == model.activeProfileID,
                    action: { model.selectProfile(profile.id) }
                ) {
                    Image(systemName: "checkmark")
                        .font(.system(size: DS.Icon.small, weight: .semibold))
                        .opacity(profile.id == model.activeProfileID ? 1 : 0)
                        .frame(width: 10)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Accessibility access required", systemImage: "exclamationmark.triangle.fill")
                .font(DS.Typography.body.weight(.medium))
                .foregroundStyle(DS.Signal.warning)

            Text(
                "Tenuo needs Accessibility access to remap keys. Enable it in System Settings to start using your profiles."
            )
            .font(DS.Typography.label)
            .foregroundStyle(DS.Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)

            PrimaryButton(title: "Open System Settings", action: model.openAccessibilitySettings)
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    private func updateRow(_ version: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(DS.Signal.ok)
                .frame(width: 6, height: 6)
            Text("Version \(version) is available")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Ink.primary)
            Spacer(minLength: 8)
            PrimaryButton(title: "Install update") { updates.install() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            FooterRow(title: "Edit layers…", action: onOpenEditor)
            FooterRow(title: "Settings…", action: onOpenPreferences)
            FooterRow(title: "Quit Tenuo", action: model.quit)
        }
    }
}
