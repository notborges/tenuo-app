import XCTest

final class CapsLockRemapperTests: XCTestCase {
    func testNoHIDMappingsAreAnEmptyList() {
        XCTAssertEqual(HIDMappingParser.parse(Data("(null)\n".utf8))?.count, 0)
    }

    func testInvalidHIDMappingOutputIsRejected() {
        XCTAssertNil(HIDMappingParser.parse(Data("not a property list".utf8)))
    }
}
