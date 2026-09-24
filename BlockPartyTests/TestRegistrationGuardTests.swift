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
//  Registration is checked in two independent ways, because a file can be
//  *half*-registered: added to the project (a PBXFileReference and a group
//  `children` entry — what "Add Files…" produces even with "Add to targets"
//  left unchecked) without ever being added to a target's Sources build phase.
//  That file satisfies `path = <dir>/<file>;`, compiles no differently to the
//  eye, and still never runs. So this guard also requires the `<file> in
//  Sources` comment token to appear at least twice — once on the PBXBuildFile
//  definition line, once in the PBXSourcesBuildPhase `files` list — which is
//  only true once the file is actually wired into a target's build phase.
//
//  Assumes both test directories are flat (no subfolders). `contentsOfDirectory`
//  does not recurse and the path/Sources regexes below do not match a `/` inside
//  the filename group, so a nested `BlockPartyTests/Foo/Bar.swift` would be
//  invisible to this guard in both directions. Reorganizing either target into
//  subdirectories means rewriting this guard to walk recursively first.
//
//  If this fails, register the file (and its target membership) with the
//  `xcodeproj` Ruby gem or the Xcode GUI. Do not hand-edit project.pbxproj.
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

    /// Counts non-overlapping occurrences of `substring` in `text`.
    private static func occurrenceCount(of substring: String, in text: String) -> Int {
        guard !substring.isEmpty else { return 0 }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: substring, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<text.endIndex
        }
        return count
    }

    /// True only once `file` has both a PBXBuildFile definition and a
    /// PBXSourcesBuildPhase files-list entry — i.e. it is actually compiled
    /// into a target, not merely referenced by the project.
    private static func isInSourcesBuildPhase(_ file: String, pbxproj: String) -> Bool {
        occurrenceCount(of: "\(file) in Sources", in: pbxproj) >= 2
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
                let hasFileReference = pbxproj.contains("path = \(directory)/\(file);")
                XCTAssertTrue(
                    hasFileReference,
                    """
                    \(directory)/\(file) exists on disk but is NOT registered in \
                    project.pbxproj, so it never runs. Register it with the xcodeproj \
                    gem or the Xcode GUI (4 entries), then confirm the executed test \
                    count rose.
                    """
                )
                guard hasFileReference else { continue }
                XCTAssertTrue(
                    Self.isInSourcesBuildPhase(file, pbxproj: pbxproj),
                    """
                    \(directory)/\(file) exists on disk and has a file reference, but is \
                    not in the target's Sources build phase — it will never compile or \
                    run. Re-add it to the target with the xcodeproj gem or by checking \
                    "Add to targets" in Xcode.
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
            let directory = String(pbxproj[dirRange])
            let file = String(pbxproj[fileRange])
            let relative = "\(directory)/\(file)"
            guard seen.insert(relative).inserted else { continue }

            let existsOnDisk = FileManager.default.fileExists(
                atPath: Self.repoRoot.appendingPathComponent(relative).path
            )
            XCTAssertTrue(
                existsOnDisk,
                """
                \(relative) is registered in project.pbxproj but is missing on disk. \
                Remove its 4 entries with the xcodeproj gem or the Xcode GUI.
                """
            )
            guard existsOnDisk else { continue }
            XCTAssertTrue(
                Self.isInSourcesBuildPhase(file, pbxproj: pbxproj),
                """
                \(relative) exists on disk and has a file reference, but is not in the \
                target's Sources build phase — it will never compile or run. Re-add it \
                to the target with the xcodeproj gem or by checking "Add to targets" in \
                Xcode.
                """
            )
        }

        XCTAssertFalse(seen.isEmpty, "found no registered test sources — the pbxproj format changed")
    }
}
