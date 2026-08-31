import SwiftUI

struct LayerList: View {
    @ObservedObject var model: AppModel
    var onOpenSettings: () -> Void
    @State private var pendingRemoval: Layer?
    @State private var renamingProfile: Layout?
    @State private var deletingProfile: Layout?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle().fill(DS.Line.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Profiles")
                        .padding(.bottom, 5)
                    ProfileSection(
                        model: model,
                        renaming: $renamingProfile,
                        deleting: $deletingProfile)

                    SectionHeader(
                        title: "Layers",
                        detail: "\(model.layout.triggeredLayers.count)/\(Layout.maxTriggeredLayers)"
                    )
                    .padding(.top, DS.Space.large)
                    .padding(.bottom, 5)
                    layers
                }
                .padding(.horizontal, 6)
                .padding(.top, DS.Space.small)
                .padding(.bottom, DS.Space.medium)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.Surface.sidebar)
        .sheet(item: $renamingProfile) { profile in
            RenameProfileSheet(model: model, profile: profile)
        }
        .confirmationDialog(
            deletingProfile.map { "Delete “\($0.name)”?" } ?? "",
            isPresented: Binding(
                get: { deletingProfile != nil },
                set: { if !$0 { deletingProfile = nil } })
        ) {
            Button("Delete Profile", role: .destructive) {
                if let profile = deletingProfile { model.removeProfile(profile.id) }
                deletingProfile = nil
            }
            Button("Cancel", role: .cancel) { deletingProfile = nil }
        } message: {
            Text("Its layers and mappings go with it.")
        }
        .confirmationDialog(
            pendingRemoval.map { "Remove “\($0.name)” and its \($0.mappings.count) mappings?" }
                ?? "",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } })
        ) {
            Button("Remove Layer", role: .destructive) {
                if let layer = pendingRemoval { model.remove(layer) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        }
    }

    private var header: some View {
        ColumnHeader {
            HStack(spacing: 8) {
                AppMark(size: 24)

                Text("Tenuo")
                    .font(DS.Typography.title)

                Spacer(minLength: 8)

                StatusPill(color: statusColor, title: statusText)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(DS.Line.hairline).frame(height: 1)

            FooterRow(title: "Settings…", action: onOpenSettings) {
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
        guard model.isTrusted else { return "No access" }
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
                                .tooltip("Another layer uses this chord, so only one can activate")
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
                title: "New Layer",
                isEnabled: model.canAddLayer,
                reason: """
                    A profile holds up to \(Layout.maxTriggeredLayers) layers. \
                    Make another profile for more.
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
            Button("Remove Layer…", role: .destructive) { pendingRemoval = layer }
        }
    }

    private func conflicts(_ layer: Layer) -> Bool {
        model.layout.conflicts().contains { $0.0.id == layer.id || $0.1.id == layer.id }
    }
}
