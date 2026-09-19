import Combine
import Foundation

@MainActor
final class ProfileSyncController: ObservableObject {
    enum Status: Equatable {
        case off, unavailable, requiresPro, checking, reviewing, syncing, current, waiting,
            attention
    }

    @Published private(set) var status = Status.off
    @Published private(set) var message: String?
    @Published private(set) var conflicts: [ProfileSyncConflict] = []
    @Published private(set) var preview: [String]?
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var hasDeferredChanges = false
    let store: SQLiteProfileStore?
    private let hasPro: () -> Bool
    private let factory: ProfileSyncTransportFactory?
    private var transport: (any ProfileSyncTransport)?
    private var retryTimer: Timer?
    private var work: Task<Void, Never>?
    private var generation = UUID()
    private var reviewing = false
    private var connectionBlocked = false
    private var reviewAccount: String?
    private var reviewRecords: [CloudProfileRecord] = []
    private var reviewEngineState: Data?
    var canApply: () -> Bool = { true }

    init(
        store: SQLiteProfileStore?, hasPro: @escaping () -> Bool,
        factory: ProfileSyncTransportFactory? = CloudProfileTransport.factory
    ) {
        self.store = store
        self.hasPro = hasPro
        self.factory = factory
        store?.onSyncChange = { [weak self] in self?.storeChanged() }
        refreshPresentation()
    }

    func entitlementChanged() {
        if !hasPro() {
            pauseService()
            status = .requiresPro
        } else if enabled && work == nil && transport == nil {
            syncNow()
        } else {
            refreshPresentation()
        }
    }

    var enabled: Bool { store?.state.enabled == true }
    var isConfigured: Bool { store != nil && factory != nil }
    var isBusy: Bool { work != nil }
    var localProfileCount: Int { store?.profiles.count ?? 0 }

