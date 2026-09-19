import Foundation

struct MappingTransfer {
    let profileID: UUID
    let mappings: [String: LayerMapping]

    init(profileID: UUID, mappings: [String: LayerMapping], selection: Set<String>) {
        self.profileID = profileID
        self.mappings = mappings.filter { selection.contains($0.key) }
    }

    enum PasteError: LocalizedError {
        case empty, selectKeys, multipleMappings, missingLayer, proRequired, localTarget

        var errorDescription: String? {
            switch self {
            case .empty: return "Copy a mapping first."
            case .selectKeys: return "Select the keys to paste onto."
            case .multipleMappings: return "Use Paste to original keys for a group of mappings."
            case .missingLayer:
                return
                    "A copied mapping refers to a layer outside this profile or a layer that was removed."
            case .proRequired: return "These mappings include actions that require Tenuo Pro."
            case .localTarget:
                return
                    "This action is linked to a target in another profile. Set it up again in this profile."
            }
        }
    }

    func replacements(
        on selection: Set<String>?, in profile: Profile, hasPro: Bool
    ) throws -> [String: LayerMapping] {
        guard !mappings.isEmpty else { throw PasteError.empty }
        for mapping in mappings.values {
            if let action = mapping.action {
                if action.kind.requiresPro && !hasPro { throw PasteError.proRequired }
                if case let .layer(id) = action.target,
                    profileID != profile.id
                        || !profile.layers.contains(where: { $0.id == id })
                {
                    throw PasteError.missingLayer
                }
                if profileID != profile.id, let macAction = action.macAction {
                    switch macAction {
                    case .file(let target) where target.localID != nil:
                        throw PasteError.localTarget
                    case .application(let target), .shortcut(let target):
                        if target.localID != nil { throw PasteError.localTarget }
                    default: break
                    }
                }
            }
        }
        guard let selection else { return mappings }
        guard !selection.isEmpty else { throw PasteError.selectKeys }
        guard mappings.count == 1, let mapping = mappings.values.first else {
            throw PasteError.multipleMappings
        }
        return Dictionary(uniqueKeysWithValues: selection.map { ($0, mapping) })
    }
}
