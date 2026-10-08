/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBControlCore
import Foundation
import IDBGRPCSwift
import XCTest

// SAFETY: `attempts` and `failuresRemaining` are only touched under `lock`.
private final class RecordingSender: @unchecked Sendable {
  private struct SendFailed: Error {}

  private let lock = NSLock()
  private var attempts: [Idb_LaunchResponse] = []
  private var failuresRemaining: Int

  init(failingFirst failures: Int = 0) {
    failuresRemaining = failures
  }

  var attempted: [Idb_LaunchResponse] {
    lock.withLock { attempts }
  }

  func send(_ response: Idb_LaunchResponse) throws {
    try lock.withLock {
      attempts.append(response)
      guard failuresRemaining > 0 else {
        return
      }
      failuresRemaining -= 1
      throw SendFailed()
    }
  }
}

final class LaunchMethodHandlerTests: XCTestCase {

  func testOutputIsForwardedInOrderWithItsInterface() async throws {
    let sender = RecordingSender()
    let consumer = LaunchMethodHandler.pipeOutput(interface: .stderr) { try sender.send($0) }

    consumer.consumeData(Data("one".utf8))
    consumer.consumeData(Data("two".utf8))
    consumer.consumeEndOfFile()
    try await consumer.awaitFinishedConsuming()

    XCTAssertEqual(sender.attempted.map(\.output.data), [Data("one".utf8), Data("two".utf8)])
    XCTAssertEqual(sender.attempted.map(\.output.interface), [.stderr, .stderr])
  }

  func testAFailedSendStopsLaterSends() async throws {
    let sender = RecordingSender(failingFirst: 1)
    let consumer = LaunchMethodHandler.pipeOutput(interface: .stdout) { try sender.send($0) }

    consumer.consumeData(Data("one".utf8))
    consumer.consumeData(Data("two".utf8))
    consumer.consumeEndOfFile()
    try await consumer.awaitFinishedConsuming()

    XCTAssertEqual(sender.attempted.map(\.output.data), [Data("one".utf8)])
  }
}
