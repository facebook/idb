/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPCCore

/// Writes an uploaded payload into the pipe an extractor reads, as it arrives.
///
/// Has to run concurrently with the extractor: the pipe holds only a buffer's worth, so filling it before the reader
/// starts would deadlock on anything larger than that.
enum PayloadPump {

  /// Writes `head`, then every frame of `frames`, to `output`. An error thrown by `frames` is passed to
  /// `onClientFailure` before it is rethrown, so a caller can tell the client's failure from the extractor's.
  static func write<Frames: AsyncSequence>(
    head: Data,
    frames: Frames,
    to output: OutputStream,
    onWrite: (Data) -> Void = { _ in },
    onClientFailure: (any Error) -> Void = { _ in }
  ) async throws where Frames.Element == Data {
    try write(head, to: output)
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
      try write(frame, to: output)
      onWrite(frame)
    }
  }

  /// A failed write ends the transfer rather than being something to retry or resume from.
  private static func write(_ data: Data, to output: OutputStream) throws {
    do {
      try output.writeAll(data)
    } catch {
      throw RPCError(code: .aborted, message: "Failed to write \(data.count) bytes to the extraction pipe: \(error.localizedDescription)")
    }
  }
}
