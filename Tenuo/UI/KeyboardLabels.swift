import Foundation

extension KeyBinding {
    @MainActor var keyboardLabel: String {
        Modifier.allCases.filter { modifiers.contains($0) }.map(\.symbol).joined()
            + KeyboardPresentation.shared.shortcutKeyLabel(for: self)
    }
}

extension TriggerKey {
    @MainActor var keyboardName: String {
        if case let .key(name) = self { return KeyboardPresentation.shared.displayName(for: name) }
        return displayName
    }

    @MainActor var keyboardSymbol: String {
        if case let .key(name) = self { return KeyboardPresentation.shared.label(for: name) }
        return shortSymbol
    }
}

extension LayerTrigger {
    @MainActor var keyboardLabel: String { modifiers.map(\.symbol).joined() + key.keyboardSymbol }
}

extension Action {
    @MainActor var keyboardLabel: String {
        if case let .sendKey(binding) = self { return binding.keyboardLabel }
        return displayLabel
    }
}

extension LayerMapping {
    @MainActor var keyboardLabel: String { action?.keyboardLabel ?? displayLabel }
}

extension MacAction {
    @MainActor var keyboardLabel: String { displayLabel }
}

@MainActor
func keyboardMappingLabel(_ mapping: LayerMapping?, in profile: Profile) -> String {
    if let action = mapping?.action, action.target == nil { return action.keyboardLabel }
    return ProfileHistoryComparison.mappingLabel(mapping, in: profile)
}
