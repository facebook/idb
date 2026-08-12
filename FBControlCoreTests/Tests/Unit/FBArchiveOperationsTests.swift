/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import XCTest

final class FBArchiveOperationsTests: XCTestCase {

  private var logger: FBControlCoreLoggerDouble!
  private var tempDirectory: String!

  override func setUp() {
    super.setUp()
    logger = FBControlCoreLoggerDouble()
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

    XCTAssertEqual(command.count, 5)
    XCTAssertEqual(command[0], "-zxp", "Flags should be -zxp without m or v")
    XCTAssertEqual(command[1], "-C")
    XCTAssertEqual(command[2], "/tmp/output")
    XCTAssertEqual(command[3], "-f")
    XCTAssertEqual(command[4], "/tmp/archive.tar.gz")
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

    XCTAssertEqual(command[2], extractPath, "Extract path should be preserved exactly")
    XCTAssertEqual(command[4], archivePath, "Archive path should be preserved exactly")
  }

  // MARK: - commandToExtractFromStdIn with GZIP

  func testCommandToExtractFromStdIn_GZIPCompression_NoOverrideMTime_NoDebug() {
    let command = FBArchiveOperations.commandToExtractFromStdIn(
      withExtractPath: "/tmp/output",
      overrideModificationTime: false,
      compression: .GZIP,
      debugLogging: false)

    XCTAssertEqual(command, ["-zxp", "-C", "/tmp/output", "-f", "-"])
  }

  func testCommandToExtractFromStdIn_GZIPCompression_WithOverrideMTime() {
    let command = FBArchiveOperations.commandToExtractFromStdIn(
      withExtractPath: "/tmp/output",
      overrideModificationTime: true,
      compression: .GZIP,
      debugLogging: false)

    XCTAssertEqual(command[0], "-zxpm", "GZIP with overrideMTime should include m flag")
    XCTAssertEqual(command[4], "-", "Last element should be stdin marker '-'")
  }

  // MARK: - commandToExtractFromStdIn with ZSTD

  func testCommandToExtractFromStdIn_ZSTDCompression_NoOverrideMTime() {
    let command = FBArchiveOperations.commandToExtractFromStdIn(
      withExtractPath: "/tmp/output",
      overrideModificationTime: false,
      compression: .ZSTD,
      debugLogging: false)

    XCTAssertEqual(command, ["--use-compress-program", "pzstd -d", "-xp", "-C", "/tmp/output", "-f", "-"])
  }

  func testCommandToExtractFromStdIn_ZSTDCompression_WithOverrideMTime() {
    let command = FBArchiveOperations.commandToExtractFromStdIn(
      withExtractPath: "/tmp/output",
      overrideModificationTime: true,
      compression: .ZSTD,
      debugLogging: false)

    XCTAssertEqual(command, ["--use-compress-program", "pzstd -d", "-xpm", "-C", "/tmp/output", "-f", "-"])
  }

  func testCommandToExtractFromStdIn_ZSTDCompression_IgnoresDebugLogging() {
    let commandNoDebug = FBArchiveOperations.commandToExtractFromStdIn(
      withExtractPath: "/tmp/output",
      overrideModificationTime: false,
      compression: .ZSTD,
      debugLogging: false)

    let commandWithDebug = FBArchiveOperations.commandToExtractFromStdIn(
      withExtractPath: "/tmp/output",
      overrideModificationTime: false,
      compression: .ZSTD,
      debugLogging: true)

    XCTAssertEqual(
      commandNoDebug, commandWithDebug,
      "ZSTD compression should produce the same command regardless of debugLogging")
  }

  // MARK: - createGzippedTarForPath with Non-Existent Path

  func testCreateGzippedTarForPath_WhenPathDoesNotExist_ReturnsError() {
    let nonExistentPath = "/tmp/this_path_definitely_does_not_exist_12345"
    let future = FBArchiveOperations.createGzippedTar(forPath: nonExistentPath, logger: logger)

    XCTAssertThrowsError(try future.`await`())
  }

  func testCreateGzippedTarDataForPath_WhenPathDoesNotExist_ReturnsError() {
    let nonExistentPath = "/tmp/this_path_definitely_does_not_exist_12345"
    let queue = DispatchQueue.global(qos: .default)
    let future = FBArchiveOperations.createGzippedTarData(
      forPath: nonExistentPath, queue: queue, logger: logger)

    XCTAssertThrowsError(try future.`await`())
  }

  func testCreateGzippedTarForPath_WhenPathDoesNotExist_ErrorContainsPath() {
    let nonExistentPath = "/tmp/nonexistent_path_for_error_check"
    let future = FBArchiveOperations.createGzippedTar(forPath: nonExistentPath, logger: logger)

    XCTAssertThrowsError(try future.`await`()) { error in
      let nsError = error as NSError
      XCTAssertTrue(
        nsError.localizedDescription.contains(nonExistentPath),
        "Error description should mention the non-existent path, got: \(nsError.localizedDescription)")
    }
  }

