import AppKit

@MainActor
final class MacActionRunner {
    private let availability: any ActionAvailability
    private enum ExecutionID: Hashable {
        case shortcut(String)
        case action(MacAction)
    }
    private var running: [ExecutionID: Task<Void, Never>] = [:]
    var onFailure: ((String) -> Void)?

    init(availability: any ActionAvailability) {
        self.availability = availability
    }

    func run(_ action: MacAction) {
        let id: ExecutionID
        if case let .shortcut(target) = action {
            id = .shortcut(target.id)
        } else {
            id = .action(action)
        }
        guard availability.canUse(.macAction), action.isValid, running[id] == nil else { return }
        running[id] = Task { [weak self] in
            guard let self else { return }
            defer { running[id] = nil }
            do {
                try Task.checkCancellation()
                guard availability.canUse(.macAction) else { return }
                try await execute(action)
            } catch {
                if !Task.isCancelled {
                    onFailure?("\(action.displayLabel): \(error.localizedDescription)")
                }
            }
        }
    }

    func cancelAll() {
        for task in running.values { task.cancel() }
    }

    private func execute(_ action: MacAction) async throws {
        switch action {
        case let .application(target):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.id)
            else {
                throw MacActionError.unavailable(
                    "App not found. Choose a replacement in the key’s settings.")
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        case let .url(value):
            guard let url = URL(string: value), NSWorkspace.shared.open(url) else {
                throw MacActionError.unavailable("The link could not be opened.")
            }
        case let .file(target):
            let url = try await Task.detached {
                var stale = false
                return try URL(
                    resolvingBookmarkData: target.bookmark,
                    options: [.withoutUI, .withoutMounting], relativeTo: nil,
                    bookmarkDataIsStale: &stale)
            }.value
            try Task.checkCancellation()
            guard availability.canUse(.macAction) else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard FileManager.default.fileExists(atPath: url.path), NSWorkspace.shared.open(url)
            else {
                throw MacActionError.unavailable(
                    "File not found or inaccessible. Choose it again in the key’s settings.")
            }
        case let .shortcut(target):
            _ = try await ShortcutsCommand.run(["run", target.id])
        }
    }
}

enum MacActionError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self {
        case let .unavailable(message): return message
        }
    }
}

private final class ShortcutProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
        if process.isRunning { process.terminate() }
    }

    func execute(_ arguments: [String], timeout: TimeInterval?) throws -> String {
        let output = Pipe()
        lock.lock()
        do {
            guard !cancelled else { throw CancellationError() }
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.standardOutput = arguments.first == "list" ? output : FileHandle.nullDevice
            try process.run()
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
        let expiry = DispatchWorkItem { [weak self] in self?.cancel() }
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: expiry)
        }
        defer { expiry.cancel() }
        let data =
            arguments.first == "list" ? output.fileHandleForReading.readDataToEndOfFile() : Data()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MacActionError.unavailable(
                "Shortcuts could not complete the request. Open Shortcuts to check its permissions or choose a replacement."
            )
        }
        return String(decoding: data, as: UTF8.self)
    }
}

enum ShortcutsCommand {
    static func run(_ arguments: [String], timeout: TimeInterval? = nil) async throws -> String {
        let process = ShortcutProcess()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await Task.detached(priority: .userInitiated) {
                try process.execute(arguments, timeout: timeout)
            }.value
        } onCancel: {
            process.cancel()
        }
    }
}

@MainActor
enum ShortcutCatalog {
    private static var cached: [NamedActionTarget]?
    private static var refreshedAt = Date.distantPast

    static func load(refresh: Bool = false) async throws -> [NamedActionTarget] {
        if !refresh, let cached, Date().timeIntervalSince(refreshedAt) < 60 { return cached }
        let output = try await ShortcutsCommand.run(["list", "--show-identifiers"], timeout: 15)
        let items = output.split(separator: "\n").compactMap { line -> NamedActionTarget? in
            guard let start = line.range(of: " (", options: .backwards), line.hasSuffix(")") else {
                return nil
            }
            let id = String(line[start.upperBound..<line.index(before: line.endIndex)])
            guard UUID(uuidString: id) != nil else { return nil }
            return NamedActionTarget(id: id, name: String(line[..<start.lowerBound]))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, items.isEmpty {
            throw MacActionError.unavailable(
                "The shortcut list could not be read. Try refreshing it.")
        }
        cached = items
        refreshedAt = Date()
        return items
    }
}
