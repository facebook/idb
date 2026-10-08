/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBArtifactStaging
import FBControlCore
import XCTest

final class FBArchiveOperationsTests: XCTestCase {

  private var logger: ControlCoreLoggerDouble!
  private var tempDirectory: String!

  override func setUp() {
    super.setUp()
    logger = ControlCoreLoggerDouble()
    tempDirectory = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent(UUID().uuidString)
    try? FileManager.default.createDirectory(
      atPath: tempDirectory,
      withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(atPath: tempDirectory)
    super.tearDown()
  }

  // MARK: - commandToExtractArchive

  func testCommandToExtractArchive_NoOverrideMTime_NoDebug() {
    let command = FBArchiveOperations.commandToExtractArchive(
      atPath: "/tmp/archive.tar.gz",
      toPath: "/tmp/output",
      overrideModificationTime: false,
      debugLogging: false)

    XCTAssertEqual(command, ["-zxp", "--no-mac-metadata", "-C", "/tmp/output", "-f", "/tmp/archive.tar.gz"])
  }

  func testCommandToExtractArchive_WithOverrideMTime_NoDebug() {
    let command = FBArchiveOperations.commandToExtractArchive(
      atPath: "/tmp/archive.tar.gz",
      toPath: "/tmp/output",
      overrideModificationTime: true,
      debugLogging: false)

    XCTAssertEqual(command[0], "-zxpm", "Flags should include m when overrideMTime is YES")
  }

  func testCommandToExtractArchive_NoOverrideMTime_WithDebug() {
    let command = FBArchiveOperations.commandToExtractArchive(
      atPath: "/tmp/archive.tar.gz",
      toPath: "/tmp/output",
      overrideModificationTime: false,
      debugLogging: true)

    XCTAssertEqual(command[0], "-zxpv", "Flags should include v when debugLogging is YES")
  }

  func testCommandToExtractArchive_WithOverrideMTime_WithDebug() {
    let command = FBArchiveOperations.commandToExtractArchive(
      atPath: "/tmp/archive.tar.gz",
      toPath: "/tmp/output",
      overrideModificationTime: true,
      debugLogging: true)

    XCTAssertEqual(command[0], "-zxpmv", "Flags should include both m and v")
  }

  func testCommandToExtractArchive_PreservesPathsExactly() {
    let archivePath = "/Users/test/Downloads/my archive (1).tar.gz"
    let extractPath = "/Users/test/Documents/output dir"

    let command = FBArchiveOperations.commandToExtractArchive(
      atPath: archivePath,
      toPath: extractPath,
      overrideModificationTime: false,
      debugLogging: false)

    XCTAssertEqual(command[3], extractPath, "Extract path should be preserved exactly")
    XCTAssertEqual(command[5], archivePath, "Archive path should be preserved exactly")
  }

  // MARK: - commandToExtractFromStdIn

  func testCommandToExtractFromStdIn_NoOverrideMTime_NoDebug() {
    let command = FBArchiveOperations.commandToExtractFromStdIn(
      withExtractPath: "/tmp/output",
      overrideModificationTime: false,
      debugLogging: false)

    XCTAssertEqual(command, ["-zxp", "--no-mac-metadata", "-C", "/tmp/output", "-f", "-"])
  }

  func testCommandToExtractFromStdIn_WithOverrideMTime() {
    let command = FBArchiveOperations.commandToExtractFromStdIn(
      withExtractPath: "/tmp/output",
      overrideModificationTime: true,
      debugLogging: false)

    XCTAssertEqual(command[0], "-zxpm", "overrideMTime should include m flag")
    XCTAssertEqual(command.last, "-", "Last element should be stdin marker '-'")
  }

  // MARK: - Round-trip extraction

  private enum ArchiveFormat {
    case gzippedTar
    case zip

    /// Flags for `bsdtar -c`. Extraction never needs the format, since bsdtar
    /// sniffs the container -- which is why the `-z` the extraction commands
    /// pass is a no-op when the archive is really a zip.
    var creationFlags: [String] {
      switch self {
      case .gzippedTar:
        return ["-z"]
      case .zip:
        return ["--format", "zip"]
      }
    }

    var fileExtension: String {
      switch self {
      case .gzippedTar:
        return "tar.gz"
      case .zip:
        return "zip"
      }
    }
  }

  private static let executableMode = 0o755
  private static let plistContents = "plist-contents"
  private static let executableContents = "#!/bin/sh\necho hi\n"
  private static let symlinkDestination = "Sample.app/Info.plist"

  /// Builds the layout of a real IPA -- a nested `.app` holding a plain file, an
  /// executable and a symlink -- returning the directory that contains `Payload`.
  private func makePayloadFixture() throws -> String {
    let source = (tempDirectory as NSString).appendingPathComponent("source")
    let payload = (source as NSString).appendingPathComponent("Payload")
    let app = (payload as NSString).appendingPathComponent("Sample.app")
    try FileManager.default.createDirectory(atPath: app, withIntermediateDirectories: true)
    try Self.plistContents.write(
      toFile: (app as NSString).appendingPathComponent("Info.plist"),
      atomically: true,
      encoding: .utf8)
    let executable = (app as NSString).appendingPathComponent("Sample")
    try Self.executableContents.write(toFile: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes(
      [.posixPermissions: Self.executableMode], ofItemAtPath: executable)
    try FileManager.default.createSymbolicLink(
      atPath: (payload as NSString).appendingPathComponent("link"),
      withDestinationPath: Self.symlinkDestination)
    return source
  }

  private func makeArchive(from source: String, format: ArchiveFormat) throws -> String {
    let archive = (tempDirectory as NSString)
      .appendingPathComponent("fixture.\(format.fileExtension)")
    try ArchiveFixtures.run(
      BSDTarPath, format.creationFlags + ["-c", "-f", archive, "-C", source, "Payload"],
      in: URL(fileURLWithPath: tempDirectory))
    return archive
  }

  private func makeExtractionDirectory() throws -> String {
    let path = (tempDirectory as NSString).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  private func extractFromFile(
    _ archive: String, overrideModificationTime: Bool = false
  ) async throws -> String {
    let destination = try makeExtractionDirectory()
    try await ArchiveExtractors.default.extract(
      fromFile: archive,
      to: destination,
      options: ArchiveExtractOptions(overrideModificationTime: overrideModificationTime),
      logger: logger)
    return destination
  }

  private func extractFromStream(
    _ archive: String, overrideModificationTime: Bool = false
  ) async throws -> String {
    let destination = try makeExtractionDirectory()
    let data = try Data(contentsOf: URL(fileURLWithPath: archive))
    try await BytePipe(data).reading {
      try await ArchiveExtractors.default.extract(
        from: $0,
        to: destination,
        options: ArchiveExtractOptions(overrideModificationTime: overrideModificationTime),
        logger: logger)
    }
    return destination
  }

  private func posixPermissions(atPath path: String) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
  }

  /// The parts of the fixture that survive every container and read mode.
  private func assertPayloadContents(extractedTo root: String) throws {
    let app = (root as NSString).appendingPathComponent("Payload/Sample.app")
    XCTAssertEqual(
      try String(
        contentsOfFile: (app as NSString).appendingPathComponent("Info.plist"), encoding: .utf8),
      Self.plistContents)
    XCTAssertEqual(
      try String(
        contentsOfFile: (app as NSString).appendingPathComponent("Sample"), encoding: .utf8),
      Self.executableContents)
  }

  // MARK: - Extraction from a file path

  func testExtractArchiveAtPath_GzippedTar_RestoresContentsPermissionsAndSymlinks() async throws {
    let archive = try makeArchive(from: try makePayloadFixture(), format: .gzippedTar)

    let root = try await extractFromFile(archive)

    try assertPayloadContents(extractedTo: root)
    XCTAssertEqual(
      try posixPermissions(
        atPath: (root as NSString).appendingPathComponent("Payload/Sample.app/Sample")),
      Self.executableMode,
      "A gzipped tar carries the mode in every entry header")
    let link = (root as NSString).appendingPathComponent("Payload/link")
    XCTAssertEqual(
      try FileManager.default.destinationOfSymbolicLink(atPath: link), Self.symlinkDestination)
  }

  func testExtractArchiveAtPath_Zip_RestoresContentsPermissionsAndSymlinks() async throws {
    let archive = try makeArchive(from: try makePayloadFixture(), format: .zip)

    let root = try await extractFromFile(archive)

    try assertPayloadContents(extractedTo: root)
    XCTAssertEqual(
      try posixPermissions(
        atPath: (root as NSString).appendingPathComponent("Payload/Sample.app/Sample")),
      Self.executableMode,
      "A seekable read reaches the zip central directory, which holds the Unix mode")
    let link = (root as NSString).appendingPathComponent("Payload/link")
    XCTAssertEqual(
      try FileManager.default.destinationOfSymbolicLink(atPath: link), Self.symlinkDestination)
  }

  // MARK: - Extraction from a stream

  func testExtractArchiveFromStream_GzippedTar_RestoresContentsPermissionsAndSymlinks() async throws {
    let archive = try makeArchive(from: try makePayloadFixture(), format: .gzippedTar)

    let root = try await extractFromStream(archive)

    try assertPayloadContents(extractedTo: root)
    XCTAssertEqual(
      try posixPermissions(
        atPath: (root as NSString).appendingPathComponent("Payload/Sample.app/Sample")),
      Self.executableMode,
      "Tar entry headers carry the mode, so streaming loses nothing")
    let link = (root as NSString).appendingPathComponent("Payload/link")
    XCTAssertEqual(
      try FileManager.default.destinationOfSymbolicLink(atPath: link), Self.symlinkDestination)
  }

  // MARK: - Modification time

  func testExtractArchiveAtPath_PreservesModificationTimeByDefault() async throws {
    let source = try makePayloadFixture()
    let archivedDate = Date(timeIntervalSince1970: 1_000_000_000)
    let plist = (source as NSString).appendingPathComponent("Payload/Sample.app/Info.plist")
    try FileManager.default.setAttributes([.modificationDate: archivedDate], ofItemAtPath: plist)
    let archive = try makeArchive(from: source, format: .gzippedTar)

    let root = try await extractFromFile(archive, overrideModificationTime: false)

    let extracted = (root as NSString).appendingPathComponent("Payload/Sample.app/Info.plist")
    let attributes = try FileManager.default.attributesOfItem(atPath: extracted)
    let extractedDate = try XCTUnwrap(attributes[.modificationDate] as? Date)
    XCTAssertEqual(
      extractedDate.timeIntervalSince1970, archivedDate.timeIntervalSince1970, accuracy: 2)
  }

  func testExtractArchiveAtPath_OverrideModificationTime_RewritesItToNow() async throws {
    let source = try makePayloadFixture()
    let archivedDate = Date(timeIntervalSince1970: 1_000_000_000)
    let plist = (source as NSString).appendingPathComponent("Payload/Sample.app/Info.plist")
    try FileManager.default.setAttributes([.modificationDate: archivedDate], ofItemAtPath: plist)
    let archive = try makeArchive(from: source, format: .gzippedTar)

    let root = try await extractFromFile(archive, overrideModificationTime: true)

    let extracted = (root as NSString).appendingPathComponent("Payload/Sample.app/Info.plist")
    let attributes = try FileManager.default.attributesOfItem(atPath: extracted)
    let extractedDate = try XCTUnwrap(attributes[.modificationDate] as? Date)
    XCTAssertGreaterThan(
      extractedDate, Date(timeIntervalSinceNow: -300),
      "The archive's mtime should be discarded in favour of the current time")
  }

  // MARK: - Failure

  func testExtractArchiveAtPath_WhenArchiveIsCorrupt_Fails() async throws {
    let archive = (tempDirectory as NSString).appendingPathComponent("corrupt.tar.gz")
    try Data("not an archive at all".utf8).write(to: URL(fileURLWithPath: archive))

    do {
      _ = try await extractFromFile(archive)
      XCTFail("Expected the extraction to fail")
    } catch {
      guard case SubprocessError.unacceptableTermination = error else {
        return XCTFail("Expected bsdtar to fail, got \(error)")
      }
    }
  }

  func testExtractArchiveAtPath_WhenArchiveIsMissing_Fails() async throws {
    let archive = (tempDirectory as NSString).appendingPathComponent("absent.tar.gz")

    do {
      _ = try await extractFromFile(archive)
      XCTFail("Expected the extraction to fail")
    } catch {
      guard case SubprocessError.unacceptableTermination = error else {
        return XCTFail("Expected bsdtar to fail, got \(error)")
      }
      XCTAssertTrue(error.localizedDescription.contains("No such file or directory"), error.localizedDescription)
    }
  }

  func testBSDTarExtractingAStream_WhenItIsCorrupt_FailsWithBSDTarsStandardError() async throws {
    let input = BytePipe(Data("not an archive at all".utf8))
    let root = try makeExtractionDirectory()

    do {
      try await input.reading { try await BSDTarExtractor().extract(from: $0, to: root, options: ArchiveExtractOptions(), logger: logger) }
      XCTFail("Expected the extraction to fail")
    } catch {
      XCTAssertTrue(error.localizedDescription.hasPrefix("Exit Code 1 is not acceptable [0]: "), error.localizedDescription)
      XCTAssertTrue(error.localizedDescription.contains("Unrecognized archive format"), error.localizedDescription)
    }
  }

  func testBSDTarExtractingAStream_WhenItStopsReadingEarly_FailsRatherThanWaiting() async throws {
    let input = BytePipe(Self.randomData(count: 8 << 20))
    let root = try makeExtractionDirectory()

    do {
      try await input.reading { try await BSDTarExtractor().extract(from: $0, to: root, options: ArchiveExtractOptions(), logger: logger) }
      XCTFail("Expected the extraction to fail")
    } catch {
      XCTAssertTrue(error.localizedDescription.hasPrefix("Exit Code 1 is not acceptable [0]"), error.localizedDescription)
    }
  }

  // MARK: - Streams larger than a pipe buffer

  func testBSDTarExtractingAStream_LargerThanAPipeBuffer_RestoresEveryByte() async throws {
    let source = try makePayloadFixture()
    let contents = Self.randomData(count: 8 << 20)
    try contents.write(to: URL(fileURLWithPath: (source as NSString).appendingPathComponent("Payload/Sample.app/Large")))
    let archive = try makeArchive(from: source, format: .gzippedTar)
    let input = BytePipe(try Data(contentsOf: URL(fileURLWithPath: archive)))
    let root = try makeExtractionDirectory()

    try await input.reading { try await BSDTarExtractor().extract(from: $0, to: root, options: ArchiveExtractOptions(), logger: logger) }

    try assertPayloadContents(extractedTo: root)
    XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: (root as NSString).appendingPathComponent("Payload/Sample.app/Large"))), contents)
  }

  private static func randomData(count: Int) -> Data {
    var data = Data(count: count)
    data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
    return data
  }
}
