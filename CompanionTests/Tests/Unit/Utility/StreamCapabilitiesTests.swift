/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import Foundation
import IDBGRPCSwift
import XCTest

final class StreamCapabilitiesTests: XCTestCase {

  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  func testAPathWithADecompressorAdvertisesZstd() {
    let pzstd = directory.appendingPathComponent("pzstd").path
    FileManager.default.createFile(atPath: pzstd, contents: Data(), attributes: [.posixPermissions: 0o755])

    let capabilities = StreamCapabilities(searchPath: "/nonexistent:\(directory.path)")
    var info = Idb_CompanionInfo()
    info.setStreamCapabilities(capabilities)

    XCTAssertEqual(capabilities.zstdDecompressorPath, pzstd)
    XCTAssertEqual(info.supportedCompressions, [.gzip, .zstd])
    XCTAssertTrue(info.zstdZipStreams)
  }

  func testAPathWithoutADecompressorAdvertisesGzipOnly() {
    let capabilities = StreamCapabilities(searchPath: directory.path)
    var info = Idb_CompanionInfo()
    info.setStreamCapabilities(capabilities)

    XCTAssertNil(capabilities.zstdDecompressorPath)
    XCTAssertEqual(info.supportedCompressions, [.gzip])
    XCTAssertFalse(info.zstdZipStreams)
  }

  func testADecompressorInstalledLaterIsNotSeenUntilResolvedAgain() {
    let capabilities = StreamCapabilities(searchPath: directory.path)
    FileManager.default.createFile(
      atPath: directory.appendingPathComponent("pzstd").path, contents: Data(), attributes: [.posixPermissions: 0o755])

    XCTAssertNil(capabilities.zstdDecompressorPath)
    XCTAssertNotNil(StreamCapabilities(searchPath: directory.path).zstdDecompressorPath)
  }
}
