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
struct ZipStreamExtractorTests {

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let fileManager = FileManager.default

  private func run(_ launchPath: String, _ arguments: [String]) throws {
    try ArchiveFixtures.run(launchPath, arguments, in: root)
  }

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
    _ = try ArchiveFixtures.makeApp(in: root)
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/zip", ["-qry0", archive, "A.app"])

    let summary = try extractAsStream(archive, to: root.appendingPathComponent("stream").path)

    // Symlinks included: they arrive as files holding their target.
    #expect(summary.files == 7)
  }

  @Test
  func extractStream_OfADittoZip_SkipsAppleDoubleEntriesAsTheyArrive() throws {
    let app = try ArchiveFixtures.makeApp(in: root)
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app, archive])
    let extracted = root.appendingPathComponent("stream").path

    try extractAsStream(archive, to: extracted, repair: false)

    #expect(try fileManager.subpathsOfDirectory(atPath: extracted).filter { ($0 as NSString).lastPathComponent.hasPrefix("._") } == [])
  }

  @Test
  func extractStream_KeepsADotUnderscoreFileThatIsNotAppleDouble() throws {
    let app = try ArchiveFixtures.makeApp(in: root)
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
    _ = try ArchiveFixtures.makeApp(in: root)
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/bin/sh", ["-c", "/usr/bin/zip -qry0 - A.app/Info.plist | /bin/cat > \"$0\"", archive])

    #expect(throws: ArchiveError.unsupported("A.app/Info.plist is stored with its size after it")) {
      try extractAsStream(archive, to: root.appendingPathComponent("stream").path)
    }
  }
}
