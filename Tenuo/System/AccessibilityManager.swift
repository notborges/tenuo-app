import AppKit
import ApplicationServices
import Foundation

final class AccessibilityManager {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    private static let pollInterval: TimeInterval = 1.0

    private var pollTimer: Timer?
    private var lastKnownState: Bool

    var onChange: ((Bool) -> Void)?

    init() {
        lastKnownState = AXIsProcessTrusted()
    }

    func noteObservedState(_ trusted: Bool) {
        lastKnownState = trusted
    }

    var isTrusted: Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openSystemSettings() {
        NSWorkspace.shared.open(Self.settingsURL)
    }

    func startMonitoring() {
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = AXIsProcessTrusted()
            guard current != lastKnownState else { return }
            lastKnownState = current
            onChange?(current)
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    deinit {
        stopMonitoring()
    }
}
