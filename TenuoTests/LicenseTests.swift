import Combine
import Foundation
import XCTest

final class LicenseTests: XCTestCase {
    func testOnlyMacActionsRequirePro() {
        let entitlement = LicenseEntitlement()

        XCTAssertTrue(entitlement.canUse(.sendKey))
        XCTAssertTrue(entitlement.canUse(.toggleLayer))
        XCTAssertTrue(entitlement.canUse(.oneShotLayer))
        XCTAssertFalse(entitlement.canUse(.macAction))

        entitlement.setProAccess(true)

        XCTAssertTrue(entitlement.canUse(.macAction))
    }

    @MainActor
    func testOfflineAccessExpiresWhileRunning() async {
        let configuration = PolarConfiguration(
            apiURL: URL(string: "https://offline.test")!, organizationID: "test", benefitID: "test")
        let store = MemoryLicenseStore(
            record: LicenseRecord(
                key: "TEST", activationID: "activation", displayKey: "TEST",
                lastValidatedAt: Date().addingTimeInterval(-LicenseManager.offlineGracePeriod + 1)))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LicenseResponseProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let manager = LicenseManager(
            configuration: configuration, store: store,
            client: PolarLicenseClient(configuration: configuration, session: session),
            allowsDevelopmentPreview: false)
        defer { manager.stop() }
        XCTAssertTrue(manager.hasProAccess)
        let expired = expectation(description: "Running app publishes expired access")
        let observer = manager.$state.filter { $0 == .failed }.prefix(1).sink { _ in
            expired.fulfill()
        }
        defer { observer.cancel() }
        manager.start()
        await fulfillment(of: [expired], timeout: 4)
        XCTAssertFalse(manager.hasProAccess)
        XCTAssertFalse(manager.entitlement.canUse(.macAction))
        XCTAssertTrue(manager.entitlement.canUse(.sendKey))
    }

    @MainActor
    func testCancelledValidationDoesNotApplyResults() async {
        let configuration = PolarConfiguration(
            apiURL: URL(string: "https://offline.test")!, organizationID: "test", benefitID: "test")
        let store = MemoryLicenseStore(
            record: LicenseRecord(
                key: "TEST", activationID: "activation", displayKey: "TEST", lastValidatedAt: Date()
            ))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LicenseResponseProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let manager = LicenseManager(
            configuration: configuration, store: store,
            client: PolarLicenseClient(configuration: configuration, session: session),
            allowsDevelopmentPreview: false)
        manager.start()
        manager.stop()
        let stoppedState = manager.state
        let original = store.record
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(manager.state, stoppedState)
        XCTAssertEqual(store.record?.lastValidatedAt, original?.lastValidatedAt)
        XCTAssertNil(manager.message)

        let cancelledConfiguration = PolarConfiguration(
            apiURL: URL(string: "https://cancelled.test")!, organizationID: "test",
            benefitID: "test")
        let client = PolarLicenseClient(configuration: cancelledConfiguration, session: session)
        do {
            _ = try await client.validate(record: store.record!)
            XCTFail("Cancelled transport must throw cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Cancellation became \(error)")
        }
    }

    @MainActor
    func testRejectedLicenseStaysLockedAfterOfflineRestart() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        for failSave in [false, true] {
            let store = MemoryLicenseStore(
                record: LicenseRecord(
                    key: "TEST-KEY", activationID: "activation", displayKey: "****-KEY",
                    lastValidatedAt: now))
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration.protocolClasses = [LicenseResponseProtocol.self]
            let session = URLSession(configuration: sessionConfiguration)
            defer { session.invalidateAndCancel() }

            func manager(host: String) -> LicenseManager {
                let configuration = PolarConfiguration(
                    apiURL: URL(string: "https://\(host)")!,
                    organizationID: "test-org", benefitID: "test-benefit")
                return LicenseManager(
                    configuration: configuration, store: store,
                    client: PolarLicenseClient(configuration: configuration, session: session),
                    now: { now }, allowsDevelopmentPreview: false)
            }
            func validate(_ manager: LicenseManager) async {
                let finished = expectation(description: "License validation completes")
                let observer = manager.$state.dropFirst().filter {
                    $0 != .validating
                }.prefix(1).sink { _ in finished.fulfill() }
                manager.start()
                await fulfillment(of: [finished], timeout: 2)
                observer.cancel()
            }

            let offline = manager(host: "offline.test")
            await validate(offline)
            XCTAssertTrue(offline.hasProAccess)
            XCTAssertEqual(offline.state, .offlinePro)

            store.failSave = failSave
            let rejected = manager(host: "rejected.test")
            await validate(rejected)
            XCTAssertFalse(rejected.hasProAccess)
            XCTAssertEqual(rejected.state, .invalid)
            XCTAssertNil(store.record?.lastValidatedAt)

            let restarted = manager(host: "offline.test")
            XCTAssertFalse(restarted.hasProAccess)
            if store.record != nil { await validate(restarted) }
            XCTAssertFalse(restarted.hasProAccess)
        }
    }
}

private final class MemoryLicenseStore: LicenseStore {
    var record: LicenseRecord?
    var failSave = false

    init(record: LicenseRecord) { self.record = record }
    func load() throws -> LicenseRecord? { record }
    func save(_ record: LicenseRecord) throws {
        if failSave { throw LicenseStoreError.unableToSave }
        self.record = record
    }
    func remove() throws { record = nil }
}

private final class LicenseResponseProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.host == "cancelled.test" {
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        if request.url?.host == "rejected.test" {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }
    override func stopLoading() {}
}
