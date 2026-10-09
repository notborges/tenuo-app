import XCTest

final class ModifierPressesTests: XCTestCase {
    func testOutputModifiersArePressedAroundTheKey() {
        var presses = ModifierPresses()
        let r = KeyCatalog.code(for: "r")!

        let downs = presses.press(output: r, flags: [.command, .option], visible: [])
        XCTAssertEqual(downs.map(\.keyCode), [KeyCode.leftOption, KeyCode.leftCommand])
        XCTAssertTrue(downs.allSatisfy(\.isKeyDown))
        XCTAssertTrue(downs[1].flags.contains([.option, .command]))
        XCTAssertTrue(presses.isPressing(for: r))
        XCTAssertTrue(presses.press(output: r, flags: [.command, .option], visible: []).isEmpty)

        let ups = presses.release(output: r, visible: [])
        XCTAssertEqual(ups.map(\.keyCode), [KeyCode.leftCommand, KeyCode.leftOption])
        XCTAssertFalse(ups.contains(where: \.isKeyDown))
        XCTAssertTrue(ups.last!.flags.isEmpty)
        XCTAssertFalse(presses.isPressing(for: r))
    }

    func testVisibleModifiersAreNotPressedAgain() {
        var presses = ModifierPresses()
        let downs = presses.press(
            output: KeyCode.leftArrow, flags: [.shift, .command], visible: [.shift])
        XCTAssertEqual(downs.map(\.keyCode), [KeyCode.leftCommand])
        XCTAssertTrue(downs[0].flags.contains(.shift))
        XCTAssertTrue(presses.press(output: KeyCode.h, flags: [.shift], visible: [.shift]).isEmpty)
        XCTAssertFalse(presses.isPressing(for: KeyCode.h))
    }

    func testSharedModifiersReleaseWithTheLastOutput() {
        var presses = ModifierPresses()
        XCTAssertEqual(
            presses.press(output: KeyCode.a, flags: [.command], visible: []).count, 1)
        XCTAssertTrue(presses.press(output: KeyCode.s, flags: [.command], visible: []).isEmpty)
        XCTAssertTrue(presses.release(output: KeyCode.a, visible: []).isEmpty)
        XCTAssertEqual(
            presses.releaseAll(visible: []).map(\.keyCode), [KeyCode.leftCommand])
    }
}
