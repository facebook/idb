/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBXCTestCore
import XCTest

final class XCTestLoggerTests: XCTestCase {

  func testLogConsumptionFeedsTheConsumerAndMirrorsToAFileInTheLogDirectory() async throws {
    let directory = (NSTemporaryDirectory() as NSString).appendingPathComponent("xctest_logger_\(UUID().uuidString)")
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let buffer = FBDataBuffer.consumableBuffer()

    let consumer = try await XCTestLogger.defaultLogger(inDirectory: directory).logConsumption(of: buffer, toFileNamed: "mirror.out", logger: ControlCoreGlobalConfiguration.defaultLogger)
    consumer.consumeData(Data("mirrored output".utf8))
    consumer.consumeEndOfFile()

    XCTAssertEqual(String(data: buffer.data(), encoding: .utf8), "mirrored output")
    let path = (directory as NSString).appendingPathComponent("mirror.out")
    let deadline = Date(timeIntervalSinceNow: 5)
    while (try? String(contentsOfFile: path, encoding: .utf8)) != "mirrored output", Date() < deadline {
      try await Task.sleep(nanoseconds: 50_000_000)
    }
    XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "mirrored output", "The file writer is asynchronous, so the mirror is polled for")
  }
}
