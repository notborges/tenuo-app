import Foundation
import IOKit.hid
import os

/// AppKit scroll phases also occur on mice. Raw contacts identify trackpad input;
/// gesture recognition and suppression still use the existing CGEvent tap.
final class TrackpadContacts {
    static let shared = TrackpadContacts()
    private typealias Callback =
        @convention(c) (
            UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
        ) -> Void
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias GetService = @convention(c) (UnsafeMutableRawPointer) -> io_service_t
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?

    private let contacts = OSAllocatedUnfairLock(initialState: [UInt: TimeInterval]())
    private var devices: [UInt64: AnyObject] = [:]
    private var notificationPort: IONotificationPortRef?
    private var connectedIterator: io_iterator_t = 0
    private var disconnectedIterator: io_iterator_t = 0
    private let library: UnsafeMutableRawPointer?
    private let createList: CreateList?
    private let register: Register?
    private let unregister: Register?
    private let startDevice: Start?
    private let stopDevice: Stop?
    private let getService: GetService?

    private static let callback: Callback = { device, _, count, _, _ in
        guard let device else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let id = UInt(bitPattern: device)
        shared.contacts.withLock { samples in
            // Raw frames include incidental contacts that macOS ignores when recognizing
            // a scroll. Use them to identify trackpad activity, not to count swipe fingers.
            // Keep the last frame briefly because scrolling can arrive after lift-off.
            if count >= 2 { samples[id] = now }
        }
    }

    private init() {
        let library = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_LAZY | RTLD_LOCAL)
        self.library = library
        func symbol<T>(_ name: String, _: T.Type) -> T? {
            guard let library, let address = dlsym(library, name) else { return nil }
            return unsafeBitCast(address, to: T.self)
        }
        createList = symbol("MTDeviceCreateList", CreateList.self)
        register = symbol("MTRegisterContactFrameCallback", Register.self)
        unregister = symbol("MTUnregisterContactFrameCallback", Register.self)
        startDevice = symbol("MTDeviceStart", Start.self)
        stopDevice = symbol("MTDeviceStop", Stop.self)
        getService = symbol("MTDeviceGetService", GetService.self)
    }

    var hasRecentScrollContact: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return contacts.withLock { $0.values.contains { now - $0 < 0.15 } }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard notificationPort == nil,
                let port = IONotificationPortCreate(kIOMainPortDefault)
            else { return }
            notificationPort = port
            IONotificationPortSetDispatchQueue(port, .main)
            let context = Unmanaged.passUnretained(self).toOpaque()
            guard
                IOServiceAddMatchingNotification(
                    port, kIOFirstMatchNotification, IOServiceMatching("AppleMultitouchDevice"),
                    Self.devicesChanged, context, &connectedIterator) == KERN_SUCCESS,
                IOServiceAddMatchingNotification(
                    port, kIOTerminatedNotification, IOServiceMatching("AppleMultitouchDevice"),
                    Self.devicesChanged, context, &disconnectedIterator) == KERN_SUCCESS
            else {
                setEnabled(false)
                return
            }
            Self.drain(connectedIterator)
            Self.drain(disconnectedIterator)
            refreshDevices()
        } else {
            if connectedIterator != 0 { IOObjectRelease(connectedIterator); connectedIterator = 0 }
            if disconnectedIterator != 0 {
                IOObjectRelease(disconnectedIterator); disconnectedIterator = 0
            }
            if let notificationPort { IONotificationPortDestroy(notificationPort) }
            notificationPort = nil
            for object in devices.values { remove(object) }
            devices.removeAll()
            contacts.withLock { $0.removeAll() }
        }
    }

    private static let devicesChanged: IOServiceMatchingCallback = { context, iterator in
        drain(iterator)
        guard let context else { return }
        let observer = Unmanaged<TrackpadContacts>.fromOpaque(context).takeUnretainedValue()
        if observer.notificationPort != nil { observer.refreshDevices() }
    }

    private static func drain(_ iterator: io_iterator_t) {
        while case let device = IOIteratorNext(iterator), device != 0 { IOObjectRelease(device) }
    }

    private func refreshDevices() {
        guard let createList, let register, let unregister, let startDevice, let stopDevice,
            let getService, let list = createList()?.takeRetainedValue()
        else { return }
        let objects = (list as NSArray).map { $0 as AnyObject }
        var present = Set<UInt64>()
        for object in objects {
            let pointer = Unmanaged.passUnretained(object).toOpaque()
            let service = getService(pointer)
            guard service != 0,
                let usages = IORegistryEntryCreateCFProperty(
                    service, kIOHIDDeviceUsagePairsKey as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? [[String: Int]],
                usages.contains(where: {
                    $0[kIOHIDDeviceUsagePageKey] == kHIDPage_Digitizer
                        && $0[kIOHIDDeviceUsageKey] == kHIDUsage_Dig_TouchPad
                })
            else { continue }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS else { continue }
            present.insert(id)
            guard devices[id] == nil else { continue }
            register(pointer, Self.callback)
            if startDevice(pointer, 0) == 0 {
                devices[id] = object
            } else {
                unregister(pointer, Self.callback)
                _ = stopDevice(pointer)
            }
        }
        for id in Set(devices.keys).subtracting(present) {
            if let object = devices.removeValue(forKey: id) { remove(object) }
        }
    }

    private func remove(_ object: AnyObject) {
        let pointer = Unmanaged.passUnretained(object).toOpaque()
        unregister?(pointer, Self.callback)
        _ = stopDevice?(pointer)
        let contactID = UInt(bitPattern: pointer)
        contacts.withLock { $0[contactID] = nil }
    }
}
