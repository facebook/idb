/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import GRPCCore

/// Writes an uploaded payload into the pipe an extractor reads, as it arrives.
///
/// Has to run concurrently with the extractor: the pipe holds only a buffer's worth, so filling it before the reader
/// starts would deadlock on anything larger than that.
enum PayloadPump {

  /// Writes `head`, then every frame of `frames`, to `input`. An error thrown by `frames` is passed to
  /// `onClientFailure` before it is rethrown, so a caller can tell the client's failure from the extractor's.
  static func write<Frames: AsyncSequence>(
    head: Data,
    frames: Frames,
    to input: InputSource,
    onWrite: (Data) -> Void = { _ in },
    onClientFailure: (any Error) -> Void = { _ in }
  ) async throws where Frames.Element == Data {
    try await write(head, to: input)
    onWrite(head)
    var iterator = frames.makeAsyncIterator()
    while true {
      let frame: Data?
      do {
        frame = try await iterator.next()
      } catch {
        onClientFailure(error)
        throw error
      }
      guard let frame else {
        return
      }
      try await write(frame, to: input)
      onWrite(frame)
    }
  }

  /// A failed write ends the transfer rather than being something to retry or resume from.
  private static func write(_ data: Data, to input: InputSource) async throws {
    do {
      try await input.writeAndWait(data)
    } catch {
      throw RPCError(code: .aborted, message: "Failed to write \(data.count) bytes to the extraction pipe: \(error.localizedDescription)")
    }
  }
}
