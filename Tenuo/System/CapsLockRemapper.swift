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

    private let log = Logger(subsystem: "app.tenuo", category: "remap")

    private let queue = DispatchQueue(label: "app.tenuo.remap", qos: .userInitiated)
    private var applied = false
    private var originalMappings: [[String: Any]]?

    func ensureApplied(completion: @escaping (Bool) -> Void = { _ in }) {
        queue.async { [self] in
            guard let existing = currentMappings() else {
                log.error("Could not read the current HID mappings")
                finish(false, completion: completion)
                return
            }

            if originalMappings == nil {
                originalMappings = existing.filter { !Self.isTenuoMapping($0) }
            }

            let updated =
                existing.filter { !Self.isCapsLockMapping($0) }
                + [Self.tenuoMapping]
            guard setMappings(updated) else {
                log.error("Failed to install Caps Lock -> F18 mapping")
                applied = false
                finish(false, completion: completion)
                return
            }
            guard
                let verified = currentMappings(),
                verified.contains(where: Self.isTenuoMapping)
            else {
                log.error("Caps Lock -> F18 mapping was not installed")
                applied = false
                finish(false, completion: completion)
                return
            }
            applied = true
            log.info("Caps Lock remapped to F18")
            finish(true, completion: completion)
        }
    }

    func revert(
        waitUntilFinished: Bool = false,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        let work = { [self] in
            guard let current = currentMappings() else {
                log.error("Could not read the current HID mappings")
                finish(false, completion: completion)
                return
            }

            let hasTenuoMapping = current.contains(where: Self.isTenuoMapping)
            guard applied || hasTenuoMapping else {
                originalMappings = nil
                finish(true, completion: completion)
                return
            }

            let restored =
                current.filter { !Self.isCapsLockMapping($0) }
                + (originalMappings ?? []).filter { Self.isCapsLockMapping($0) }
            guard setMappings(restored) else {
                log.error("Failed to revert Caps Lock mapping")
                finish(false, completion: completion)
                return
            }

            guard
                let verified = currentMappings(),
                !verified.contains(where: Self.isTenuoMapping)
            else {
                log.error("Caps Lock mapping remained after revert")
                finish(false, completion: completion)
                return
            }

            log.info("Caps Lock mapping reverted")
            self.originalMappings = nil
            applied = false
            finish(true, completion: completion)
        }
        if waitUntilFinished {
            queue.sync(execute: work)
        } else {
            queue.async(execute: work)
        }
    }

    private static let tenuoMapping: [String: Any] = [
        sourceKey: NSNumber(value: capsLockUsage),
        destinationKey: NSNumber(value: f18Usage),
    ]

    private static func source(of mapping: [String: Any]) -> UInt64? {
        usage(from: mapping[sourceKey])
    }

    private static func destination(of mapping: [String: Any]) -> UInt64? {
        usage(from: mapping[destinationKey])
    }

    private static func isCapsLockMapping(_ mapping: [String: Any]) -> Bool {
        source(of: mapping) == capsLockUsage
    }

    private static func isTenuoMapping(_ mapping: [String: Any]) -> Bool {
        source(of: mapping) == capsLockUsage && destination(of: mapping) == f18Usage
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

            return HIDMappingParser.parse(data)?.map(Self.normalized)
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

    private func finish(_ success: Bool, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            completion(success)
        }
    }
}
