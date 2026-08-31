import Foundation
import os

// CoreGraphics cannot reliably observe Caps Lock as a momentary trigger. The
// HID mapping makes it arrive at the event tap as F18 while Tenuo is running.
final class CapsLockRemapper {
    private static let capsLockUsage: UInt64 = 0x700000039
    private static let f18Usage: UInt64 = 0x70000006D
    private static let toolPath = "/usr/bin/hidutil"

    private static let sourceKey = "HIDKeyboardModifierMappingSrc"
    private static let destinationKey = "HIDKeyboardModifierMappingDst"

    private let log = Logger(subsystem: "com.tenuo.Tenuo", category: "remap")

    private let queue = DispatchQueue(label: "com.tenuo.remap", qos: .userInitiated)
    private var applied = false
    private var originalMappings: [[String: Any]]?

    func apply() {
        queue.async { [self] in
            guard !applied else { return }
            guard let existing = currentMappings() else {
                log.error("Could not read the current HID mappings")
                return
            }

            let updated =
                existing.filter { Self.source(of: $0) != Self.capsLockUsage }
                + [Self.tenuoMapping]
            guard setMappings(updated) else {
                log.error("Failed to install Caps Lock -> F18 mapping")
                return
            }
            originalMappings = existing
            applied = true
            log.info("Caps Lock remapped to F18")
        }
    }

    func revert(waitUntilFinished: Bool = false) {
        let work = { [self] in
            guard applied, let originalMappings else { return }
            guard let current = currentMappings() else {
                log.error("Could not read the current HID mappings")
                return
            }
            let restored =
                current.filter { Self.source(of: $0) != Self.capsLockUsage }
                + originalMappings.filter { Self.source(of: $0) == Self.capsLockUsage }
            if setMappings(restored) {
                log.info("Caps Lock mapping reverted")
                self.originalMappings = nil
                applied = false
            } else {
                log.error("Failed to revert Caps Lock mapping")
            }
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
            guard let existing = currentMappings() else {
                log.error("Could not read the current HID mappings")
                return
            }
            let updated =
                existing.filter { Self.source(of: $0) != Self.capsLockUsage }
                + [Self.tenuoMapping]
            if setMappings(updated) {
                log.info("Caps Lock mapping re-applied")
            } else {
                log.error("Failed to re-apply Caps Lock mapping")
            }
        }
    }

    private static let tenuoMapping: [String: Any] = [
        sourceKey: NSNumber(value: capsLockUsage),
        destinationKey: NSNumber(value: f18Usage),
    ]

    private static func source(of mapping: [String: Any]) -> UInt64? {
        usage(from: mapping[sourceKey])
    }

    private static func usage(from value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let string = value as? String { return UInt64(string) }
        return nil
    }

    private static func normalized(_ mapping: [String: Any]) -> [String: Any] {
        var normalized = mapping
        for key in [sourceKey, destinationKey] {
            if let usage = usage(from: normalized[key]) {
                normalized[key] = NSNumber(value: usage)
            }
        }
        return normalized
    }

    private func currentMappings() -> [[String: Any]]? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: Self.toolPath)
        process.arguments = ["property", "--get", "UserKeyMapping"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            var format = PropertyListSerialization.PropertyListFormat.openStep
            let value = try PropertyListSerialization.propertyList(
                from: data, options: [], format: &format)
            guard let values = value as? [Any], values.allSatisfy({ $0 is [String: Any] })
            else { return nil }
            return values.compactMap { $0 as? [String: Any] }.map(Self.normalized)
        } catch {
            log.error("hidutil read failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func setMappings(_ mappings: [[String: Any]]) -> Bool {
        guard
            let payloadData = try? JSONSerialization.data(
                withJSONObject: ["UserKeyMapping": mappings]),
            let payload = String(data: payloadData, encoding: .utf8)
        else { return false }

        return runSynchronously(payload: payload)
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