  // MARK: - createGzippedTarForPath with Real Paths

  func testCreateGzippedTarForPath_WhenPathIsDirectoryWithContent_StartsSubprocess() throws {
    let filePath = (tempDirectory as NSString).appendingPathComponent("testfile.txt")
    try "hello".write(toFile: filePath, atomically: true, encoding: .utf8)

    let future = FBArchiveOperations.createGzippedTar(forPath: tempDirectory, logger: logger)
    let subprocess = try future.`await`()
    XCTAssertNotNil(subprocess.stdOut)
  }

  func testCreateGzippedTarForPath_WhenPathIsFile_StartsSubprocess() throws {
    let filePath = (tempDirectory as NSString).appendingPathComponent("testfile.txt")
    try "some content".write(toFile: filePath, atomically: true, encoding: .utf8)

    let future = FBArchiveOperations.createGzippedTar(forPath: filePath, logger: logger)
    let subprocess = try future.`await`()
    XCTAssertNotNil(subprocess.stdOut)
  }

  // MARK: - createGzippedTarDataForPath with Real Paths

  func testCreateGzippedTarDataForPath_WhenPathIsDirectory_ProducesData() throws {
    let filePath = (tempDirectory as NSString).appendingPathComponent("data.txt")
    try "tar data test".write(toFile: filePath, atomically: true, encoding: .utf8)

    let queue = DispatchQueue.global(qos: .default)
    let future = FBArchiveOperations.createGzippedTarData(
      forPath: tempDirectory, queue: queue, logger: logger)

    let result = try future.`await`()
    XCTAssertGreaterThan(result.length, 0)
  }

  func testCreateGzippedTarDataForPath_WhenPathIsFile_ProducesData() throws {
    let filePath = (tempDirectory as NSString).appendingPathComponent("single.txt")
    try "file content for tar".write(toFile: filePath, atomically: true, encoding: .utf8)

    let queue = DispatchQueue.global(qos: .default)
    let future = FBArchiveOperations.createGzippedTarData(
      forPath: filePath, queue: queue, logger: logger)

    let result = try future.`await`()
    XCTAssertGreaterThan(result.length, 0)
  }

  func testCreateGzippedTarDataForPath_ProducesValidGzipData() throws {
    let filePath = (tempDirectory as NSString).appendingPathComponent("gzip_check.txt")
    try "content to verify gzip format".write(toFile: filePath, atomically: true, encoding: .utf8)

    let queue = DispatchQueue.global(qos: .default)
    let future = FBArchiveOperations.createGzippedTarData(
      forPath: tempDirectory, queue: queue, logger: logger)

    let result = try future.`await`()
    let data = result as Data
    XCTAssertGreaterThanOrEqual(data.count, 2, "Gzip data should be at least 2 bytes")
    XCTAssertEqual(data[0], 0x1f, "First byte of gzip data should be 0x1f")
    XCTAssertEqual(data[1], 0x8b, "Second byte of gzip data should be 0x8b")
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
    let process = Process()
    process.executableURL = URL(fileURLWithPath: BSDTarPath)
    process.arguments = format.creationFlags + ["-c", "-f", archive, "-C", source, "Payload"]
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(
      process.terminationStatus, 0, "Failed to build the \(format.fileExtension) fixture")
    return archive
  }

