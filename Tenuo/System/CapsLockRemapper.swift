import Foundation
import os

// CoreGraphics cannot reliably observe Caps Lock as a momentary trigger. The
// HID mapping makes it arrive at the event tap as F18 while Tenuo is running.
final class CapsLockRemapper {
    private static let capsLockUsage: UInt64 = 0x700000039
    private static let f18Usage: UInt64 = 0x70000006D
    private static let toolPath = "/usr/bin/hidutil"

    private static let mapping = """
        {"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":\(capsLockUsage),\
        "HIDKeyboardModifierMappingDst":\(f18Usage)}]}
        """
    private static let cleared = #"{"UserKeyMapping":[]}"#

    private let log = Logger(subsystem: "com.tenuo.Tenuo", category: "remap")

    private let queue = DispatchQueue(label: "com.tenuo.remap", qos: .userInitiated)
    private var applied = false

    func apply() {
        queue.async { [self] in
            guard !applied else { return }
            guard runSynchronously(payload: Self.mapping) else {
                log.error("Failed to install Caps Lock -> F18 mapping")
                return
            }
            applied = true
            log.info("Caps Lock remapped to F18")
        }
    }

    func revert(waitUntilFinished: Bool = false) {
        let work = { [self] in
            guard applied else { return }
            if runSynchronously(payload: Self.cleared) {
                log.info("Caps Lock mapping reverted")
            } else {
                log.error("Failed to revert Caps Lock mapping")
            }
            applied = false
        }
        if waitUntilFinished {
            queue.sync(execute: work)
        } else {
            queue.async(execute: work)
        }
    }

    func reapplyIfNeeded() {
        queue.async { [self] in
            guard applied else { return }
            if runSynchronously(payload: Self.mapping) {
                log.info("Caps Lock mapping re-applied")
            } else {
                log.error("Failed to re-apply Caps Lock mapping")
            }
        }
    }

    private func runSynchronously(payload: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.toolPath)
        process.arguments = ["property", "--set", payload]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            log.error("hidutil failed to launch: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
