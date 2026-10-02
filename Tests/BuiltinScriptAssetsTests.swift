import AppKit
import XCTest

/// Guards the script packages that ship inside the app. A typo in a
/// `config.json`, or a lost executable bit, would otherwise only show up as a
/// menu item that silently never appears.
final class BuiltinScriptAssetsTests: XCTestCase {
    private var root: URL {
        // Tests/BuiltinScriptAssetsTests.swift -> repository root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var packages: [URL] {
        let directory = root
            .appendingPathComponent("RightKit/Resources/BuiltinScripts", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    func testShipsAtLeastOnePackage() {
        XCTAssertFalse(packages.isEmpty)
    }

    func testEveryPackageHasAnExecutableEntrypoint() {
        for package in packages {
            let script = package.appendingPathComponent("script.sh")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: script.path),
                "\(package.lastPathComponent) is missing script.sh"
            )
            XCTAssertTrue(
                FileManager.default.isExecutableFile(atPath: script.path),
                "\(package.lastPathComponent)/script.sh is not executable"
            )
        }
    }

    func testEveryConfigDecodes() throws {
        for package in packages {
            let config = package.appendingPathComponent("config.json")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: config.path),
                "\(package.lastPathComponent) is missing config.json"
            )
            let data = try Data(contentsOf: config)
            let decoded = try JSONDecoder().decode(ScriptConfig.self, from: data)
            XCTAssertNotNil(
                decoded.name,
                "\(package.lastPathComponent) has no display name"
            )
        }
    }

    /// A script that filters on extensions but names none would never appear.
    func testExtensionFilterIsNeverEmpty() throws {
        for package in packages {
            let data = try Data(contentsOf: package.appendingPathComponent("config.json"))
            let config = try JSONDecoder().decode(ScriptConfig.self, from: data)
            if let extensions = config.extensions {
                XCTAssertFalse(
                    extensions.isEmpty,
                    "\(package.lastPathComponent) filters on an empty extension list"
                )
            }
        }
    }

    /// The whole point of the field is that the icon resolves on a real machine.
    func testApplicationIconsResolve() throws {
        for package in packages {
            let data = try Data(contentsOf: package.appendingPathComponent("config.json"))
            let config = try JSONDecoder().decode(ScriptConfig.self, from: data)
            guard let identifier = config.applicationBundleIdentifier else {
                continue
            }
            XCTAssertNotNil(
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
                "\(package.lastPathComponent) names \(identifier), which resolves to no application"
            )
        }
    }

    /// Built-in names are what the user sees in the Finder submenu.
    func testNamesAreLocalised() throws {
        for package in packages {
            let data = try Data(contentsOf: package.appendingPathComponent("config.json"))
            let config = try JSONDecoder().decode(ScriptConfig.self, from: data)
            let name = try XCTUnwrap(config.name)
            XCTAssertTrue(
                name.contains { $0.unicodeScalars.contains { $0.value > 0x2E7F } },
                "\(package.lastPathComponent) has a non-Chinese display name: \(name)"
            )
        }
    }
}