    func start() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !connectionBlocked else { return }
                syncNow()
            }
        }
        syncNow()
    }

    func localProfile(_ id: UUID) -> Profile? {
        store?.state.snapshot.profiles.first { $0.id == id }
    }
    func isSelected(_ id: UUID) -> Bool { store?.snapshot.manualProfileID == id }

    func prepare() {
        guard hasPro() else { status = .requiresPro; return }
        guard let store, let factory else { status = .unavailable; return }
        pauseService()
        reviewing = true
        connectionBlocked = false
        message = nil
        status = .checking
        let token = generation
        let transport = makeTransport(factory, token: token)
        self.transport = transport
        work = Task.detached { @MainActor [weak self] in
            guard let self else { return }
            do {
                let account = try await transport.accountID()
                guard valid(token) else { return }
                reviewAccount = account
                try await transport.start(serializedState: nil)
                try await transport.fetch()
                guard valid(token) else { return }
                let remote = try reviewRecords.map { try self.decode($0) }
                var candidate = store.state
                candidate.incoming = [:]
                candidate.conflicts = [:]
                try candidate.connectAccount(account)
                candidate.prepareFullFetch(recordIDs: Set(remote.map(\.id)))
                for document in remote { try candidate.receive(document) }
                try candidate.reconcile(protectedProfileID: nil)
                preview = candidate.snapshot.profiles.map(\.name)
                message =
                    candidate.conflicts.isEmpty
                    ? "Your profiles will be combined with the profiles in iCloud."
                    : "\(candidate.conflicts.count) profile(s) have different versions. Both versions will be kept for review."
                if let previousAccount = store.state.accountID, previousAccount != account {
                    message =
                        "You’re connecting a different Apple Account. The profiles on this Mac will be copied to that account when you connect. Your previous iCloud library stays unchanged."
                }
                status = .reviewing
            } catch {
                if valid(token) { status = .attention; message = error.localizedDescription }
            }
            if token == generation { work = nil }
        }
    }

    func confirm() {
        guard hasPro(), reviewing, preview != nil, let account = reviewAccount,
            let store
        else { return }
        do {
            try store.transaction { state in
                for profile in state.snapshot.profiles { state.recordHistory(profile) }
                try state.connectAccount(account)
                state.enabled = true
                state.incoming = [:]
                state.conflicts = [:]
                state.prepareFullFetch(recordIDs: Set(reviewRecords.map(\.id)))
                for record in reviewRecords {
                    let document = try decode(record)
                    state.serverFields[record.id] = record.systemFields
                    try state.receive(document)
                }
                state.engineState = reviewEngineState
                try state.reconcile(
                    protectedProfileID: canApply() ? nil : state.snapshot.manualProfileID)
            }
            pauseService()
            syncNow()
        } catch { status = .attention; message = error.localizedDescription }
    }

    func cancelSetup() {
        pauseService()
        connectionBlocked = false
        refreshPresentation()
        if enabled { syncNow() }
    }

    func disable() {
        pauseService()
        connectionBlocked = false
        do { try store?.transaction { $0.enabled = false }; status = .off; message = nil } catch {
            status = .attention; message = error.localizedDescription
        }
    }

    func syncNow() {
        guard work == nil, enabled, !reviewing, hasPro(),
            let store, let factory
        else { refreshPresentation(); return }
        message = nil
        connectionBlocked = false
        status = .syncing
        let startingRevisions = store.state.pending.mapValues(\.revision)
        let token = generation
        work = Task.detached { @MainActor [weak self] in
            guard let self else { return }
            do {
                let active: any ProfileSyncTransport
                if let transport {
                    active = transport
                } else {
                    active = makeTransport(factory, token: token)
                    transport = active
                    let account = try await active.accountID()
                    guard valid(token) else { return }
                    guard account == store.state.accountID else {
                        throw ProfileSyncError.accountChanged
                    }
                    try await active.start(serializedState: store.state.engineState)
                }
                try await active.fetch()
                guard valid(token), enabled else { return }
                try reconcile()
                let documents = store.state.pending.values.filter {
                    store.state.conflicts[$0.id] == nil && store.state.incoming[$0.id] == nil
                        && store.state.quarantined[$0.id] == nil
                }
                if !documents.isEmpty {
                    try await active.send(documents, fields: store.state.serverFields)
                }
                guard valid(token), enabled else { return }
                if store.state.pending.isEmpty && store.state.incoming.isEmpty
                    && store.state.conflicts.isEmpty && store.state.quarantined.isEmpty
                {
                    try store.transaction { $0.lastSyncedAt = Date() }
                    status = .current
                } else {
                    status = .waiting
                }
            } catch {
                guard valid(token) else { return }
                connectionBlocked = error is ProfileSyncError
                status = connectionBlocked ? .attention : .waiting
                message = error.localizedDescription
                pauseService()
            }
            if token == generation {
                work = nil
                refreshPresentation()
                if store.state.pending.contains(where: {
                    startingRevisions[$0.key] != $0.value.revision
                }) {
                    storeChanged()
                }
            }
        }
    }

    func applyWaitingChanges() {
        guard hasPro(), enabled else { return }
        guard hasDeferredChanges, canApply() else { return }
        do { try reconcile(); refreshPresentation(); syncNow() } catch {
            status = .attention; message = error.localizedDescription
        }
    }

    func resolve(_ conflict: ProfileSyncConflict, keepLocal: Bool) {
        guard hasPro(), enabled, let store, canApply() else {
            message =
                "Release your layer keys and turn off toggled layers before resolving this profile."
            return
        }
        do {
            try store.transaction { state in
                guard state.conflicts[conflict.id] == conflict else {
                    throw ProfileSyncError.unresolvedConflict
                }
                let remote = conflict.remote
                if keepLocal {
                    if let remoteProfile = remote.profile {
                        state.recordHistory(remoteProfile)
                    }
                    let profile = state.snapshot.profiles.first { $0.id == conflict.id }
                    state.acknowledged[conflict.id] = remote
                    state.pending[conflict.id] = SyncedProfile(
                        id: conflict.id, revision: UUID(), profile: profile,
                        position: state.snapshot.profiles.firstIndex(where: { $0.id == conflict.id }
                        ) ?? remote.position)
                } else {
                    if remote.profile == nil && state.snapshot.manualProfileID == conflict.id {
                        throw ProfileSyncError.unresolvedConflict
                    }
                    try state.apply(remote)
                    state.acknowledged[conflict.id] = remote
                    state.pending[conflict.id] = nil
                }
                state.conflicts[conflict.id] = nil
            }
            syncNow()
        } catch { message = error.localizedDescription; status = .attention }
    }

    func stop() { retryTimer?.invalidate(); retryTimer = nil; pauseService() }

    private func makeTransport(_ factory: ProfileSyncTransportFactory, token: UUID)
        -> any ProfileSyncTransport
    {
        factory(
            { [weak self] event in
                await self?.receive(event, token: token)
            },
            { [weak self] in
                await self?.maySend(token) == true
            })
    }

    private func maySend(_ token: UUID) -> Bool { valid(token) && enabled && !reviewing }

    private func valid(_ token: UUID) -> Bool { token == generation && hasPro() }

    private func receive(_ event: CloudProfileEvent, token: UUID) async {
        guard valid(token), let store else { return }
        do {
            switch event {
            case .accountChanged:
                let account = try await transport?.accountID()
                guard valid(token) else { return }
                guard account == (reviewing ? reviewAccount : store.state.accountID) else {
                    throw ProfileSyncError.accountChanged
                }
            case let .state(data):
                if reviewing {
                    reviewEngineState = data
                } else if enabled {
                    try store.transaction { $0.engineState = data }
                }
            case let .received(records):
                let account = try await transport?.accountID()
                guard valid(token) else { return }
                guard account == (reviewing ? reviewAccount : store.state.accountID)
                else { throw ProfileSyncError.accountChanged }
                if reviewing {
                    for record in records {
                        reviewRecords.removeAll { $0.id == record.id }
                        reviewRecords.append(record)
                    }
                } else if enabled {
                    try store.transaction { state in
                        for record in records {
                            state.serverFields[record.id] = record.systemFields
                            do {
                                try state.receive(decode(record));
                                state.quarantined[record.id] = nil
                            } catch { state.quarantined[record.id] = record.payload }
                        }
                        try state.reconcile(
                            protectedProfileID: canApply() ? nil : state.snapshot.manualProfileID)
                    }
                }
            case let .saved(records):
                let account = try await transport?.accountID()
                guard valid(token) else { return }
                guard account == store.state.accountID else {
                    throw ProfileSyncError.accountChanged
                }
                guard enabled, !reviewing else { return }
                try store.transaction { state in
                    for record in records {
                        state.serverFields[record.id] = record.systemFields
                        state.acknowledge(try decode(record))
                    }
                }
            case let .waiting(text):
                message = text
                status = .waiting
            case let .failure(text):
                connectionBlocked = true
                message = text
                status = .attention
                pauseService()
            }
            refreshPresentation()
        } catch {
            guard valid(token) else { return }
            connectionBlocked = true
            message = error.localizedDescription; status = .attention; pauseService()
        }
    }

    private func decode(_ record: CloudProfileRecord) throws -> SyncedProfile {
        guard record.payload.count < 900_000 else { throw ProfileSyncError.invalidDocument }
        let document = try JSONDecoder().decode(SyncedProfile.self, from: record.payload)
        guard document.id == record.id else { throw ProfileSyncError.invalidDocument }
        try document.validate()
        return document
    }

    private func reconcile() throws {
        try store?.transaction { state in
            state.retryQuarantinedProfiles()
            try state.reconcile(
                protectedProfileID: canApply() ? nil : state.snapshot.manualProfileID)
        }
    }

    private func storeChanged() {
        refreshPresentation()
        guard enabled, !reviewing, work == nil, !connectionBlocked,
            let state = store?.state,
            state.pending.keys.contains(where: {
                state.conflicts[$0] == nil && state.incoming[$0] == nil
                    && state.quarantined[$0] == nil
            })
        else { return }
        let token = generation
        work = Task.detached { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, valid(token), !Task.isCancelled else { return }
            work = nil
            syncNow()
        }
    }

    private func pauseService() {
        generation = UUID()
        work?.cancel()
        work = nil
        reviewing = false
        preview = nil
        reviewAccount = nil
        reviewRecords = []
        reviewEngineState = nil
        let old = transport
        transport = nil
        Task.detached { await old?.stop() }
    }

    private func refreshPresentation() {
        conflicts =
            store?.state.conflicts.values.sorted { $0.id.uuidString < $1.id.uuidString } ?? []
        lastSyncedAt = store?.state.lastSyncedAt
        hasDeferredChanges = store?.state.incoming.isEmpty == false
        if !hasPro() {
            status = .requiresPro
        } else if !isConfigured {
            status = .unavailable
        } else if connectionBlocked {
            status = .attention
        } else if !enabled && !reviewing {
            status = .off
        } else if !conflicts.isEmpty || store?.state.quarantined.isEmpty == false {
            status = .attention
            if store?.state.quarantined.isEmpty == false && message == nil {
                message =
                    "Some iCloud profiles could not be read. They have been kept unchanged. Update Tenuo, then try again."
            }
        } else if status == .current && store?.state.pending.isEmpty == false {
            status = .waiting
        }
    }
}
