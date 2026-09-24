//
//  TestRegistrationGuardTests.swift
//  Block Party — the gate that stops a test file from silently never running.
//
//  The app target is a file-system-synchronized group, so a new Swift file under
//  BlockParty/ joins the build on its own. The test targets are NOT: they carry an
//  explicit source list, and a new file under BlockPartyTests/ is invisible to
//  `xcodebuild test` until four project.pbxproj entries exist. The symptom is the
//  worst kind — the suite passes, the executed count never rises, and the new
//  tests never ran.
//
//  This is a source-level gate, like TypographyScalingGuardTests. It reads the
//  pbxproj from the repo root resolved off #filePath, which is baked at compile
//  time and therefore points at this checkout.
//
//  If this fails, register the file with the `xcodeproj` Ruby gem or the Xcode
//  GUI. Do not hand-edit project.pbxproj.
//

import XCTest

final class TestRegistrationGuardTests: XCTestCase {

    /// Directories whose Swift files must each appear in project.pbxproj.
    private static let testDirectories = ["BlockPartyTests", "BlockPartyUITests"]

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // BlockPartyTests
            .deletingLastPathComponent()   // repo root
    }

    private static func projectFile() throws -> String {
        let url = repoRoot.appendingPathComponent("BlockParty.xcodeproj/project.pbxproj")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testEveryTestFileOnDiskIsRegistered() throws {
        let pbxproj = try Self.projectFile()
        for directory in Self.testDirectories {
            let dir = Self.repoRoot.appendingPathComponent(directory)
            let files = try FileManager.default
                .contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasSuffix(".swift") }
                .sorted()
            XCTAssertFalse(files.isEmpty, "\(directory) has no Swift files — did the path change?")
            for file in files {
                XCTAssertTrue(
                    pbxproj.contains("path = \(directory)/\(file);"),
                    """
                    \(directory)/\(file) exists on disk but is NOT registered in \
                    project.pbxproj, so it never runs. Register it with the xcodeproj \
                    gem or the Xcode GUI (4 entries), then confirm the executed test \
                    count rose.
                    """
                )
            }
        }
    }

    func testEveryRegisteredTestFileExistsOnDisk() throws {
        let pbxproj = try Self.projectFile()
        let pattern = "path = (\(Self.testDirectories.joined(separator: "|")))/([A-Za-z0-9_+.-]+\\.swift);"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(pbxproj.startIndex..., in: pbxproj)
        var seen: Set<String> = []

        for match in regex.matches(in: pbxproj, range: range) {
            guard let dirRange = Range(match.range(at: 1), in: pbxproj),
                  let fileRange = Range(match.range(at: 2), in: pbxproj) else { continue }
            let relative = "\(pbxproj[dirRange])/\(pbxproj[fileRange])"
            guard seen.insert(relative).inserted else { continue }
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: Self.repoRoot.appendingPathComponent(relative).path),
                """
                \(relative) is registered in project.pbxproj but is missing on disk. \
                Remove its 4 entries with the xcodeproj gem or the Xcode GUI.
                """
            )
        }

        XCTAssertFalse(seen.isEmpty, "found no registered test sources — the pbxproj format changed")
    }
}
