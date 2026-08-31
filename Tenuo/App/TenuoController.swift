import AppKit
import Foundation
import os

final class TenuoController {
    private let log = Logger(subsystem: "com.tenuo.Tenuo", category: "controller")

    let settings: Settings
    let accessibility = AccessibilityManager()
    let launchAtLogin = LaunchAtLoginManager()

    private let remapper = CapsLockRemapper()
    private let systemEvents = SystemEventObserver()
    private var monitor: KeyboardMonitor

    var onStateChanged: (() -> Void)?
    var onPermissionMissing: (() -> Void)?
    var onPermissionGranted: (() -> Void)?
    var onActiveLayerChanged: ((Int?) -> Void)?

    var isTrusted: Bool { monitor.isRunning || accessibility.isTrusted }

    var isActive: Bool { monitor.isRunning && settings.isEnabled }

    private var retryTimer: Timer?
    private static let retryInterval: TimeInterval = 1.0

    init(settings: Settings = Settings()) {
        self.settings = settings
        monitor = KeyboardMonitor(layout: settings.activeProfile, isEnabled: settings.isEnabled)
    }

    func start() {
        settings.onChange = { [weak self] in self?.applySettings() }

        accessibility.onChange = { [weak self] trusted in
            guard let self, !trusted, monitor.isRunning else { return }
            log.info("Accessibility revoked")
            deactivate()
            onPermissionMissing?()
            startRetrying()
            onStateChanged?()
        }
        accessibility.startMonitoring()

        systemEvents.onShouldResetState = { [weak self] in self?.monitor.flushHeldKeys() }
        systemEvents.onShouldReapplyRemap = { [weak self] in self?.remapper.reapplyIfNeeded() }
        systemEvents.start()

        monitor.onActiveLayerChanged = { [weak self] index in
            self?.onActiveLayerChanged?(index)
        }

        monitor.onTapInvalidated = { [weak self] in
            guard let self else { return }
            if !accessibility.isTrusted {
                deactivate()
                onPermissionMissing?()
                startRetrying()
            }
            onStateChanged?()
        }

        if !activate() {
            onPermissionMissing?()
            startRetrying()
        }
        onStateChanged?()
    }

    func shutDown() {
        stopRetrying()
        monitor.stop()
        remapper.revert(waitUntilFinished: true)
        accessibility.stopMonitoring()
    }

    @discardableResult
    private func activate() -> Bool {
        guard settings.isEnabled else { return false }

        guard monitor.start() else {
            accessibility.noteObservedState(false)
            return false
        }
        accessibility.noteObservedState(true)
        applyRemapIfNeeded()
        return true
    }

    private func startRetrying() {
        guard retryTimer == nil else { return }
        let timer = Timer(timeInterval: Self.retryInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard settings.isEnabled else { return }
            guard activate() else { return }

            log.info("Accessibility granted; tap started without a relaunch")
            stopRetrying()
            onPermissionGranted?()
            onStateChanged?()
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    private func stopRetrying() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func deactivate() {
        monitor.stop()
        remapper.revert()
    }

    private func applyRemapIfNeeded() {
        if settings.activeProfile.triggeredLayers.contains(where: {
            $0.trigger?.key.requiresCapsLockRemap == true
        }) {
            remapper.apply()
        } else {
            remapper.revert()
        }
    }

    private func applySettings() {
        monitor.update(layout: settings.activeProfile)
        monitor.update(isEnabled: settings.isEnabled)

        if settings.isEnabled {
            if activate() {
                stopRetrying()
            } else {
                startRetrying()
            }
        } else {
            stopRetrying()
            deactivate()
        }
        onStateChanged?()
    }

    func toggleEnabled() {
        settings.isEnabled.toggle()
    }

    func apply(layout: Layout) {
        settings.activeProfile = layout
    }

    func toggleLaunchAtLogin() {
        launchAtLogin.setEnabled(!launchAtLogin.isEnabled)
        onStateChanged?()
    }

    func openAccessibilitySettings() {
        accessibility.openSystemSettings()
    }

    deinit {
        retryTimer?.invalidate()
    }
}
