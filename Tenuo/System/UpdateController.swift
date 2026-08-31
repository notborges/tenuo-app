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
        case downloading(fraction: Double)
        case installing
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .checking, .downloading, .installing: return true
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
        subsystem: Bundle.main.bundleIdentifier ?? "app.tenuo.Tenuo",
        category: "updates")
    private var updater: SPUUpdater?

    private var wantsInstall = false
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0

    func start(checksAutomatically: Bool) {
        guard updater == nil else { return }
        guard Self.isConfigured else {
            log.info("No update feed configured; updater not started")
            return
        }

        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: self,
            delegate: nil)
        updater.automaticallyDownloadsUpdates = false
        updater.automaticallyChecksForUpdates = checksAutomatically
        updater.sendsSystemProfile = false

        do {
            try updater.start()
            self.updater = updater
        } catch {
            log.error("Updater failed to start: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }

    func check() {
        guard let updater, !status.isBusy else { return }
        wantsInstall = false
        status = .checking
        updater.checkForUpdates()
    }

    func install() {
        guard let updater, !status.isBusy else { return }
        wantsInstall = true
        status = .checking
        updater.checkForUpdates()
    }
}

extension UpdateController: SPUUserDriver {

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(
            SUUpdatePermissionResponse(
                automaticUpdateChecks: checksAutomatically,
                sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        status = .checking
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        lastChecked = Date()
        status = .available(version: appcastItem.displayVersionString)
        reply(wantsInstall ? .install : .dismiss)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        lastChecked = Date()
        status = .upToDate
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        log.error("Update failed: \(error.localizedDescription, privacy: .public)")
        status = .failed(error.localizedDescription)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedLength = 0
        receivedLength = 0
        status = .downloading(fraction: 0)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        guard expectedLength > 0 else { return }
        status = .downloading(fraction: min(1, Double(receivedLength) / Double(expectedLength)))
    }

    func showDownloadDidStartExtractingUpdate() {
        status = .installing
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        status = .installing
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        status = .installing
        reply(.install)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        status = .installing
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        acknowledgement()
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        wantsInstall = false
        if status.isBusy { status = .idle }
    }
}
