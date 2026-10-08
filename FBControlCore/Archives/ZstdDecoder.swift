/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
internal import ZstdDecompress

/// A zstd decompression stream. Frames are read one after another, and skippable frames are skipped.
final class ZstdDecoder {

  struct Step {
    let consumed: Int
    let produced: Int
    /// The frame that was being read has ended and all of its output has been produced.
    let frameEnded: Bool
  }

  private let stream: OpaquePointer

  init?() {
    guard let stream = ZSTD_createDStream() else {
      return nil
    }
    self.stream = stream
  }

  deinit {
    ZSTD_freeDStream(stream)
  }

  /// Nil if `input` is not zstd.
  func decompress(_ input: UnsafeRawBufferPointer, into output: UnsafeMutableRawBufferPointer) -> Step? {
    var inBuffer = ZSTD_inBuffer(src: input.baseAddress, size: input.count, pos: 0)
    var outBuffer = ZSTD_outBuffer(dst: output.baseAddress, size: output.count, pos: 0)
    let hint = ZSTD_decompressStream(stream, &outBuffer, &inBuffer)
    guard ZSTD_isError(hint) == 0 else {
      return nil
    }
    return Step(consumed: inBuffer.pos, produced: outBuffer.pos, frameEnded: hint == 0)
  }
}
