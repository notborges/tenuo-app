import SwiftUI

struct ProfileSyncSettingsView: View {
    @ObservedObject var sync: ProfileSyncController
    @ObservedObject var license: LicenseManager
    let activate: () -> Void
    @State private var selectedConflict: ProfileSyncConflict?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "icloud")
                    .font(.system(size: 26, weight: .medium))
                    .frame(width: 52, height: 52)
                    .background(DS.Surface.raised, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your setup, on every Mac")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("Keep your profiles together with iCloud.")
                        .font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                }
            }
            if !license.hasProAccess {
                ProFeaturePrompt(
                    title: "A familiar setup on every Mac",
                    detail:
                        "Bring your profiles, mappings, and actions to your other Macs. Turn it on when you’re ready, using the same Apple Account.",
                    visual: "icloud", activate: activate
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                if sync.enabled {
                    HStack {
                        Text("Sync is paused until Pro is active.")
                            .font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                        Spacer()
                        QuietButton(title: "Turn off sync", action: sync.disable)
                    }.padding(.horizontal, 12)
                }
            } else {
                controls
            }
            VStack(alignment: .leading, spacing: 12) {
                detail(
                    "square.stack.3d.up", "Synced profiles",
                    "Layers, app overrides, and actions stay together.")
                detail(
                    "laptopcomputer", "Settings kept on this Mac",
                    "Your active profile, preferences, and history stay on this Mac. Files and Shortcuts may need to be linked here."
                )
            }
            .padding(.horizontal, 12)
        }
        .sheet(item: $selectedConflict) { conflict in
            ProfileSyncConflictView(sync: sync, conflict: conflict)
        }
    }

    @ViewBuilder private var controls: some View {
        InspectorCard {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync profiles with iCloud").font(DS.Typography.body)
                    Text(statusText).font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                }
                Spacer(minLength: 8)
                if sync.status == .checking { ProgressView().controlSize(.small) }
                AppSwitch(
                    isOn: Binding(
                        get: { sync.enabled },
                        set: { value in
                            if value { sync.prepare() } else { sync.disable() }
                        }), label: "Sync profiles with iCloud"
                )
                .disabled(
                    !sync.isConfigured || (!sync.enabled && (sync.isBusy || sync.preview != nil)))
            }
            .padding(16)
        }
        if sync.status == .checking {
            QuietButton(title: "Cancel", action: sync.cancelSetup).padding(.horizontal, 12)
        }
        if !sync.isConfigured {
            Text("iCloud sync is not available in this build. Your profiles are saved locally.")
                .font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                .padding(.horizontal, 12)
        } else if let profiles = sync.preview {
            InspectorCard(title: "Before you connect") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(sync.message ?? "Review the combined profiles.")
                        .font(DS.Typography.body)
                    ForEach(Array(profiles.enumerated()), id: \.offset) { _, name in
                        Label(name, systemImage: "square.stack.3d.up")
                            .font(DS.Typography.label)
                    }
                    Text(
                        "Your current profile stays selected. File access stays on this Mac; choose local replacements on your other Macs."
                    )
                    .font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                    HStack {
                        QuietButton(title: "Cancel", action: sync.cancelSetup)
                        Spacer()
                        PrimaryButton(title: "Connect profiles", action: sync.confirm)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            if let message = sync.message {
                Text(message).font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                    .padding(.horizontal, 12).fixedSize(horizontal: false, vertical: true)
            }
            if sync.enabled {
                HStack {
                    if let date = sync.lastSyncedAt {
                        Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                    }
                    Spacer(minLength: 8)
                    QuietButton(title: "Sync now", action: sync.syncNow).disabled(sync.isBusy)
                }
                .padding(.horizontal, 12)
                if sync.status == .attention {
                    QuietButton(title: "Review iCloud connection…", action: sync.prepare)
                        .disabled(sync.isBusy).padding(.horizontal, 12)
                }
            }
        }
        if sync.hasDeferredChanges {
            InspectorCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("An update is waiting", systemImage: "keyboard")
                        .font(DS.Typography.label)
                    Text("Release held keys and turn off toggled layers to apply it safely.")
                        .font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                    QuietButton(title: "Apply waiting changes", action: sync.applyWaitingChanges)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if !sync.conflicts.isEmpty {
            InspectorCard(title: "Choose which version to keep") {
                ForEach(sync.conflicts) { conflict in
                    Button {
                        selectedConflict = conflict
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up")
                            Text(
                                conflict.remote.profile?.name ?? sync.localProfile(conflict.id)?
                                    .name ?? "Deleted profile"
                            )
                            .lineLimit(1)
                            Spacer()
                            Text("Review").foregroundStyle(DS.Ink.secondary)
                            Image(systemName: "chevron.right").font(
                                .system(size: 10, weight: .semibold))
                        }
                        .font(DS.Typography.label).padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var statusText: String {
        switch sync.status {
        case .off: "Off · saved on this Mac"
        case .unavailable: "Unavailable in this build"
        case .requiresPro: "Paused · requires Pro"
        case .checking: "Checking iCloud…"
        case .reviewing: "Ready for your review"
        case .syncing: "Syncing…"
        case .current: "Up to date"
        case .waiting: "Waiting to sync"
        case .attention: "Needs attention"
        }
    }

    private func detail(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(DS.Ink.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(DS.Typography.label)
                Text(text).font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ProfileSyncConflictView: View {
    @ObservedObject var sync: ProfileSyncController
    let conflict: ProfileSyncConflict
    @Environment(\.dismiss) private var dismiss

    private var local: Profile? { sync.localProfile(conflict.id) }
    private var remote: Profile? { conflict.remote.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Two versions need your attention")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                Spacer()
                QuietButton(title: "Done") { dismiss() }
            }
            Text("Compare this Mac with iCloud, then choose the version to use on your Macs.")
                .font(DS.Typography.body).foregroundStyle(DS.Ink.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let local, let remote {
                        let differences = ProfileHistoryComparison.changes(from: local, to: remote)
                        if differences.isEmpty {
                            Text(
                                "The profile contents match; their position in the library differs."
                            )
                            .font(DS.Typography.body)
                        }
                        ForEach(differences) { change in
                            InspectorCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(
                                        [change.layerName, change.title].compactMap { $0 }.joined(
                                            separator: " · ")
                                    )
                                    .font(DS.Typography.label)
                                    Text("This Mac: \(change.before)")
                                    Text("iCloud: \(change.after)").foregroundStyle(
                                        DS.Ink.secondary)
                                }
                                .font(DS.Typography.body).padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        Text(
                            local == nil
                                ? "This profile was deleted on this Mac and edited in iCloud."
                                : "This profile was deleted in iCloud. This Mac still has “\(local?.name ?? "Profile")”."
                        )
                        .font(DS.Typography.body)
                    }
                    if remote == nil && sync.isSelected(conflict.id) {
                        Text(
                            "Select another profile in the main window before accepting this deletion."
                        )
                        .font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                    }
                    if let message = sync.message {
                        Text(message).font(DS.Typography.footnote).foregroundStyle(DS.Ink.secondary)
                    }
                }
            }
            HStack {
                QuietButton(title: local == nil ? "Keep deleted" : "Use this Mac") {
                    resolve(keepLocal: true)
                }
                Spacer()
                PrimaryButton(title: remote == nil ? "Accept deletion" : "Use iCloud") {
                    resolve(keepLocal: false)
                }
                .disabled(remote == nil && sync.isSelected(conflict.id))
            }
        }
        .padding(24).frame(width: 520, height: 450)
        .background(DS.Surface.window).foregroundStyle(DS.Ink.primary)
    }

    private func resolve(keepLocal: Bool) {
        sync.resolve(conflict, keepLocal: keepLocal)
        if !sync.conflicts.contains(where: { $0.id == conflict.id }) { dismiss() }
    }
}
