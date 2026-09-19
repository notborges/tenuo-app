import AppKit
import Foundation
import IOKit
import IOKit.hid
import os

final class SystemEventObserver {
    private let log = Logger(subsystem: "app.tenuo", category: "system")

    var onShouldResetState: (() -> Void)?
    var onShouldReapplyRemap: (() -> Void)?

    private var notificationPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var observers: [NSObjectProtocol] = []
    private var reapplyWorkItem: DispatchWorkItem?

    func start() {
        registerWorkspaceObservers()
        registerScreenLockObservers()
        registerKeyboardObservers()
    }

    private func registerWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        for name in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.log.info("Reset on \(name.rawValue, privacy: .public)")
                    self?.onShouldResetState?()
                })
        }

        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.log.info("Recover on \(name.rawValue, privacy: .public)")
                    self?.onShouldResetState?()
                    self?.scheduleReapply()
                })
        }

        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.onShouldResetState?()
                })
        }
    }

    private func registerScreenLockObservers() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            observers.append(
                center.addObserver(
                    forName: Notification.Name(name),
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.log.info("Reset on \(name, privacy: .public)")
                    self?.onShouldResetState?()
                })
        }
    }

    private func registerKeyboardObservers() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else {
            log.error("Could not create IOKit notification port")
            return
        }
        notificationPort = port
        IONotificationPortSetDispatchQueue(port, .main)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            var service = IOIteratorNext(iterator)
            var changed = false
            while service != 0 {
                IOObjectRelease(service)
                changed = true
                service = IOIteratorNext(iterator)
            }
            guard changed, let refcon else { return }
            let observer = Unmanaged<SystemEventObserver>.fromOpaque(refcon).takeUnretainedValue()
            observer.handleKeyboardChange()
        }

        guard let matched = Self.keyboardMatchingDictionary(),
            let terminated = Self.keyboardMatchingDictionary()
        else {
            log.error("Could not build keyboard matching dictionary")
            return
        }
        IOServiceAddMatchingNotification(
            port, kIOMatchedNotification, matched,
            callback, context, &matchedIterator)
        IOServiceAddMatchingNotification(
            port, kIOTerminatedNotification, terminated,
            callback, context, &terminatedIterator)

        drain(matchedIterator)
        drain(terminatedIterator)
    }

    private static func keyboardMatchingDictionary() -> CFDictionary? {
        guard let matching = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary? else {
            return nil
        }
        matching[kIOHIDPrimaryUsagePageKey] = kHIDPage_GenericDesktop
        matching[kIOHIDPrimaryUsageKey] = kHIDUsage_GD_Keyboard
        return matching as CFDictionary
    }

    private func drain(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private func handleKeyboardChange() {
        Task { @MainActor in KeyboardPresentation.shared.resetKeyboardDetection() }
        log.info("Keyboard set changed")
        onShouldResetState?()
        scheduleReapply()
    }

    private func scheduleReapply() {
        reapplyWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onShouldReapplyRemap?() }
        reapplyWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
            distributed.removeObserver(observer)
        }
        reapplyWorkItem?.cancel()
        if matchedIterator != 0 { IOObjectRelease(matchedIterator) }
        if terminatedIterator != 0 { IOObjectRelease(terminatedIterator) }
        if let notificationPort { IONotificationPortDestroy(notificationPort) }
    }
}
