import XCTest
@testable import Gridlet

final class DiagnosticsTests: XCTestCase {
    func testParseEmptySelectionFails() {
        if case .failure(let err) = Diagnostics.parseSelection("") {
            XCTAssertTrue(err.description.contains("empty"))
        } else {
            XCTFail("expected failure")
        }
    }

    func testParseNegativeScreenIndexFails() {
        if case .failure = Diagnostics.parseSelection("8,8,0,0,7,7@-1") {
            // ok
        } else {
            XCTFail("expected failure for @-1")
        }
    }

    func testParseInvalidTokenFails() {
        if case .failure = Diagnostics.parseSelection("8,8,0,0,7,x") {
            // ok
        } else {
            XCTFail("expected failure for non-int")
        }
    }

    func testParseValidSelection() {
        switch Diagnostics.parseSelection("8,8,0,0,3,3@0") {
        case .success(let parsed):
            XCTAssertEqual(parsed.rows, 8)
            XCTAssertEqual(parsed.screenIdx, 0)
            XCTAssertEqual(parsed.sel.rowEnd, 3)
        case .failure:
            XCTFail("expected success")
        }
    }
}
