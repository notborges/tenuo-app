import AppKit
import Foundation
import Sparkle
import os

@MainActor
final class UpdateController: NSObject, ObservableObject {

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .checking: return true
            default: return false
            }
        }
    }

    static let isConfigured: Bool = {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        guard let feed = feed?.trimmingCharacters(in: .whitespacesAndNewlines),
            !feed.isEmpty,
            let url = URL(string: feed), url.scheme != nil
        else { return false }
        return true
    }()

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?

    var checksAutomatically: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    private let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.tenuo",
        category: "updates")
    private var updater: SPUUpdater?

    func start(checksAutomatically: Bool) {
        guard updater == nil else { return }
        guard Self.isConfigured else {
            log.info("No update feed configured; updater not started")
            return
        }

        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: SPUStandardUserDriver(hostBundle: .main, delegate: nil),
            delegate: self)
        updater.automaticallyDownloadsUpdates = false
        updater.automaticallyChecksForUpdates = checksAutomatically
        updater.sendsSystemProfile = false

        do {
            try updater.start()
            self.updater = updater
            lastChecked = updater.lastUpdateCheckDate
            if updater.automaticallyChecksForUpdates {
                status = .checking
                updater.checkForUpdatesInBackground()
            }
        } catch {
            log.error("Updater failed to start: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }

    func check() {
        guard let updater else { return }
        if !updater.sessionInProgress { status = .checking }
        updater.checkForUpdates()
    }
}

extension UpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        lastChecked = Date()
        status = .available(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        lastChecked = Date()
        status = .upToDate
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        lastChecked = updater.lastUpdateCheckDate
        if let error = error as NSError?,
            error.domain != SUSparkleErrorDomain
                || (error.code != SUError.noUpdateError.rawValue
                    && error.code != SUError.installationCanceledError.rawValue)
        {
            log.error("Update failed: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        } else if status != .upToDate {
            status = .idle
        }
    }
}
