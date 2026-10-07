/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing
import os

@Suite
struct ZipExtractorTests {

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let fileManager = FileManager.default
  private let logger = ControlCoreGlobalConfiguration.defaultLogger

  private func run(_ launchPath: String, _ arguments: [String]) throws {
    try ArchiveFixtures.run(launchPath, arguments, in: root)
  }

  /// An app with modes, symlinks, nesting, extended attributes and contents that deflate.
  private func makeApp() throws -> String {
    let app = root.appendingPathComponent("A.app")
    try fileManager.createDirectory(at: app.appendingPathComponent("Real/Deeper"), withIntermediateDirectories: true)
    try fileManager.createDirectory(at: app.appendingPathComponent("Private"), withIntermediateDirectories: true)
    try Data("binary".utf8).write(to: app.appendingPathComponent("A"))
    try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.appendingPathComponent("A").path)
    try Data("<plist/>".utf8).write(to: app.appendingPathComponent("Info.plist"))
    try Data(String(repeating: "compressible ", count: 200_000).utf8).write(to: app.appendingPathComponent("Real/Deeper/big.txt"))
    try Data().write(to: app.appendingPathComponent("Real/empty"))
    try Data("secret".utf8).write(to: app.appendingPathComponent("Private/key"))
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: app.appendingPathComponent("Private/key").path)
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: app.appendingPathComponent("Private").path)
    try fileManager.createSymbolicLink(atPath: app.appendingPathComponent("link.plist").path, withDestinationPath: "Info.plist")
    try fileManager.createSymbolicLink(atPath: app.appendingPathComponent("LinkDir").path, withDestinationPath: "Real")
    try run("/usr/bin/xattr", ["-w", "com.example.tag", "value", app.appendingPathComponent("Info.plist").path])
    return app.path
  }

  private func expectParityWithBSDTar(_ archive: String) async throws {
    let expected = root.appendingPathComponent("bsdtar").path
    try fileManager.createDirectory(atPath: expected, withIntermediateDirectories: true)
    try await BSDTarExtractor().extract(.filePath(archive), to: expected, options: ArchiveExtractOptions(), logger: logger)
    let extracted = root.appendingPathComponent("inprocess").path
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)

    let summary = try ZipExtractor.extract(archiveAtPath: archive, to: extracted)

    let expectedTree = try ArchiveFixtures.bsdtarTree(at: expected, keepHardLinks: false)
    let extractedTree = try ArchiveFixtures.tree(at: extracted, keepHardLinks: false)
    #expect(ArchiveFixtures.differences(expectedTree, extractedTree) == "")
    #expect(summary.files == expectedTree.values.filter { $0.hasPrefix("file") }.count)
  }

  @Test
  func extract_OfADittoZip_MatchesBSDTar() async throws {
    let app = try makeApp()
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app, archive])

    try await expectParityWithBSDTar(archive)
  }

  @Test
  func extract_KeepsADotUnderscoreFileThatIsNotAppleDouble() throws {
    let app = try makeApp()
    try Data("not metadata".utf8).write(to: URL(fileURLWithPath: "\(app)/._Info.plist"))
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/zip", ["-qry", archive, "A.app"])
    let extracted = root.appendingPathComponent("inprocess").path
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)

    try ZipExtractor.extract(archiveAtPath: archive, to: extracted)

    #expect(try Data(contentsOf: URL(fileURLWithPath: "\(extracted)/A.app/._Info.plist")) == Data("not metadata".utf8))
  }

  @Test
  func extract_WithOverrideModificationTime_StampsTheCurrentTime() throws {
    let app = try makeApp()
    try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: "\(app)/Info.plist")
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app, archive])
    let extracted = root.appendingPathComponent("inprocess").path
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)

    try ZipExtractor.extract(archiveAtPath: archive, to: extracted, overrideModificationTime: true)

    let modified = try #require(fileManager.attributesOfItem(atPath: "\(extracted)/A.app/Info.plist")[.modificationDate] as? Date)
    #expect(Date().timeIntervalSince(modified) < 60)
  }

  @Test
  func extract_RejectsAnEntryWhoseContentsDoNotMatchItsCRC() throws {
    let contents = Data(String(repeating: "0123456789", count: 100).utf8)
    try fileManager.createDirectory(at: root.appendingPathComponent("A.app"), withIntermediateDirectories: true)
    try contents.write(to: root.appendingPathComponent("A.app/file"))
    let archive = root.appendingPathComponent("a.ipa")
    try run("/usr/bin/zip", ["-qry0", archive.path, "A.app"])
    var bytes = try Data(contentsOf: archive)
    let range = try #require(bytes.range(of: contents))
    bytes[range.lowerBound] ^= 0xFF
    try bytes.write(to: archive)
    let extracted = root.appendingPathComponent("inprocess").path
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)

    #expect(throws: ArchiveError.corrupt("A.app/file does not match its size or CRC")) {
      try ZipExtractor.extract(archiveAtPath: archive.path, to: extracted)
    }
  }

  @Test
  func extract_RejectsAPathOutsideTheExtraction() throws {
    try fileManager.createDirectory(at: root.appendingPathComponent("aa"), withIntermediateDirectories: true)
    try Data("escaped".utf8).write(to: root.appendingPathComponent("aa/escape"))
    let archive = root.appendingPathComponent("a.zip")
    try run("/usr/bin/zip", ["-qr0", "-D", archive.path, "aa/escape"])
    // The same length, so every header still describes the archive.
    let bytes = try Data(contentsOf: archive)
    try Data(bytes.split(separator: Data("aa/escape".utf8), omittingEmptySubsequences: false).joined(separator: Data("../escape".utf8))).write(to: archive)
    let extracted = root.appendingPathComponent("inprocess").path
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)

    #expect(throws: ArchiveError.unsafePath("../escape")) {
      try ZipExtractor.extract(archiveAtPath: archive.path, to: extracted)
    }
    #expect(!fileManager.fileExists(atPath: root.appendingPathComponent("escape").path))
  }

  @Test
  func extract_OfAnEncryptedZip_IsUnsupported() throws {
    _ = try makeApp()
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/zip", ["-qry", "-P", "password", archive, "A.app/Info.plist"])
    let extracted = root.appendingPathComponent("inprocess").path
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)

    #expect(throws: ArchiveError.unsupported("A.app/Info.plist is encrypted")) {
      try ZipExtractor.extract(archiveAtPath: archive, to: extracted)
    }
  }

  // MARK: - ZipStreamExtractor

  /// Extracts through a pipe, as a zip arrives, then repairs from the complete file.
  @discardableResult
  private func extractAsStream(_ archive: String, to extracted: String, repair: Bool = true) throws -> ArchiveExtractionSummary {
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)
    var fds: [Int32] = [0, 0]
    #expect(pipe(&fds) == 0)
    let (readEnd, writeEnd) = (fds[0], fds[1])
    _ = fcntl(writeEnd, F_SETNOSIGPIPE, 1)
    let contents = try Data(contentsOf: URL(fileURLWithPath: archive))
    let wroteAll = OSAllocatedUnfairLock(initialState: false)
    let finished = DispatchSemaphore(value: 0)
    // After the read end closes, so that a reader that stops early fails this rather than hanging it.
    defer {
      finished.wait()
      #expect(wroteAll.withLock { $0 }, "the extractor should read the whole zip, even when it fails")
    }
    defer { close(readEnd) }
    let writer = Thread {
      defer {
        close(writeEnd)
        finished.signal()
      }
      contents.withUnsafeBytes { buffer in
        var offset = 0
        while offset < buffer.count {
          let written = write(writeEnd, buffer.baseAddress.map { $0 + offset }, min(buffer.count - offset, 7_000))
          guard written > 0 else {
            return
          }
          offset += written
        }
        wroteAll.withLock { $0 = true }
      }
    }
    writer.start()
    let summary = try ZipStreamExtractor.extract(from: FileDescriptorSource(readEnd), to: extracted)
    if repair {
      try ZipCentralDirectory(archiveAtPath: archive).repair(extractedAt: extracted)
    }
    return summary
  }

  @Test
  func extractStream_CountsTheFilesItWrote() throws {
    _ = try makeApp()
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/zip", ["-qry0", archive, "A.app"])

    let summary = try extractAsStream(archive, to: root.appendingPathComponent("stream").path)

    // Symlinks included: they arrive as files holding their target.
    #expect(summary.files == 7)
  }

  @Test
  func extractStream_OfADittoZip_SkipsAppleDoubleEntriesAsTheyArrive() throws {
    let app = try makeApp()
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app, archive])
    let extracted = root.appendingPathComponent("stream").path

    try extractAsStream(archive, to: extracted, repair: false)

    #expect(try fileManager.subpathsOfDirectory(atPath: extracted).filter { ($0 as NSString).lastPathComponent.hasPrefix("._") } == [])
  }

  @Test
  func extractStream_KeepsADotUnderscoreFileThatIsNotAppleDouble() throws {
    let app = try makeApp()
    try Data("not metadata".utf8).write(to: URL(fileURLWithPath: "\(app)/._Info.plist"))
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/zip", ["-qry", archive, "A.app"])
    let extracted = root.appendingPathComponent("stream").path

    try extractAsStream(archive, to: extracted)

    #expect(try Data(contentsOf: URL(fileURLWithPath: "\(extracted)/A.app/._Info.plist")) == Data("not metadata".utf8))
  }

  @Test
  func extractStream_RejectsAnEntryWhoseContentsDoNotMatchItsCRC() throws {
    let contents = Data(String(repeating: "0123456789", count: 100).utf8)
    try fileManager.createDirectory(at: root.appendingPathComponent("A.app"), withIntermediateDirectories: true)
    try contents.write(to: root.appendingPathComponent("A.app/file"))
    // More than a pipe holds after the corrupt entry, so that the writer only finishes if the extractor reads on.
    try Data(repeating: 1, count: 1 << 20).write(to: root.appendingPathComponent("A.app/after"))
    let archive = root.appendingPathComponent("a.ipa")
    try run("/usr/bin/zip", ["-q0", archive.path, "A.app/file", "A.app/after"])
    var bytes = try Data(contentsOf: archive)
    let range = try #require(bytes.range(of: contents))
    bytes[range.lowerBound] ^= 0xFF
    try bytes.write(to: archive)

    #expect(throws: ArchiveError.corrupt("A.app/file does not match its size or CRC")) {
      try extractAsStream(archive.path, to: root.appendingPathComponent("stream").path)
    }
  }

  @Test
  func extractStream_OfAStoredEntryWithItsSizeAfterIt_IsUnsupported() throws {
    _ = try makeApp()
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/bin/sh", ["-c", "/usr/bin/zip -qry0 - A.app/Info.plist | /bin/cat > \"$0\"", archive])

    #expect(throws: ArchiveError.unsupported("A.app/Info.plist is stored with its size after it")) {
      try extractAsStream(archive, to: root.appendingPathComponent("stream").path)
    }
  }

  // MARK: - InProcessZipExtractor

  @Test
  func inProcessZipExtractor_ExtractsAZipItself() async throws {
    let app = try makeApp()
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app, archive])
    let extracted = root.appendingPathComponent("inprocess").path
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)
    let fallback = RecordingExtractor()

    try await InProcessZipExtractor(fallback: fallback).extract(.filePath(archive), to: extracted, options: ArchiveExtractOptions(), logger: logger)

    #expect(!fallback.wasReached)
    #expect(fileManager.fileExists(atPath: "\(extracted)/A.app/Info.plist"))
  }

  @Test
  func inProcessZipExtractor_LeavesAnythingButAZipToItsFallback() async throws {
    _ = try makeApp()
    let archive = root.appendingPathComponent("a.tar").path
    try run("/usr/bin/tar", ["-cf", archive, "A.app"])
    let extracted = root.appendingPathComponent("inprocess").path
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)
    let fallback = RecordingExtractor()

    try await InProcessZipExtractor(fallback: fallback).extract(.filePath(archive), to: extracted, options: ArchiveExtractOptions(), logger: logger)

    #expect(fallback.extractions.map(\.path) == [archive])
  }

  @Test
  func inProcessZipExtractor_FallsBackToAnEmptyDirectoryWhenItCannotExtract() async throws {
    _ = try makeApp()
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/zip", ["-qry", archive, "A.app/A"])
    try run("/usr/bin/zip", ["-qry", "-P", "password", archive, "A.app/Info.plist"])
    let extracted = root.appendingPathComponent("inprocess").path
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)
    let fallback = RecordingExtractor()

    try await InProcessZipExtractor(fallback: fallback).extract(.filePath(archive), to: extracted, options: ArchiveExtractOptions(), logger: logger)

    let extractions = fallback.extractions
    #expect(extractions.map(\.path) == [archive])
    #expect(extractions.first?.existing == [])
  }
}
