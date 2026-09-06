import AppKit
import Combine
import Foundation
import os

@MainActor
final class TenuoController {
    private let log = Logger(subsystem: "app.tenuo", category: "controller")

    let preferences: AppPreferences
    let profileStore: ProfileStore
    let actionAvailability: any ActionAvailability
    let license: LicenseManager
    let accessibility = AccessibilityManager()
    let launchAtLogin = LaunchAtLoginManager()

    private let remapper = CapsLockRemapper()
    private let systemEvents = SystemEventObserver()
    private let profileSelection: ProfileSelectionSource
    private var applicationObserver: NSObjectProtocol?
    private var licenseObserver: AnyCancellable?
    private var monitor: KeyboardMonitor

    var onStateChanged: (() -> Void)?
    var onPermissionMissing: (() -> Void)?
    var onPermissionGranted: (() -> Void)?
    var onActiveLayersChanged: (([LayerActivity]) -> Void)?

    var isTrusted: Bool { monitor.isRunning || accessibility.isTrusted }

    var isActive: Bool {
        guard monitor.isRunning && preferences.isEnabled else { return false }
        return !requiresCapsLockRemap || capsLockRemapReady
    }

    private var retryTimer: Timer?
    private var remapRetryTimer: Timer?
    private var remapGeneration = 0
    private var capsLockRemapReady = true
    private static let retryInterval: TimeInterval = 1.0

    init(
        preferences: AppPreferences = AppPreferences(),
        profileStore: ProfileStore? = nil,
        profileSelection: ProfileSelectionSource? = nil,
        actionAvailability: (any ActionAvailability)? = nil,
        license: LicenseManager? = nil
    ) {
        self.preferences = preferences
        let license = license ?? LicenseManager()
        self.license = license
        self.actionAvailability = actionAvailability ?? license.entitlement
        let store = profileStore ?? UserDefaultsProfileStore()
        self.profileStore = store
        let selection = profileSelection ?? ManualProfileSelectionSource(store: store)
        self.profileSelection = selection
        monitor = KeyboardMonitor(
            profile: selection.current.profile,
            isEnabled: preferences.isEnabled,
            actionAvailability: self.actionAvailability)
    }

    func start() {
        applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshApplication() }
        }
        licenseObserver = license.$state.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refreshApplication()
        }
        refreshApplication()
        license.start()
        preferences.onChange = { [weak self] in self?.applySettings() }
        profileSelection.onChange = { [weak self] selection in
            self?.applyEffectiveProfile(selection.profile)
        }

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
        systemEvents.onShouldReapplyRemap = { [weak self] in self?.reconcileRemap() }
        systemEvents.start()

        monitor.onActiveLayersChanged = { [weak self] states in
            self?.onActiveLayersChanged?(states)
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

        profileSelection.start()

        if preferences.isEnabled, !activate() {
            onPermissionMissing?()
            startRetrying()
        }
        onStateChanged?()
    }

    private func refreshApplication() {
        monitor.updateApplication(
            license.hasProAccess
                ? NSWorkspace.shared.frontmostApplication?.bundleIdentifier : nil)
        onStateChanged?()
    }

    func shutDown() {
        if let applicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationObserver)
        }
        applicationObserver = nil
        licenseObserver = nil
        license.stop()
        stopRetrying()
        stopRemapRetrying()
        profileSelection.stop()
        profileSelection.onChange = nil
        remapGeneration += 1
        monitor.stop()
        remapper.revert(waitUntilFinished: true)
        accessibility.stopMonitoring()
    }

    @discardableResult
    private func activate() -> Bool {
        guard preferences.isEnabled else { return false }

        guard monitor.start() else {
            accessibility.noteObservedState(false)
            return false
        }
        accessibility.noteObservedState(true)
        reconcileRemap()
        return true
    }

    private func startRetrying() {
        guard retryTimer == nil else { return }
        let timer = Timer(timeInterval: Self.retryInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.preferences.isEnabled else { return }
                guard self.activate() else { return }

                self.log.info("Accessibility granted; tap started without a relaunch")
                self.stopRetrying()
                self.onPermissionGranted?()
                self.onStateChanged?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    private func stopRetrying() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func startRemapRetrying() {
        guard remapRetryTimer == nil else { return }
        let timer = Timer(timeInterval: Self.retryInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.preferences.isEnabled, self.monitor.isRunning,
                    self.requiresCapsLockRemap
                else {
                    self.stopRemapRetrying()
                    return
                }
                self.reconcileRemap()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        remapRetryTimer = timer
    }

    private func stopRemapRetrying() {
        remapRetryTimer?.invalidate()
        remapRetryTimer = nil
    }

    private func deactivate() {
        remapGeneration += 1
        capsLockRemapReady = false
        monitor.stop()
        remapper.revert()
    }

    private var requiresCapsLockRemap: Bool {
        profileSelection.current.profile.triggeredLayers.contains {
            $0.trigger?.key.requiresCapsLockRemap == true
        }
    }

    private func reconcileRemap() {
        remapGeneration += 1
        let generation = remapGeneration

        guard preferences.isEnabled, monitor.isRunning else {
            capsLockRemapReady = false
            stopRemapRetrying()
            remapper.revert()
            onStateChanged?()
            return
        }

        guard requiresCapsLockRemap else {
            capsLockRemapReady = true
            stopRemapRetrying()
            remapper.revert()
            onStateChanged?()
            return
        }

        capsLockRemapReady = false
        remapper.ensureApplied { [weak self] success in
            guard let self, generation == remapGeneration else { return }
            guard preferences.isEnabled, monitor.isRunning, requiresCapsLockRemap else { return }

            capsLockRemapReady = success
            if success {
                stopRemapRetrying()
                log.info("Caps Lock mapping is ready")
            } else {
                log.error("Caps Lock mapping is unavailable; retrying")
                startRemapRetrying()
            }
            onStateChanged?()
        }
    }

    private func applySettings() {
        monitor.update(isEnabled: preferences.isEnabled)

        if preferences.isEnabled {
            if activate() {
                stopRetrying()
            } else {
                startRetrying()
            }
        } else {
            stopRetrying()
            stopRemapRetrying()
            deactivate()
        }
        onStateChanged?()
    }

    private func applyEffectiveProfile(_ profile: Profile) {
        monitor.update(profile: profile)
        reconcileRemap()
        onStateChanged?()
    }

    func toggleEnabled() {
        preferences.isEnabled.toggle()
    }

    func toggleLaunchAtLogin() {
        launchAtLogin.setEnabled(!launchAtLogin.isRegistered)
        onStateChanged?()
    }

    func openAccessibilitySettings() {
        accessibility.openSystemSettings()
    }

    deinit {
        retryTimer?.invalidate()
        remapRetryTimer?.invalidate()
    }
}
