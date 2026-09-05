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

    let entitlement: LicenseEntitlement
    let configuration: PolarConfiguration

    @Published private(set) var state: LicenseState
    @Published private(set) var message: String?
    @Published private(set) var displayKey: String?

    private let store: LicenseStore
    private let client: PolarLicenseClient
    private let now: () -> Date
    private var record: LicenseRecord?
    private var task: Task<Void, Never>?

    init(
        configuration: PolarConfiguration = PolarConfiguration(bundle: .main),
        store: LicenseStore? = nil,
        client: PolarLicenseClient? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        entitlement = LicenseEntitlement()
        self.store = store ?? KeychainLicenseStore()
        self.client = client ?? PolarLicenseClient(configuration: configuration)
        self.now = now

        if Self.developmentPreviewEnabled {
            state = .pro
            entitlement.setProAccess(true)
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
                    entitlement.setProAccess(true)
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

    var isDevelopmentPreview: Bool { Self.developmentPreviewEnabled }

    var isBusy: Bool {
        switch state {
        case .activating, .validating, .deactivating: return true
        default: return false
        }
    }

    func start() {
        guard !isDevelopmentPreview, configuration.isConfigured, record != nil else { return }
        validateStoredLicense()
    }

    func validateStoredLicense() {
        guard !isDevelopmentPreview, configuration.isConfigured, let record else { return }
        cancelTask()
        message = nil
        if record.hasOfflineAccess(now: now(), gracePeriod: Self.offlineGracePeriod) {
            entitlement.setProAccess(true)
        } else {
            entitlement.setProAccess(false)
        }
        state = .validating
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await client.validate(record: record)
                applyValidation(result, to: record)
            } catch is CancellationError {
            } catch {
                applyValidationFailure(error, for: record)
            }
            task = nil
        }
    }

    func activate(key: String) {
        guard !isDevelopmentPreview, configuration.isConfigured else { return }
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
            guard let self else { return }
            do {
                if let oldRecord {
                    do {
                        try await client.deactivate(record: oldRecord)
                    } catch let error as PolarLicenseError where error == .invalidLicense {
                    }
                    try store.remove()
                    self.record = nil
                    displayKey = nil
                    entitlement.setProAccess(false)
                }
                let deviceName = Host.current().localizedName ?? "This Mac"
                let result = try await client.activate(
                    key: key,
                    label: "Tenuo · " + deviceName)
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
                entitlement.setProAccess(true)
                state = .pro
            } catch is CancellationError {
            } catch let error as PolarLicenseError {
                entitlement.setProAccess(false)
                state = error == .invalidLicense ? .invalid : .failed
                message = error.localizedDescription
            } catch {
                entitlement.setProAccess(false)
                state = .failed
                message = error.localizedDescription
            }
            task = nil
        }
    }

    func deactivate() {
        guard !isDevelopmentPreview else { return }
        guard configuration.isConfigured, let record else {
            clearLocalLicense()
            return
        }

        cancelTask()
        message = nil
        state = .deactivating
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await client.deactivate(record: record)
                clearLocalLicense()
            } catch is CancellationError {
            } catch let error as PolarLicenseError {
                if error == .invalidLicense {
                    clearLocalLicense()
                } else {
                    state = hasProAccess ? .pro : .free
                    message = error.localizedDescription
                }
            } catch {
                state = hasProAccess ? .pro : .free
                message = error.localizedDescription
            }
            task = nil
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
            entitlement.setProAccess(true)
            state = .pro
            message = nil
        } catch {
            entitlement.setProAccess(false)
            state = .failed
            message = error.localizedDescription
        }
    }

    private func applyValidationFailure(_ error: Error, for record: LicenseRecord) {
        if let error = error as? PolarLicenseError, error == .invalidLicense {
            entitlement.setProAccess(false)
            state = .invalid
            message = error.localizedDescription
            return
        }

        if record.hasOfflineAccess(now: now(), gracePeriod: Self.offlineGracePeriod) {
            entitlement.setProAccess(true)
            state = .offlinePro
            message =
                "Could not verify the license right now. Pro stays available while you are offline."
            return
        }

        entitlement.setProAccess(false)
        state = .failed
        message =
            (error as? LocalizedError)?.errorDescription
            ?? "Tenuo could not verify the license."
    }

    private func clearLocalLicense() {
        record = nil
        displayKey = nil
        entitlement.setProAccess(false)
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
        task?.cancel()
        task = nil
    }

    private static func displayKey(for key: String) -> String {
        "****-\(key.suffix(6))"
    }
}
