import AppKit
import SwiftUI

@MainActor
extension AppModel {
    private static let mappingPasteboardType = NSPasteboard.PasteboardType("app.tenuo.mappings")

    var selectedKey: String? {
        selectedKeys.count == 1 ? selectedKeys.first : nil
    }

    var canCopyMappings: Bool {
        isMappingEditorVisible && selectedKeys.contains { selectedMappings[$0] != nil }
    }

    var canClearMappings: Bool { canCopyMappings }

    var hasCopiedMappings: Bool {
        isMappingEditorVisible && copiedMappings != nil
            && mappingPasteboardChange == NSPasteboard.general.changeCount
    }

    var canPasteMappings: Bool {
        hasCopiedMappings && copiedMappings?.mappings.count == 1 && !selectedKeys.isEmpty
    }

    func selectKey(_ key: String) {
        if NSApp.keyWindow?.firstResponder is NSTextView {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        if NSEvent.modifierFlags.contains(.command) {
            if !selectedKeys.insert(key).inserted { selectedKeys.remove(key) }
        } else {
            selectedKeys = selectedKeys == [key] ? [] : [key]
        }
    }

    func copyMappings() {
        guard canCopyMappings else { return }
        copiedMappings = MappingTransfer(
            profileID: profile.id, mappings: selectedMappings, selection: selectedKeys)
        // The payload stays in this editor session; other clipboard writes invalidate it.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(UUID().uuidString, forType: Self.mappingPasteboardType)
        mappingPasteboardChange = pasteboard.changeCount
        objectWillChange.send()
    }

    func pasteMappings(toOriginalKeys: Bool = false) {
        guard hasCopiedMappings, let copiedMappings else { return }
        do {
            let replacements = try copiedMappings.replacements(
                on: toOriginalKeys ? nil : selectedKeys, in: profile, hasPro: license.hasProAccess)
            var mappings = selectedMappings
            mappings.merge(replacements) { _, new in new }
            if updateMappings(mappings, name: "Paste Mappings") {
                selectedKeys = Set(replacements.keys)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearMappings() {
        guard canClearMappings else { return }
        let mappings = selectedMappings.filter { !selectedKeys.contains($0.key) }
        _ = updateMappings(
            mappings, name: selectedApplicationID == nil ? "Clear Mappings" : "Use Default Mappings"
        )
    }
}

struct MappingSelectionMenu: View {
    @ObservedObject var model: AppModel
    var key: String?

    private var selection: Set<String> {
        if let key, !model.selectedKeys.contains(key) { return [key] }
        return model.selectedKeys
    }

    var body: some View {
        Button("Copy mappings") {
            model.selectedKeys = selection
            model.copyMappings()
        }
        .disabled(!selection.contains { model.selectedMappings[$0] != nil })
        Button("Paste mapping") {
            model.selectedKeys = selection
            model.pasteMappings()
        }
        .disabled(
            !model.hasCopiedMappings || model.copiedMappings?.mappings.count != 1
                || selection.isEmpty)
        Button("Paste to original keys") { model.pasteMappings(toOriginalKeys: true) }
            .disabled(!model.hasCopiedMappings)
        Divider()
        Button(model.selectedApplicationID == nil ? "Clear mappings" : "Use Default") {
            model.selectedKeys = selection
            model.clearMappings()
        }
        .disabled(!selection.contains { model.selectedMappings[$0] != nil })
    }
}

struct MappingGroupInspector: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.medium) {
            ForEach(model.selectedKeys.sorted(), id: \.self) { key in
                HStack(spacing: DS.Space.small) {
                    Keycap(
                        label: KeyCatalog.label(for: KeyCatalog.code(for: key) ?? 0),
                        width: 30, height: 30, legendSize: 11,
                        isLit: model.selectedMappings[key] != nil)
                    Text(
                        (model.selectedMappings[key] ?? model.inheritedMappings[key])
                            .map(LayersPage.caption(for:)) ?? "Normal key"
                    )
                    .font(DS.Typography.body)
                    .lineLimit(2)
                }
            }
            Divider()
            Button {
                model.copyMappings()
            } label: {
                Text("Copy mappings").frame(maxWidth: .infinity)
            }
            .buttonStyle(RoundedActionStyle())
            .disabled(!model.canCopyMappings)
            Button {
                model.pasteMappings()
            } label: {
                Text("Paste mapping").frame(maxWidth: .infinity)
            }
            .buttonStyle(RoundedActionStyle())
            .disabled(!model.canPasteMappings)
            Button {
                model.pasteMappings(toOriginalKeys: true)
            } label: {
                Text("Paste to original keys").frame(maxWidth: .infinity)
            }
            .buttonStyle(RoundedActionStyle())
            .disabled(!model.hasCopiedMappings)
            Text("⌘-click a key to add or remove it from the selection.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Ink.tertiary)
        }
    }
}
