import AppKit
import SwiftUI

struct ProfileSection: View {
    @ObservedObject var model: AppModel
    @Binding var renaming: Profile?
    @Binding var deleting: Profile?
    var onOpenHistory: (UUID) -> Void

    var body: some View {
        VStack(spacing: 1) {
            ForEach(model.profiles) { profile in
                SidebarRow(
                    title: profile.name,
                    isSelected: profile.id == model.activeProfileID,
                    action: { model.selectProfile(profile.id) }
                ) {
                    Image(
                        systemName: profile.id == model.activeProfileID
                            ? "square.stack.3d.up.fill" : "square.stack.3d.up"
                    )
                    .font(.system(size: DS.Icon.regular))
                    .frame(width: 15)
                } trailing: {
                    Text("\(profile.triggeredLayers.count)")
                        .font(DS.Typography.mono)
                        .foregroundStyle(DS.Ink.tertiary)
                }
                .contextMenu { menu(for: profile) }
            }

            SidebarAddRow(title: "New profile", action: model.newProfile)
        }
    }

    @ViewBuilder
    private func menu(for profile: Profile) -> some View {
        if profile.id != model.activeProfileID {
            Button("Switch to profile") { model.selectProfile(profile.id) }
            Divider()
        }
        if model.license.hasProAccess {
            Button("History") { onOpenHistory(profile.id) }
        }
        Button("Rename…") { renaming = profile }
        Button("Duplicate") { model.duplicateProfile(profile) }
        Button("Export…") { model.exportProfile(profile) }
        if model.canRemoveProfile {
            Divider()
            Button("Delete…", role: .destructive) { deleting = profile }
        }
    }

}

struct RenameProfileSheet: View {
    @ObservedObject var model: AppModel
    let profile: Profile
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.medium) {
            Text("Rename profile").font(DS.Typography.display)

            TextField("Profile name", text: $draft)
                .textFieldStyle(.plain)
                .font(DS.Typography.body)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Surface.raised)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .strokeBorder(DS.Line.hairline, lineWidth: 0.5)
                }
                .onSubmit(commit)

            HStack(spacing: DS.Space.tight) {
                Spacer()
                QuietButton(title: "Cancel") { dismiss() }
                PrimaryButton(title: "Rename", action: commit)
                    .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
        }
        .padding(DS.Space.large)
        .frame(width: 340)
        .background(DS.Surface.window)
        .onAppear { draft = profile.name }
    }

    private func commit() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.renameProfile(profile.id, to: draft)
        dismiss()
    }
}
