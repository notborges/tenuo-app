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

    func testOfflineAccessExpiresAfterGracePeriod() {
        let now = Date(timeIntervalSince1970: 1_000)
        let record = LicenseRecord(
            key: "TEST-KEY",
            activationID: UUID().uuidString,
            displayKey: "****-KEY",
            lastValidatedAt: now)

        XCTAssertTrue(record.hasOfflineAccess(now: now.addingTimeInterval(10), gracePeriod: 20))
        XCTAssertFalse(record.hasOfflineAccess(now: now.addingTimeInterval(21), gracePeriod: 20))
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
