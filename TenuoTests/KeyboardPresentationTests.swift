import Carbon
import XCTest

@MainActor
final class KeyboardPresentationTests: XCTestCase {
    private func source(_ id: String) throws -> TISInputSource {
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        let sources =
            TISCreateInputSourceList(filter, true).takeRetainedValue() as! [TISInputSource]
        return try XCTUnwrap(sources.first, "Missing system keyboard layout: \(id)")
    }

    private func defaults() -> UserDefaults {
        let name = "app.tenuo.keyboard-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testCommandShortcutUsesCommandLayoutWithoutChangingSourceLegend() throws {
        let layout = try source("com.apple.keylayout.DVORAK-QWERTYCMD")
        let keyboard = KeyboardPresentation(defaults: defaults(), inputSource: { layout })
        keyboard.override = .ansi
        XCTAssertEqual(keyboard.label(for: "q"), "'")
        XCTAssertEqual(
            keyboard.shortcutKeyLabel(for: KeyBinding(key: "q", modifiers: [.command])), "Q")
        XCTAssertEqual(
            keyboard.shortcutKeyLabel(for: KeyBinding(key: "q", modifiers: [.command, .shift])), "Q"
        )
        XCTAssertEqual(
            keyboard.shortcutKeyLabel(for: KeyBinding(key: "q", modifiers: [.option])), "'")
    }

    func testShapeOverrideUsesMatchingTranslationAndAutomaticFollowsObservedKeyboard() throws {
        let layout = try source("com.apple.keylayout.US")
        let keyboard = KeyboardPresentation(defaults: defaults(), inputSource: { layout })
        keyboard.observeKeyboardType(40)
        XCTAssertEqual(keyboard.shape, .ansi)
        XCTAssertEqual(keyboard.label(for: "backslash"), "\\")
        keyboard.override = .jis
        XCTAssertEqual(keyboard.shape, .jis)
        XCTAssertEqual(keyboard.label(for: "backslash"), "]")
        keyboard.observeKeyboardType(41)
        XCTAssertEqual(keyboard.detectedShape, .iso)
        XCTAssertEqual(keyboard.shape, .jis)
        XCTAssertEqual(keyboard.label(for: "backslash"), "]")
        keyboard.override = nil
        XCTAssertEqual(keyboard.shape, .iso)
        XCTAssertEqual(keyboard.label(for: "backslash"), "\\")
        keyboard.observeKeyboardType(42)
        XCTAssertEqual(keyboard.shape, .jis)
        XCTAssertEqual(keyboard.label(for: "backslash"), "]")
        keyboard.observeKeyboardType(0)
        XCTAssertEqual(keyboard.shape, .jis)
    }

    func testMissingInputSourceClearsPreviousLanguageAndShortcutLabels() throws {
        var layout: TISInputSource? = try source("com.apple.keylayout.Dvorak")
        let keyboard = KeyboardPresentation(defaults: defaults(), inputSource: { layout })
        keyboard.override = .ansi
        XCTAssertEqual(keyboard.label(for: "q"), "'")
        layout = nil
        keyboard.refresh()
        XCTAssertEqual(keyboard.label(for: "q"), "Q")
        XCTAssertEqual(
            keyboard.shortcutKeyLabel(for: KeyBinding(key: "q", modifiers: [.command])), "Q")
    }
}
