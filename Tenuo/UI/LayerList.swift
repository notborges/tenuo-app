import SwiftUI

struct LayerList: View {
    @ObservedObject var model: AppModel
    var onOpenSettings: () -> Void
    @State private var pendingRemoval: Layer?
    @State private var renamingProfile: Profile?
    @State private var deletingProfile: Profile?
    var onOpenHistory: (UUID) -> Void
    @State private var isHistoryHovering = false
    @State private var showsHistoryProInfo = false
    @FocusState private var isHistoryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    profilesHeader
                        .padding(.bottom, 5)
                    ProfileSection(
                        model: model,
                        renaming: $renamingProfile,
                        deleting: $deletingProfile,
                        onOpenHistory: onOpenHistory)

                    SectionHeader(
                        title: "Layers",
                        detail:
                            "\(model.profile.triggeredLayers.count)/\(Profile.maxTriggeredLayers)"
                    )
                    .padding(.top, DS.Space.large)
                    .padding(.bottom, 5)
                    layers
                }
                .padding(.horizontal, 10)
                .padding(.top, DS.Space.medium)
                .padding(.bottom, DS.Space.medium)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationSurface()
        .sheet(item: $renamingProfile) { profile in
            RenameProfileSheet(model: model, profile: profile)
        }
        .confirmationDialog(
            deletingProfile.map { "Delete “\($0.name)”?" } ?? "",
            isPresented: Binding(
                get: { deletingProfile != nil },
                set: { if !$0 { deletingProfile = nil } })
        ) {
            Button("Delete profile", role: .destructive) {
                if let profile = deletingProfile { model.removeProfile(profile.id) }
                deletingProfile = nil
            }
            Button("Cancel", role: .cancel) { deletingProfile = nil }
        } message: {
            Text("This deletes all of its layers and mappings.")
        }
        .confirmationDialog(
            pendingRemoval.map(removalTitle(for:))
                ?? "",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } })
        ) {
            Button("Remove layer", role: .destructive) {
                if let layer = pendingRemoval { model.remove(layer) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
    }

    private var profilesHeader: some View {
        HStack(spacing: DS.Space.tight) {
            Text("Profiles").sectionLabel()
            Spacer(minLength: 0)
            Button {
                if model.license.hasProAccess {
                    onOpenHistory(model.profile.id)
                } else {
                    showsHistoryProInfo = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("History")
                    if !model.license.hasProAccess {
                        Text("Pro").font(.system(size: 9, weight: .medium))
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(
                    isHistoryHovering || isHistoryFocused
                        ? DS.Ink.primary : DS.Ink.tertiary
                )
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                        .fill(
                            isHistoryHovering || isHistoryFocused
                                ? DS.Selection.hover : .clear)
                }
                .frame(height: DS.Metrics.controlHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($isHistoryFocused)
            .onHover { isHistoryHovering = $0 }
            .animation(DS.Motion.hover, value: isHistoryHovering || isHistoryFocused)
            .accessibilityLabel("View history for \(model.profile.name)")
            .tooltip("Profile history")
            .popover(isPresented: $showsHistoryProInfo) {
                ProFeaturePrompt(
                    title: "Profile history",
                    detail:
                        "Compare earlier versions and return to a setup you liked. Your current version is kept before you restore.",
                    visual: "clock.arrow.circlepath", presentation: .popover
                ) {
                    showsHistoryProInfo = false
                    model.onOpenProSettings?()
                }
                .frame(width: 300)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        ColumnHeader(reservesWindowControls: true) {
            HStack(spacing: 8) {
                AppMark(size: 24)

                Text(AppIdentity.displayName)
                    .font(DS.Typography.title)
                if model.license.hasProAccess { ProBadge() }

                Spacer(minLength: 8)

                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .help(statusText)
                    .accessibilityLabel(statusText)
            }
        }
        .padding(.leading, DS.Metrics.panelInset)
        .padding(.trailing, DS.Metrics.panelInset)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.Line.hairline).frame(height: 1)

            FooterRow(title: "Settings…", height: DS.Metrics.row, action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: DS.Icon.regular))
                    .frame(width: 15)
            }
        }
    }

    private var statusColor: Color {
        guard model.isTrusted else { return DS.Signal.warning }
        return model.isActive ? DS.Signal.ok : DS.Ink.tertiary
    }

    private var statusText: String {
        guard model.isTrusted else { return "Needs Accessibility access" }
        return model.isActive ? "Active" : "Off"
    }

    private var layers: some View {
        VStack(spacing: 1) {
            ForEach(model.layers) { layer in
                SidebarRow(
                    title: layer.name,
                    isSelected: model.selectedLayerID == layer.id,
                    action: { model.selectedLayerID = layer.id }
                ) {
                    ChordBadge(layer: layer, isSelected: model.selectedLayerID == layer.id)
                } trailing: {
                    HStack(spacing: 6) {
                        if conflicts(layer) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: DS.Icon.small))
                                .foregroundStyle(DS.Signal.warning)
                                .tooltip(
                                    "This trigger is also used by another layer. Only one layer will activate."
                                )
                        }
                        if !layer.mappings.isEmpty {
                            Text("\(layer.mappings.count)")
                                .font(DS.Typography.mono)
                                .foregroundStyle(DS.Ink.tertiary)
                        }
                    }
                }
                .contextMenu { menu(for: layer) }
            }

            SidebarAddRow(
                title: "New layer",
                isEnabled: model.canAddLayer,
                reason: """
                    This profile already has \(Profile.maxTriggeredLayers) layers. \
                    Create another profile to add more.
                    """,
                action: model.addLayer
            )
        }
    }

    @ViewBuilder
    private func menu(for layer: Layer) -> some View {
        Button("Duplicate") { model.duplicateLayer(layer) }
            .disabled(!model.canAddLayer)
        if !layer.isBase {
            Divider()
            Button("Remove layer…", role: .destructive) { pendingRemoval = layer }
        }
    }

    private func removalTitle(for layer: Layer) -> String {
        guard !layer.mappings.isEmpty else { return "Remove “\(layer.name)”?" }
        let mappingWord = layer.mappings.count == 1 ? "mapping" : "mappings"
        return "Remove “\(layer.name)” and its \(layer.mappings.count) \(mappingWord)?"
    }

    private func conflicts(_ layer: Layer) -> Bool {
        model.profile.conflicts().contains { $0.0.id == layer.id || $0.1.id == layer.id }
    }
}
