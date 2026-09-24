import XCTest

final class ScriptConfigTests: XCTestCase {
    func testDecodesNameAndMultiple() throws {
        let json = #"{"name":"Demo","multiple":true}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(ScriptConfig.self, from: json)

        XCTAssertEqual(config.name, "Demo")
        XCTAssertEqual(config.multiple, true)
    }

    func testUniqueURLUsesDirectory() {
        let directory = URL(fileURLWithPath: "/tmp")
        let url = NewFileService.uniqueURL(for: "untitled.txt", in: directory)

        XCTAssertEqual(url.path, "/tmp/untitled.txt")
    }
}
