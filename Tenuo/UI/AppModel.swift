import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private let controller: TenuoController

    @Published private(set) var isTrusted: Bool = false
    @Published private(set) var isActive: Bool = false
    @Published private(set) var launchesAtLogin: Bool = false
    @Published private(set) var launchNeedsApproval: Bool = false

    @Published var selectedLayerID: UUID?

    init(controller: TenuoController) {
        self.controller = controller
        selectedLayerID =
            controller.settings.activeProfile.triggeredLayers.first?.id
            ?? controller.settings.activeProfile.layers.first?.id
        refresh()
    }

    var profile: Profile {
        get { controller.settings.activeProfile }
        set {
            controller.settings.activeProfile = newValue
            objectWillChange.send()
        }
    }

    var layers: [Layer] { profile.layers }

    var selectedIndex: Int {
        profile.layers.firstIndex { $0.id == selectedLayerID } ?? 0
    }

    var selectedLayer: Layer {
        get {
            profile.layers.indices.contains(selectedIndex)
                ? profile.layers[selectedIndex]
                : Presets.default.layers[0]
        }
        set {
            guard profile.layers.indices.contains(selectedIndex) else { return }
            profile.layers[selectedIndex] = newValue
        }
    }

    var selectedMappings: [String: KeyAction] { selectedLayer.mappings }

    var inheritedMappings: [String: KeyAction] {
        var result: [String: KeyAction] = [:]
        for layer in profile.layers.prefix(selectedIndex) {
            for (key, action) in layer.mappings where action != .transparent {
                result[key] = action
            }
        }
        for key in selectedLayer.mappings.keys { result.removeValue(forKey: key) }
        return result
    }

    var sortedMappings: [(source: String, action: KeyAction)] {
        selectedMappings
            .map { (source: $0.key, action: $0.value) }
            .sorted { $0.source < $1.source }
    }

    var canAddLayer: Bool { profile.canAddLayer }

    func addLayer() {
        guard canAddLayer else { return }
        var layer = Presets.newLayer(index: profile.layers.count)
        guard let preferred = layer.trigger,
            let trigger = uniqueTrigger(preferred: preferred)
        else { return }
        layer.trigger = trigger
        profile.layers.append(layer)
        selectedLayerID = layer.id
    }

    func duplicateLayer(_ layer: Layer) {
        guard canAddLayer else { return }
        var copy = layer
        copy.id = UUID()
        copy.name = "\(layer.name) Copy"
        guard let trigger = uniqueTrigger(preferred: copy.trigger ?? LayerTrigger()) else { return }
        copy.trigger = trigger
        profile.layers.append(copy)
        selectedLayerID = copy.id
    }

    func remove(_ layer: Layer) {
        guard !layer.isBase, let index = profile.layers.firstIndex(where: { $0.id == layer.id })
        else { return }
        profile.layers.remove(at: index)
        if selectedLayerID == layer.id { selectedLayerID = profile.layers.last?.id }
    }

    func removeSelectedLayer() {
        guard profile.layers.indices.contains(selectedIndex),
            !profile.layers[selectedIndex].isBase
        else { return }
        let removed = profile.layers.remove(at: selectedIndex)
        if selectedLayerID == removed.id {
            selectedLayerID = profile.layers.last?.id
        }
    }

    var profiles: [Profile] { controller.settings.profiles }

    var activeProfileID: UUID { controller.settings.activeProfileID }

    func selectProfile(_ id: UUID) {
        guard id != controller.settings.activeProfileID else { return }
        controller.settings.activeProfileID = id
        selectInitialLayer()
        objectWillChange.send()
    }

    func addProfile(from source: Profile, named name: String) {
        let created = source.copy(named: controller.settings.uniqueName(name))
        controller.settings.profiles = controller.settings.profiles + [created]
        controller.settings.activeProfileID = created.id
        selectInitialLayer()
        objectWillChange.send()
    }

    func newProfile() {
        addProfile(from: Profile(name: "", layers: [Presets.emptyBase()]), named: "New Profile")
    }

    func duplicateProfile(_ profile: Profile) {
        addProfile(from: profile, named: "\(profile.name) Copy")
    }

    func duplicateActiveProfile() { duplicateProfile(profile) }

    func renameProfile(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            var updated = profiles.first(where: { $0.id == id }),
            trimmed != updated.name
        else { return }
        updated.name = controller.settings.uniqueName(trimmed)
        controller.settings.profiles = profiles.map { $0.id == id ? updated : $0 }
        objectWillChange.send()
    }

    var canRemoveProfile: Bool { profiles.count > 1 }

    func removeProfile(_ id: UUID) {
        guard canRemoveProfile else { return }
        controller.settings.profiles = profiles.filter { $0.id != id }
        selectInitialLayer()
        objectWillChange.send()
    }

    func exportProfile(_ profile: Profile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(profile.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Settings.encoder.encode(profile).write(to: url) } catch {
            errorMessage = error.localizedDescription
        }
    }

    @Published var errorMessage: String?

    func exportProfileToPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(profile.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try controller.settings.exportJSON().write(to: url) } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importProfileFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try controller.settings.importJSON(Data(contentsOf: url))
            selectInitialLayer()
            objectWillChange.send()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func selectInitialLayer() {
        selectedLayerID = profile.triggeredLayers.first?.id ?? profile.layers.first?.id
    }

    private func uniqueTrigger(preferred: LayerTrigger) -> LayerTrigger? {
        let used = Set(profile.triggeredLayers.compactMap(\.trigger))
        let key = preferred.key
        let candidates =
            [preferred]
            + ModifierRequirement.allCases.map {
                LayerTrigger(key: key, modifiers: [$0])
            }
        return candidates.first { !used.contains($0) }
    }

    var isEnabled: Bool {
        get { controller.settings.isEnabled }
        set {
            controller.settings.isEnabled = newValue
            refresh()
        }
    }

    let updates = UpdateController()

    var updatesAvailable: Bool { UpdateController.isConfigured }

    var checksForUpdates: Bool {
        get { controller.settings.checksForUpdates }
        set {
            controller.settings.checksForUpdates = newValue
            updates.checksAutomatically = newValue
            refresh()
        }
    }

    func startUpdater() {
        updates.start(checksAutomatically: controller.settings.checksForUpdates)
    }

    var showsCheatSheet: Bool {
        get { controller.settings.showsCheatSheet }
        set {
            controller.settings.showsCheatSheet = newValue
            refresh()
        }
    }

    func refresh() {
        isTrusted = controller.isTrusted
        isActive = controller.isActive
        launchesAtLogin = controller.launchAtLogin.isEnabled
        launchNeedsApproval = controller.launchAtLogin.requiresApproval
        objectWillChange.send()
    }

    func toggleLaunchAtLogin() {
        controller.toggleLaunchAtLogin()
        refresh()
    }

    func openAccessibilitySettings() {
        controller.openAccessibilitySettings()
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
