import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private let controller: TenuoController
    private var profileStore: ProfileStore { controller.profileStore }

    @Published private(set) var isTrusted: Bool = false
    @Published private(set) var isActive: Bool = false
    @Published private(set) var launchesAtLogin: Bool = false
    @Published private(set) var launchNeedsApproval: Bool = false
    @Published private(set) var licenseState: LicenseState

    @Published var selectedLayerID: UUID?

    let license: LicenseManager
    private var licenseObserver: AnyCancellable?

    init(controller: TenuoController) {
        self.controller = controller
        license = controller.license
        licenseState = controller.license.state
        let store = controller.profileStore
        selectedLayerID =
            store.manualProfile.triggeredLayers.first?.id
            ?? store.manualProfile.layers.first?.id
        licenseObserver = license.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.licenseState = state
            }
        refresh()
    }

    var profile: Profile {
        get { profileStore.manualProfile }
        set {
            guard profileStore.updateProfile(newValue) else { return }
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

    var selectedMappings: [String: LayerMapping] { selectedLayer.mappings }

    var inheritedMappings: [String: LayerMapping] {
        var result: [String: LayerMapping] = [:]
        for layer in profile.layers.prefix(selectedIndex) {
            for (key, action) in layer.mappings where action != .transparent {
                result[key] = action
            }
        }
        for key in selectedLayer.mappings.keys { result.removeValue(forKey: key) }
        return result
    }

    var sortedMappings: [(source: String, action: LayerMapping)] {
        selectedMappings
            .map { (source: $0.key, action: $0.value) }
            .sorted { $0.source < $1.source }
    }

    var canAddLayer: Bool { profile.canAddLayer }

    func canUse(_ kind: ActionKind) -> Bool {
        controller.actionAvailability.canUse(kind)
    }

    func activateLicense(_ key: String) {
        license.activate(key: key)
    }

    func checkLicense() {
        license.validateStoredLicense()
    }

    func deactivateLicense() {
        license.deactivate()
    }

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
        let originalID = copy.id
        copy.id = UUID()
        copy.name = "Copy of \(layer.name)"
        let copiedLayerIDs = [originalID: copy.id]
        copy.tapAction = copy.tapAction?.remappingLayerIDs(copiedLayerIDs)
        copy.mappings = copy.mappings.mapValues { $0.remappingLayerIDs(copiedLayerIDs) }
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

    var profiles: [Profile] { profileStore.profiles }

    var activeProfileID: UUID { profileStore.manualProfileID }

    func selectProfile(_ id: UUID) {
        guard profileStore.selectManualProfile(id) else { return }
        selectInitialLayer()
        objectWillChange.send()
    }

    func addProfile(from source: Profile, named name: String) {
        let created = source.copy(named: profileStore.uniqueName(name))
        guard profileStore.replaceProfiles(profiles + [created], selecting: created.id) else {
            return
        }
        selectInitialLayer()
        objectWillChange.send()
    }

    func newProfile() {
        addProfile(from: Profile(name: "", layers: [Presets.emptyBase()]), named: "New profile")
    }

    func duplicateProfile(_ profile: Profile) {
        addProfile(from: profile, named: "Copy of \(profile.name)")
    }

    func duplicateActiveProfile() { duplicateProfile(profile) }

    func renameProfile(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            var updated = profiles.first(where: { $0.id == id }),
            trimmed != updated.name
        else { return }
        updated.name = profileStore.uniqueName(trimmed)
        guard profileStore.replaceProfiles(
            profiles.map { $0.id == id ? updated : $0 },
            selecting: activeProfileID
        ) else { return }
        objectWillChange.send()
    }

    var canRemoveProfile: Bool { profiles.count > 1 }

    func removeProfile(_ id: UUID) {
        guard canRemoveProfile else { return }
        let remaining = profiles.filter { $0.id != id }
        let selectedID = id == activeProfileID ? remaining[0].id : activeProfileID
        guard profileStore.replaceProfiles(remaining, selecting: selectedID) else { return }
        selectInitialLayer()
        objectWillChange.send()
    }

    func exportProfile(_ profile: Profile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(profile.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try profileStore.exportProfile(profile).write(to: url) } catch {
            errorMessage = error.localizedDescription
        }
    }

    @Published var errorMessage: String?

    func exportProfileToPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(profile.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try profileStore.exportProfile(profile).write(to: url) } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importProfileFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try profileStore.importProfile(Data(contentsOf: url))
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
        get { controller.preferences.isEnabled }
        set {
            controller.preferences.isEnabled = newValue
            refresh()
        }
    }

    let updates = UpdateController()

    var updatesAvailable: Bool { UpdateController.isConfigured }

    var checksForUpdates: Bool {
        get { controller.preferences.checksForUpdates }
        set {
            controller.preferences.checksForUpdates = newValue
            updates.checksAutomatically = newValue
            refresh()
        }
    }

    func startUpdater() {
        updates.start(checksAutomatically: controller.preferences.checksForUpdates)
    }

    var showsCheatSheet: Bool {
        get { controller.preferences.showsCheatSheet }
        set {
            controller.preferences.showsCheatSheet = newValue
            refresh()
        }
    }

    func refresh() {
        isTrusted = controller.isTrusted
        isActive = controller.isActive
        launchesAtLogin = controller.launchAtLogin.isRegistered
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
