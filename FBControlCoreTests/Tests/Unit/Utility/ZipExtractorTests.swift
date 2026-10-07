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
struct ZipExtractorTests {

  private let root = TemporaryDirectory(logger: ControlCoreGlobalConfiguration.defaultLogger).temporaryDirectory()
  private let fileManager = FileManager.default
  private let logger = ControlCoreGlobalConfiguration.defaultLogger

  private func run(_ launchPath: String, _ arguments: [String]) throws {
    try ArchiveFixtures.run(launchPath, arguments, in: root)
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
    let app = try ArchiveFixtures.makeApp(in: root)
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app, archive])

    try await expectParityWithBSDTar(archive)
  }

  @Test
  func extract_KeepsADotUnderscoreFileThatIsNotAppleDouble() throws {
    let app = try ArchiveFixtures.makeApp(in: root)
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
    let app = try ArchiveFixtures.makeApp(in: root)
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
    _ = try ArchiveFixtures.makeApp(in: root)
    let archive = root.appendingPathComponent("a.ipa").path
    try run("/usr/bin/zip", ["-qry", "-P", "password", archive, "A.app/Info.plist"])
    let extracted = root.appendingPathComponent("inprocess").path
    try fileManager.createDirectory(atPath: extracted, withIntermediateDirectories: true)

    #expect(throws: ArchiveError.unsupported("A.app/Info.plist is encrypted")) {
      try ZipExtractor.extract(archiveAtPath: archive, to: extracted)
    }
  }

  // MARK: - InProcessZipExtractor

  @Test
  func inProcessZipExtractor_ExtractsAZipItself() async throws {
    let app = try ArchiveFixtures.makeApp(in: root)
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
    _ = try ArchiveFixtures.makeApp(in: root)
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
    _ = try ArchiveFixtures.makeApp(in: root)
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
