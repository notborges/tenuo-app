import Combine
import Foundation

@MainActor
final class LicenseManager: ObservableObject {
    static let offlineGracePeriod: TimeInterval = 30 * 24 * 60 * 60

    private static var developmentPreviewEnabled: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    private static var freePreviewEnabled: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("--free-preview")
        #else
            false
        #endif
    }

    let entitlement: LicenseEntitlement
    let configuration: PolarConfiguration

    @Published private(set) var state: LicenseState
    @Published private(set) var message: String?
    @Published private(set) var displayKey: String?

    private let developmentPreview: Bool
    private let store: LicenseStore
    private let client: PolarLicenseClient
    private let now: () -> Date
    private var record: LicenseRecord?
    private var task: Task<Void, Never>?
    private var validationTimer: Timer?

    init(
        configuration: PolarConfiguration = PolarConfiguration(bundle: .main),
        store: LicenseStore? = nil,
        client: PolarLicenseClient? = nil,
        now: @escaping () -> Date = Date.init,
        allowsDevelopmentPreview: Bool = true
    ) {
        developmentPreview = Self.developmentPreviewEnabled && allowsDevelopmentPreview
        self.configuration = configuration
        entitlement = LicenseEntitlement(now: now)
        self.store = store ?? KeychainLicenseStore()
        self.client = client ?? PolarLicenseClient(configuration: configuration)
        self.now = now

        if developmentPreview {
            state = Self.freePreviewEnabled ? .free : .pro
            entitlement.setProAccess(!Self.freePreviewEnabled)
        } else {
            guard configuration.isConfigured else {
                state = .notConfigured
                return
            }

            do {
                record = try self.store.load()
                displayKey = record?.displayKey
                if let record,
                    record.hasOfflineAccess(now: now(), gracePeriod: Self.offlineGracePeriod)
                {
                    entitlement.setProAccess(
                        true,
                        until: record.lastValidatedAt?.addingTimeInterval(Self.offlineGracePeriod))
                    state = .offlinePro
                } else {
                    state = .free
                }
            } catch {
                state = .failed
                message = "Tenuo could not read its saved license."
            }
        }
    }

    var hasProAccess: Bool { entitlement.isPro }

    var isDevelopmentPreview: Bool { developmentPreview && !Self.freePreviewEnabled }

    var isBusy: Bool {
        switch state {
        case .activating, .validating, .deactivating: return true
        default: return false
        }
    }

    func start() {
        guard !developmentPreview, configuration.isConfigured, record != nil else {
            return
        }
        validateStoredLicense()
    }

    func validateStoredLicense() {
        guard !developmentPreview, configuration.isConfigured, let record else {
            return
        }
        cancelTask()
        message = nil
        if record.hasOfflineAccess(now: now(), gracePeriod: Self.offlineGracePeriod) {
            setProAccess(true)
        } else {
            setProAccess(false)
        }
        state = .validating
        task = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                let result = try await client.validate(record: record)
                try Task.checkCancellation()
                applyValidation(result, to: record)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                applyValidationFailure(error, for: record)
            }
            guard !Task.isCancelled else { return }
            task = nil
            scheduleValidation()
        }
    }

    func activate(key: String) {
        if developmentPreview && Self.freePreviewEnabled {
            message =
                "License activation is unavailable in this preview. Relaunch without --free-preview to use the Debug Pro preview."
            return
        }
        guard !developmentPreview, configuration.isConfigured else { return }
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            message = "Paste a license key to continue."
            state = .free
            return
        }

        cancelTask()
        if let record, record.key == key {
            validateStoredLicense()
            return
        }
        message = nil
        state = .activating
        let oldRecord = record
        task = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                if let oldRecord {
                    do {
                        try await client.deactivate(record: oldRecord)
                    } catch let error as PolarLicenseError where error == .invalidLicense {
                    }
                    try Task.checkCancellation()
                    try store.remove()
                    self.record = nil
                    displayKey = nil
                    setProAccess(false)
                }
                let deviceName = Host.current().localizedName ?? "This Mac"
                let result = try await client.activate(
                    key: key,
                    label: "Tenuo · " + deviceName)
                try Task.checkCancellation()
                let next = LicenseRecord(
                    key: key,
                    activationID: result.activationID,
                    displayKey: result.displayKey ?? Self.displayKey(for: key),
                    lastValidatedAt: now())
                do {
                    try store.save(next)
                } catch {
                    try? await client.deactivate(record: next)
                    throw LicenseStoreError.unableToSave
                }
                self.record = next
                displayKey = next.displayKey
                setProAccess(true)
                state = .pro
            } catch is CancellationError {
            } catch let error as PolarLicenseError {
                guard !Task.isCancelled else { return }
                setProAccess(false)
                state = error == .invalidLicense ? .invalid : .failed
                message = error.localizedDescription
            } catch {
                guard !Task.isCancelled else { return }
                setProAccess(false)
                state = .failed
                message = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            task = nil
            scheduleValidation()
        }
    }

    func deactivate() {
        guard !developmentPreview else { return }
        guard configuration.isConfigured, let record else {
            clearLocalLicense()
            return
        }

        cancelTask()
        message = nil
        state = .deactivating
        task = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                try await client.deactivate(record: record)
                try Task.checkCancellation()
                clearLocalLicense()
            } catch is CancellationError {
            } catch let error as PolarLicenseError {
                guard !Task.isCancelled else { return }
                if error == .invalidLicense {
                    clearLocalLicense()
                } else {
                    state = hasProAccess ? .pro : .free
                    message = error.localizedDescription
                }
            } catch {
                guard !Task.isCancelled else { return }
                state = hasProAccess ? .pro : .free
                message = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            task = nil
            scheduleValidation()
        }
    }

    func stop() {
        cancelTask()
    }

    private func applyValidation(_ result: PolarValidationResult, to record: LicenseRecord) {
        let next = LicenseRecord(
            key: record.key,
            activationID: record.activationID,
            displayKey: result.displayKey ?? record.displayKey ?? Self.displayKey(for: record.key),
            lastValidatedAt: now())
        do {
            try store.save(next)
            self.record = next
            displayKey = next.displayKey
            setProAccess(true)
            state = .pro
            message = nil
        } catch {
            setProAccess(false)
            state = .failed
            message = error.localizedDescription
        }
    }

    private func applyValidationFailure(_ error: Error, for record: LicenseRecord) {
        if let error = error as? PolarLicenseError, error == .invalidLicense {
            setProAccess(false)
            let invalidated = LicenseRecord(
                key: record.key, activationID: record.activationID,
                displayKey: record.displayKey, lastValidatedAt: nil)
            self.record = invalidated
            state = .invalid
            message = error.localizedDescription
            do {
                try store.save(invalidated)
            } catch {
                do {
                    try store.remove()
                } catch {
                    message =
                        "This license is invalid. Tenuo could not clear its saved validation from Keychain."
                }
            }
            return
        }

        if record.hasOfflineAccess(now: now(), gracePeriod: Self.offlineGracePeriod) {
            setProAccess(true)
            state = .offlinePro
            message =
                "Could not verify the license right now. Pro stays available while you are offline."
            return
        }

        setProAccess(false)
        state = .failed
        message =
            (error as? LocalizedError)?.errorDescription
            ?? "Tenuo could not verify the license."
    }

    private func clearLocalLicense() {
        record = nil
        displayKey = nil
        setProAccess(false)
        state = .free
        message = nil
        do {
            try store.remove()
        } catch {
            state = .failed
            message = error.localizedDescription
        }
    }

    private func cancelTask() {
        validationTimer?.invalidate()
        validationTimer = nil
        task?.cancel()
        task = nil
    }

    private func setProAccess(_ enabled: Bool) {
        entitlement.setProAccess(
            enabled, until: record?.lastValidatedAt?.addingTimeInterval(Self.offlineGracePeriod))
    }

    private func scheduleValidation() {
        validationTimer?.invalidate()
        validationTimer = nil
        guard !developmentPreview, configuration.isConfigured, let record,
            let validatedAt = record.lastValidatedAt
        else { return }
        let remaining = validatedAt.addingTimeInterval(Self.offlineGracePeriod).timeIntervalSince(
            now())
        let interval = remaining > 0 ? min(remaining + 0.01, 3600) : 3600
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.validateStoredLicense() }
        }
        validationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    deinit { validationTimer?.invalidate() }

    private static func displayKey(for key: String) -> String {
        "****-\(key.suffix(6))"
    }
}
