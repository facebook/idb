/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import Foundation
import GRPCCore
import IDBGRPCSwift
import XCTest

/// Counts writes and starts reporting failure from a chosen write onwards, the way a real pipe
/// does once the process reading the other end has exited.
private final class StubOutputStream: OutputStream {

  static let failureReason = "stub pipe closed"

  private(set) var writeCount = 0
  private let failFromWrite: Int

  init(failFromWrite: Int) {
    self.failFromWrite = failFromWrite
    super.init(toMemory: ())
  }

  private var failing: Bool { writeCount >= failFromWrite }

  override func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
    writeCount += 1
    return failing ? -1 : len
  }

  // `NSStream` leaves this to the concrete subclass and traps if it is not overridden.
  override var streamError: Error? {
    guard failing else { return nil }
    return NSError(
      domain: "com.example.stub",
      code: 32,
      userInfo: [NSLocalizedDescriptionKey: Self.failureReason])
  }
}

final class MultisourceFileReaderTests: XCTestCase {

  func testWritePayloadsStopsWhenTheSinkFails() async throws {
    let stream = StubOutputStream(failFromWrite: 2)

    do {
      try await MultisourceFileReader.writePayloads(
        initialData: Data([0xFF]),
        from: Self.requestStream(chunkCount: 4),
        to: stream)
      XCTFail("Expected the failed write to end the transfer")
    } catch let error as RPCError {
      XCTAssertEqual(error.code, .aborted)
      XCTAssertTrue(error.message.contains(StubOutputStream.failureReason))
    }

    // The initial write plus the first chunk, which is the one that failed. The three chunks
    // after it are neither written nor pulled from the request stream.
    XCTAssertEqual(stream.writeCount, 2)
  }

  private static func requestStream(chunkCount: Int) -> RequestStreamReader<Idb_PushRequest> {
    let requests = (0..<chunkCount).map { index in
      Idb_PushRequest.with {
        $0.payload = .with { $0.data = Data([UInt8(index)]) }
      }
    }
    let source = AsyncThrowingStream<Idb_PushRequest, any Error> { continuation in
      for request in requests {
        continuation.yield(request)
      }
      continuation.finish()
    }
    return RequestStreamReader(RPCAsyncSequence(wrapping: source))
  }
}
