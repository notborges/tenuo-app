import Foundation

enum LicenseState: Equatable {
    case notConfigured
    case free
    case activating
    case validating
    case pro
    case offlinePro
    case deactivating
    case invalid
    case failed
}

struct PolarConfiguration: Equatable {
    let apiURL: URL
    let organizationID: String
    let benefitID: String

    init(
        apiURL: URL = URL(string: "https://api.polar.sh")!,
        organizationID: String,
        benefitID: String
    ) {
        self.apiURL = apiURL
        self.organizationID = organizationID
        self.benefitID = benefitID
    }

    init(bundle: Bundle = .main) {
        let apiString = Self.value(for: "TenuoPolarAPIURL", in: bundle)
        apiURL = URL(string: apiString) ?? URL(string: "https://api.polar.sh")!
        organizationID = Self.value(for: "TenuoPolarOrganizationID", in: bundle)
        benefitID = Self.value(for: "TenuoPolarBenefitID", in: bundle)
    }

    var isConfigured: Bool {
        !organizationID.isEmpty && !benefitID.isEmpty && apiURL.scheme == "https"
            && apiURL.host != nil
    }

    private static func value(for key: String, in bundle: Bundle) -> String {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
            !value.isEmpty,
            !value.contains("$(")
        else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LicenseRecord: Codable, Equatable {
    let key: String
    let activationID: String
    let displayKey: String?
    let lastValidatedAt: Date?

    func hasOfflineAccess(now: Date, gracePeriod: TimeInterval) -> Bool {
        guard let lastValidatedAt else { return false }
        let elapsed = now.timeIntervalSince(lastValidatedAt)
        return elapsed >= 0 && elapsed <= gracePeriod
    }
}

final class LicenseEntitlement: ActionAvailability, @unchecked Sendable {
    private let lock = NSLock()
    private var hasProAccess = false
    private var expiresAt: Date?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    var isPro: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasProAccess && (expiresAt.map { now() <= $0 } ?? true)
    }

    func canUse(_ kind: ActionKind) -> Bool {
        guard kind.requiresPro else { return true }
        return isPro
    }

    func setProAccess(_ enabled: Bool, until expiresAt: Date? = nil) {
        lock.lock()
        hasProAccess = enabled
        self.expiresAt = expiresAt
        lock.unlock()
    }
}
