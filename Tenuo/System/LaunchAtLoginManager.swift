import Foundation
import ServiceManagement
import os

final class LaunchAtLoginManager {
    private let log = Logger(subsystem: "com.tenuo.Tenuo", category: "login")
    private let service = SMAppService.mainApp

    var isEnabled: Bool {
        service.status == .enabled
    }

    var requiresApproval: Bool {
        service.status == .requiresApproval
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard service.status != .enabled else { return true }
                try service.register()
            } else {
                guard service.status != .notRegistered else { return true }
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
