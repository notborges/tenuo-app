import Foundation

@MainActor
final class ProfileEditSession {
    private static let maximumUndoLevels = 100
    let undoManager = UndoManager()
    var onFailure: (() -> Void)?
    var onChange: (() -> Void)?
    private let store: any ProfileStore
    private var editing = false
    private var observer: UUID?

    init(store: any ProfileStore) {
        self.store = store
        undoManager.levelsOfUndo = Self.maximumUndoLevels
        observeStore()
    }

    deinit {
        if let observer { store.removeObserver(observer) }
    }

    private func observeStore() {
        guard observer == nil else { return }
        observer = store.addObserver { [weak self] change in
            guard let self, !editing, change.previous.profiles != change.current.profiles else {
                return
            }
            undoManager.removeAllActions()
            self.store.history.endSession()
        }
    }

    @discardableResult
    func perform(_ name: String = "Profile Edit", _ operation: () throws -> Bool) rethrows -> Bool {
        observeStore()
        let before = store.snapshot
        editing = true
        defer { editing = false }
        guard try operation() else { return false }
        if before.profiles != store.snapshot.profiles { register(before, name: name) }
        return true
    }

    func endSession() {
        if let observer { store.removeObserver(observer) }
        observer = nil
        store.history.endSession()
        undoManager.removeAllActions()
    }

    private func register(_ snapshot: ProfileStoreSnapshot, name: String) {
        undoManager.registerUndo(withTarget: self) { target in
            let current = target.store.snapshot
            let selected =
                snapshot.profiles.contains { $0.id == current.manualProfileID }
                ? current.manualProfileID : snapshot.manualProfileID
            guard
                target.perform(
                    name,
                    {
                        target.store.replaceProfiles(snapshot.profiles, selecting: selected)
                    })
            else {
                target.undoManager.removeAllActions()
                target.onFailure?()
                return
            }
            target.onChange?()
        }
        undoManager.setActionName(name)
    }
}