  private func makeExtractionDirectory() throws -> String {
    let path = (tempDirectory as NSString).appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  private func extractFromFile(
    _ archive: String, overrideModificationTime: Bool = false
  ) throws -> String {
    let destination = try makeExtractionDirectory()
    let future = FBArchiveOperations.extractArchive(
      atPath: archive,
      toPath: destination,
      overrideModificationTime: overrideModificationTime,
      logger: logger)
    return try future.`await`() as String
  }

  private func extractFromStream(
    _ archive: String, overrideModificationTime: Bool = false
  ) throws -> String {
    let destination = try makeExtractionDirectory()
    let data = try Data(contentsOf: URL(fileURLWithPath: archive))
    let input = unsafeBitCast(
      FBProcessInput<NSData>(from: data), to: FBProcessInput<AnyObject>.self)
    // Production passes GZIP for every container -- the flag only selects between
    // gzip and zstd, and bsdtar sniffs the real format regardless.
    let future = FBArchiveOperations.extractArchive(
      fromStream: input,
      toPath: destination,
      overrideModificationTime: overrideModificationTime,
      logger: logger,
      compression: .GZIP)
    return try future.`await`() as String
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

  // MARK: Extraction from a file path

  func testExtractArchiveAtPath_GzippedTar_RestoresContentsPermissionsAndSymlinks() throws {
    let archive = try makeArchive(from: try makePayloadFixture(), format: .gzippedTar)

    let root = try extractFromFile(archive)

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

  func testExtractArchiveAtPath_Zip_RestoresContentsPermissionsAndSymlinks() throws {
    let archive = try makeArchive(from: try makePayloadFixture(), format: .zip)

    let root = try extractFromFile(archive)

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

  // MARK: Extraction from a stream

  func testExtractArchiveFromStream_GzippedTar_RestoresContentsPermissionsAndSymlinks() throws {
    let archive = try makeArchive(from: try makePayloadFixture(), format: .gzippedTar)

    let root = try extractFromStream(archive)

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

  // BUG: a streamed zip silently loses Unix permissions and flattens symlinks into
  // regular files -- both live only in the zip central directory at the end of the
  // archive, which a sequential reader never reaches. This is the `.url` and
  // `.data` install path, and it strips the executable bit from every binary in a
  // real IPA. Asserted as-is here; flipped later in the stack.
  func testExtractArchiveFromStream_Zip_LosesPermissionsAndSymlinks() throws {
    let archive = try makeArchive(from: try makePayloadFixture(), format: .zip)

    let root = try extractFromStream(archive)

    try assertPayloadContents(extractedTo: root)
    XCTAssertNotEqual(
      try posixPermissions(
        atPath: (root as NSString).appendingPathComponent("Payload/Sample.app/Sample")),
      Self.executableMode,
      "BUG: the executable bit is dropped when a zip is streamed")
    let link = (root as NSString).appendingPathComponent("Payload/link")
    XCTAssertThrowsError(
      try FileManager.default.destinationOfSymbolicLink(atPath: link),
      "BUG: the symlink is materialised as a regular file when a zip is streamed")
    XCTAssertEqual(
      try String(contentsOfFile: link, encoding: .utf8), Self.symlinkDestination,
      "BUG: and the file's contents are the link target path, not the target's contents")
  }

  // MARK: Modification time

  func testExtractArchiveAtPath_PreservesModificationTimeByDefault() throws {
    let source = try makePayloadFixture()
    let archivedDate = Date(timeIntervalSince1970: 1_000_000_000)
    let plist = (source as NSString).appendingPathComponent("Payload/Sample.app/Info.plist")
    try FileManager.default.setAttributes([.modificationDate: archivedDate], ofItemAtPath: plist)
    let archive = try makeArchive(from: source, format: .gzippedTar)

    let root = try extractFromFile(archive, overrideModificationTime: false)

    let extracted = (root as NSString).appendingPathComponent("Payload/Sample.app/Info.plist")
    let attributes = try FileManager.default.attributesOfItem(atPath: extracted)
    let extractedDate = try XCTUnwrap(attributes[.modificationDate] as? Date)
    XCTAssertEqual(
      extractedDate.timeIntervalSince1970, archivedDate.timeIntervalSince1970, accuracy: 2)
  }

  func testExtractArchiveAtPath_OverrideModificationTime_RewritesItToNow() throws {
    let source = try makePayloadFixture()
    let archivedDate = Date(timeIntervalSince1970: 1_000_000_000)
    let plist = (source as NSString).appendingPathComponent("Payload/Sample.app/Info.plist")
    try FileManager.default.setAttributes([.modificationDate: archivedDate], ofItemAtPath: plist)
    let archive = try makeArchive(from: source, format: .gzippedTar)

    let root = try extractFromFile(archive, overrideModificationTime: true)

    let extracted = (root as NSString).appendingPathComponent("Payload/Sample.app/Info.plist")
    let attributes = try FileManager.default.attributesOfItem(atPath: extracted)
    let extractedDate = try XCTUnwrap(attributes[.modificationDate] as? Date)
    XCTAssertGreaterThan(
      extractedDate, Date(timeIntervalSinceNow: -300),
      "The archive's mtime should be discarded in favour of the current time")
  }

  // MARK: Failure

  func testExtractArchiveAtPath_WhenArchiveIsCorrupt_Fails() throws {
    let archive = (tempDirectory as NSString).appendingPathComponent("corrupt.tar.gz")
    try Data("not an archive at all".utf8).write(to: URL(fileURLWithPath: archive))

    XCTAssertThrowsError(try extractFromFile(archive))
  }

  func testExtractArchiveAtPath_WhenArchiveIsMissing_Fails() throws {
    let archive = (tempDirectory as NSString).appendingPathComponent("absent.tar.gz")

    XCTAssertThrowsError(try extractFromFile(archive))
  }
}
