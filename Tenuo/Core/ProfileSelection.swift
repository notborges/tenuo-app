import Foundation

enum ProfileSelectionReason: String, Equatable, Sendable {
    case manual
}

struct EffectiveProfile: Equatable, Sendable {
    let profile: Profile
    let profileID: UUID?
    let reason: ProfileSelectionReason
}

protocol ProfileSelectionSource: AnyObject {
    var current: EffectiveProfile { get }
    var onChange: ((EffectiveProfile) -> Void)? { get set }

    func start()
    func stop()
    func refresh()
}

final class ManualProfileSelectionSource: ProfileSelectionSource {
    private let store: ProfileStore
    private var observerToken: UUID?

    private(set) var current: EffectiveProfile
    var onChange: ((EffectiveProfile) -> Void)?

    init(store: ProfileStore) {
        self.store = store
        current = Self.effectiveProfile(from: store.snapshot)
    }

    func start() {
        guard observerToken == nil else { return }
        observerToken = store.addObserver { [weak self] _ in self?.refresh() }
        refresh()
    }

    func stop() {
        if let observerToken {
            store.removeObserver(observerToken)
            self.observerToken = nil
        }
    }

    func refresh() {
        let next = Self.effectiveProfile(from: store.snapshot)
        guard next != current else { return }
        current = next
        onChange?(next)
    }

    private static func effectiveProfile(from snapshot: ProfileStoreSnapshot) -> EffectiveProfile {
        EffectiveProfile(
            profile: snapshot.manualProfile,
            profileID: snapshot.manualProfileID,
            reason: .manual)
    }

    deinit {
        stop()
    }
}
