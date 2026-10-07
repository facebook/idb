/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
@preconcurrency import FBControlCore
import Foundation
import GRPCCore
import IDBGRPCSwift
import XCTest
import os

final class MultisourceFileReaderTests: XCTestCase {

  func testWritePayloadsStopsWhenTheReaderHasGone() async throws {
    let pipe = BytePipe()
    try await pipe.reading { _ in }
    let pulled = OSAllocatedUnfairLock(initialState: 0)

    do {
      try await MultisourceFileReader.writePayloads(
        initialData: Data([0xFF]),
        from: Self.requestStream(chunkCount: 4, pulled: pulled),
        to: pipe.input)
      XCTFail("Expected the failed write to end the transfer")
    } catch let error as RPCError {
      XCTAssertEqual(error.code, .aborted)
      XCTAssertTrue(error.message.hasPrefix("Failed to write 1 bytes to the extraction pipe"), error.message)
    }

    XCTAssertEqual(pulled.withLock { $0 }, 0)
  }

  private static func requestStream(chunkCount: Int, pulled: OSAllocatedUnfairLock<Int>) -> RequestStreamReader<Idb_PushRequest> {
    let source = AsyncThrowingStream<Idb_PushRequest, any Error> {
      let index = pulled.withLock { count -> Int in
        count += 1
        return count - 1
      }
      guard index < chunkCount else { return nil }
      return Idb_PushRequest.with {
        $0.payload = .with { $0.data = Data([UInt8(index)]) }
      }
    }
    return RequestStreamReader(RPCAsyncSequence(wrapping: source))
  }
}
