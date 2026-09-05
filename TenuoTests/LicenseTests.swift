import Foundation
import XCTest

final class LicenseTests: XCTestCase {
    func testEntitlementUnlocksOnlyProActions() {
        let entitlement = LicenseEntitlement()

        XCTAssertTrue(entitlement.canUse(.sendKey))
        XCTAssertFalse(entitlement.canUse(.toggleLayer))
        XCTAssertFalse(entitlement.canUse(.oneShotLayer))

        entitlement.setProAccess(true)

        XCTAssertTrue(entitlement.canUse(.toggleLayer))
        XCTAssertTrue(entitlement.canUse(.oneShotLayer))
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

    func testLicenseRecordRoundTrips() throws {
        let record = LicenseRecord(
            key: "TEST-KEY",
            activationID: "activation",
            displayKey: "****-KEY",
            lastValidatedAt: Date(timeIntervalSince1970: 1_000))

        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(LicenseRecord.self, from: data), record)
    }
}
