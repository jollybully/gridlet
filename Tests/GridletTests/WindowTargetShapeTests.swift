import ApplicationServices
import XCTest
@testable import Gridlet

/// Shape checks for the windows Gridlet will try to place. A role or subrole change in
/// an app is what makes Gridlet report "no window available" for a perfectly movable
/// window, so the accepted shapes are pinned here rather than left implicit.
final class WindowTargetShapeTests: XCTestCase {
    func testStandardWindowRoleAndSubroleAccepted() {
        XCTAssertTrue(WindowTargetResolver.isAcceptableRole(kAXWindowRole as String))
        XCTAssertTrue(
            WindowTargetResolver.isAcceptableSubrole(
                kAXStandardWindowSubrole as String,
                role: kAXWindowRole as String
            )
        )
    }

    func testWindowWithoutSubroleAccepted() {
        XCTAssertTrue(
            WindowTargetResolver.isAcceptableSubrole("", role: kAXWindowRole as String)
        )
    }

    /// After Effects 2026 publishes its document window as AXLayoutArea/AXFloatingWindow.
    func testAfterEffectsLayoutAreaWindowAccepted() {
        XCTAssertTrue(WindowTargetResolver.isAcceptableRole("AXLayoutArea"))
        XCTAssertTrue(
            WindowTargetResolver.isAcceptableSubrole(
                "AXFloatingWindow",
                role: "AXLayoutArea"
            )
        )
    }

    /// Warp publishes its main terminal window as AXWindow/AXSystemDialog. Modal
    /// dialogs are rejected by the modal check before the subrole is consulted, so
    /// accepting this subrole cannot make Gridlet grab an alert.
    func testSystemDialogSubroleAccepted() {
        XCTAssertTrue(
            WindowTargetResolver.isAcceptableSubrole("AXSystemDialog", role: kAXWindowRole as String)
        )
    }

    func testLayoutAreaWithStandardSubroleAccepted() {
        XCTAssertTrue(
            WindowTargetResolver.isAcceptableSubrole(
                kAXStandardWindowSubrole as String,
                role: "AXLayoutArea"
            )
        )
    }

    /// A floating palette in a normal app stays out of reach: the relaxed role is what
    /// makes AXFloatingWindow acceptable, not the subrole on its own.
    func testFloatingSubroleOnAPlainWindowRejected() {
        XCTAssertFalse(
            WindowTargetResolver.isAcceptableSubrole(
                "AXFloatingWindow",
                role: kAXWindowRole as String
            )
        )
    }

    func testOtherSubrolesRejected() {
        for subrole in ["AXFullScreenWindow", "AXDialog", "AXUnknown"] {
            XCTAssertFalse(
                WindowTargetResolver.isAcceptableSubrole(subrole, role: kAXWindowRole as String),
                "subrole '\(subrole)' must not be treated as a placeable window"
            )
        }
    }

    func testNonWindowRolesRejected() {
        for role in ["AXSheet", "AXDrawer", "AXSystemWide", "AXDesktop", "AXMenuBar", "AXGroup", "AXButton"] {
            XCTAssertFalse(
                WindowTargetResolver.isAcceptableRole(role),
                "role '\(role)' must not be treated as a placeable window"
            )
        }
    }
}
