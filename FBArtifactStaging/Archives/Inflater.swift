/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import zlib

/// A zlib inflate stream. A class, as zlib keeps a pointer back to the `z_stream`
/// it initialised, so the stream must not be copied.
final class Inflater {

  enum Format {
    /// Raw deflate, without a header, as a zip holds.
    case deflate
    /// A gzip member, header and trailer included.
    case gzip
  }

  struct Step {
    let consumed: Int
    let produced: Int
    let ended: Bool
  }

  private var stream = z_stream()
  private var initialised = false

  init?(_ format: Format) {
    let windowBits = format == .deflate ? -MAX_WBITS : MAX_WBITS + 16
    guard inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
      return nil
    }
    initialised = true
  }

  deinit {
    if initialised {
      inflateEnd(&stream)
    }
  }

  /// Nil if `input` is not what the format says.
  func inflate(_ input: UnsafeRawBufferPointer, into output: UnsafeMutableRawBufferPointer) -> Step? {
    stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
    stream.avail_in = uInt(input.count)
    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
    stream.avail_out = uInt(output.count)
    let status = zlib.inflate(&stream, Z_NO_FLUSH)
    guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
      return nil
    }
    return Step(consumed: input.count - Int(stream.avail_in), produced: output.count - Int(stream.avail_out), ended: status == Z_STREAM_END)
  }

  /// Readies the stream for another member after one ends.
  func reset() {
    inflateReset(&stream)
  }
}
