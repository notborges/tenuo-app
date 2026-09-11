import Foundation
import ServiceManagement
import os

final class LaunchAtLoginManager {
    private let log = Logger(subsystem: "app.tenuo", category: "login")
    private let service = SMAppService.mainApp

    var isRegistered: Bool {
        service.status == .enabled || service.status == .requiresApproval
    }

    var requiresApproval: Bool {
        service.status == .requiresApproval
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard !isRegistered else { return true }
                try service.register()
            } else {
                guard isRegistered else { return true }
                try service.unregister()
            }
            return true
        } catch {
            log.error(
                "Launch at login \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }
}
