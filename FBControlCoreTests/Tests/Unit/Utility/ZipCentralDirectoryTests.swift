/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

@Suite
struct ZipCentralDirectoryTests {

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let fileManager = FileManager.default

  private func run(_ launchPath: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    process.currentDirectoryURL = root
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0, "\(launchPath) \(arguments)")
  }

  /// An app with the things a zip records only in its central directory.
  private func makeApp() throws -> String {
    let app = root.appendingPathComponent("A.app")
    try fileManager.createDirectory(at: app.appendingPathComponent("Real"), withIntermediateDirectories: true)
    try Data("binary".utf8).write(to: app.appendingPathComponent("A"))
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.appendingPathComponent("A").path)
    try Data("<plist/>".utf8).write(to: app.appendingPathComponent("Info.plist"))
    try fileManager.createSymbolicLink(atPath: app.appendingPathComponent("link.plist").path, withDestinationPath: "Info.plist")
    try fileManager.createSymbolicLink(atPath: app.appendingPathComponent("LinkDir").path, withDestinationPath: "Real")
    return app.path
  }

  private func extractAsStream(_ archive: String, to directory: String) throws {
    try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
    // Through a pipe: bsdtar seeks a file on its stdin, reading the central directory after all.
    try run("/bin/sh", ["-c", "/bin/cat \"$0\" | /usr/bin/bsdtar -xp --no-mac-metadata -C \"$1\" -f -", archive, directory])
  }

  private func permissions(_ path: String) throws -> Int {
    try #require(fileManager.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
  }

  @Test
  func repair_RestoresWhatAStreamedExtractionLoses() throws {
    let app = try makeApp()
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app, archive])
    let extracted = root.appendingPathComponent("stream").path
    try extractAsStream(archive, to: extracted)
    #expect(try permissions("\(extracted)/A.app/A") == 0o664)
    #expect(try permissions("\(extracted)/A.app/Real") == 0o775)

    try ZipCentralDirectory(archiveAtPath: archive).repair(extractedAt: extracted)

    #expect(try permissions("\(extracted)/A.app/A") == 0o755)
    #expect(try permissions("\(extracted)/A.app/Real") == 0o755)
    #expect(try fileManager.destinationOfSymbolicLink(atPath: "\(extracted)/A.app/link.plist") == "Info.plist")
    #expect(try fileManager.destinationOfSymbolicLink(atPath: "\(extracted)/A.app/LinkDir") == "Real")
  }

  @Test
  func repair_RemovesAppleDoubleEntries() throws {
    let app = try makeApp()
    try run("/usr/bin/xattr", ["-w", "com.example.tag", "value", "\(app)/Info.plist"])
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app, archive])
    let extracted = root.appendingPathComponent("stream").path
    try extractAsStream(archive, to: extracted)
    #expect(fileManager.fileExists(atPath: "\(extracted)/A.app/._Info.plist"))

    try ZipCentralDirectory(archiveAtPath: archive).repair(extractedAt: extracted)

    #expect(!fileManager.fileExists(atPath: "\(extracted)/A.app/._Info.plist"))
    #expect(fileManager.fileExists(atPath: "\(extracted)/A.app/Info.plist"))
  }

  @Test
  func repair_KeepsADotUnderscoreFileThatIsNotAppleDouble() throws {
    let app = try makeApp()
    try Data("not metadata".utf8).write(to: URL(fileURLWithPath: "\(app)/._Info.plist"))
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/zip", ["-qry", archive, "A.app"])
    let extracted = root.appendingPathComponent("stream").path
    try extractAsStream(archive, to: extracted)

    try ZipCentralDirectory(archiveAtPath: archive).repair(extractedAt: extracted)

    #expect(fileManager.fileExists(atPath: "\(extracted)/A.app/._Info.plist"))
  }

  @Test
  func init_ReadsAZip64Archive() throws {
    _ = try makeApp()
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/zip", ["-qry", "-fz", archive, "A.app"])

    let entries = try ZipCentralDirectory(archiveAtPath: archive).entries

    #expect(entries.first { $0.path == "A.app/link.plist" }?.mode.map { $0 & S_IFMT } == S_IFLNK)
    #expect(entries.first { $0.path == "A.app/A" }?.mode.map { $0 & 0o7777 } == 0o755)
  }

  @Test
  func init_RejectsAFileThatIsNotAZip() throws {
    let path = root.appendingPathComponent("not.zip").path
    try Data(repeating: 0, count: 100).write(to: URL(fileURLWithPath: path))

    #expect(throws: ArchiveError.corrupt("no end of central directory record")) {
      try ZipCentralDirectory(archiveAtPath: path)
    }
  }

  @Test
  func repair_DoesNotFollowASymlinkOutOfTheExtraction() throws {
    let outside = root.appendingPathComponent("outside")
    try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
    try Data().write(to: outside.appendingPathComponent("file"))
    let extracted = root.appendingPathComponent("stream")
    try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
    try fileManager.createSymbolicLink(atPath: extracted.appendingPathComponent("link").path, withDestinationPath: outside.path)
    let directory = ZipCentralDirectory(entries: [.init(path: "link/file", mode: S_IFREG | 0o777)])

    #expect(throws: ArchiveError.unsafePath("link")) {
      try directory.repair(extractedAt: extracted.path)
    }
    #expect(try permissions(outside.appendingPathComponent("file").path) != 0o777)
  }

  @Test
  func repair_RejectsAPathOutsideTheExtraction() throws {
    let directory = ZipCentralDirectory(entries: [.init(path: "../escape", mode: S_IFLNK | 0o755)])

    #expect(throws: ArchiveError.unsafePath("../escape")) {
      try directory.repair(extractedAt: root.path)
    }
  }
}
