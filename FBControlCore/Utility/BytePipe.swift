/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A pipe within the process: a producer writes to `input` as its bytes arrive, and one reader
/// reads them as a `ByteSource`, blocking its thread until they do.
///
/// Writes before the reader starts are held, as for a launch that has not happened yet; from
/// then on the pipe's buffer holds a producer that awaits its writes to the reader's pace.
public final class BytePipe: Sendable {

  /// Where the producer writes. `finish()` is the reader's end of file.
  public let input = InputSource()

  public init() {}

  /// A pipe holding `data` and then its end.
  public convenience init(_ data: Data) {
    self.init()
    input.write(data)
    input.finish()
  }

  /// Calls `body` with a source reading the pipe, and closes the reading end however `body`
  /// returns, so that a producer still writing fails rather than blocking on a pipe nothing reads.
  /// A pipe is read once.
  public func reading<T>(_ body: (any ByteSource) async throws -> T) async throws -> T {
    let readEnd = try input.attach()
    defer { close(readEnd) }
    return try await body(FileDescriptorSource(readEnd))
  }
}
