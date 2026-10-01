import XCTest

final class FinderExtensionControllerTests: XCTestCase {
    func testParsesEnabledElection() {
        let output = "+\tcom.dozecat.RightKit.FinderExtension(1.0.0)\n"

        XCTAssertEqual(FinderExtensionController.parseState(from: output), .enabled)
    }

    func testParsesDisabledElection() {
        let output = "-\tcom.dozecat.RightKit.FinderExtension(1.0.0)\n"

        XCTAssertEqual(FinderExtensionController.parseState(from: output), .disabled)
    }

    func testParsesMatchWithLeadingWhitespace() {
        let output = "  +\t\tcom.dozecat.RightKit.FinderExtension(1.0.0)\t/path/RightKit.appex\n"

        XCTAssertEqual(FinderExtensionController.parseState(from: output), .enabled)
    }

    func testIgnoresOtherExtensions() {
        let output = """
        +\tcn.better365.iRightMouse.Extension(1.0)
        -\tcom.dozecat.RightKit.FinderExtension(1.0.0)
        """

        XCTAssertEqual(FinderExtensionController.parseState(from: output), .disabled)
    }

    /// The real failure output seen when the calling process is not allowed to
    /// query PlugInKit; the UI must fall back to System Settings rather than
    /// showing a wrong switch position.
    func testUnknownWhenQueryIsNotAuthorized() {
        let output = "match: unauthorized discovery flag (PKDiscoverAll)\n"

        XCTAssertEqual(FinderExtensionController.parseState(from: output), .unknown)
    }

    func testUnknownWhenNoMatch() {
        XCTAssertEqual(FinderExtensionController.parseState(from: ""), .unknown)
        XCTAssertEqual(
            FinderExtensionController.parseState(from: "+\tcom.apple.Safari(1.0)\n"),
            .unknown
        )
    }

    func testUnknownWhenElectionMarkerIsMissing() {
        let output = "\t\tcom.dozecat.RightKit.FinderExtension(1.0.0)\n"

        XCTAssertEqual(FinderExtensionController.parseState(from: output), .unknown)
    }
}
