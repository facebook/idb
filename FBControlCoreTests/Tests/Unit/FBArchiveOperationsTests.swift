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
}
