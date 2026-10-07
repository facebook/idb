/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import zlib

/// A zlib deflate stream writing a single gzip member. A class, as zlib keeps a pointer back to the
/// `z_stream` it initialised, and to the header it was given, so neither may move.
final class Deflater {

  struct Step {
    let consumed: Int
    let produced: Int
    let ended: Bool
  }

  private var stream = z_stream()
  private let header: UnsafeMutablePointer<gz_header>
  private var initialised = false

  init?() {
    header = .allocate(capacity: 1)
    header.initialize(to: gz_header())
    // zlib names macOS by its own OS code; gzip and bsdtar write 3 for any Unix host, which is what clients see today.
    header.pointee.os = 3
    guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, MAX_WBITS + 16, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
      header.deallocate()
      return nil
    }
    guard deflateSetHeader(&stream, header) == Z_OK else {
      deflateEnd(&stream)
      header.deallocate()
      return nil
    }
    initialised = true
  }

  deinit {
    if initialised {
      deflateEnd(&stream)
      header.deallocate()
    }
  }

  /// Deflates `input`, writing the trailer once `finish` is set and all of the input is consumed.
  func deflate(_ input: UnsafeRawBufferPointer, into output: UnsafeMutableRawBufferPointer, finish: Bool) -> Step? {
    stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
    stream.avail_in = uInt(input.count)
    stream.next_out = output.bindMemory(to: Bytef.self).baseAddress
    stream.avail_out = uInt(output.count)
    let status = zlib.deflate(&stream, finish ? Z_FINISH : Z_NO_FLUSH)
    guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
      return nil
    }
    return Step(consumed: input.count - Int(stream.avail_in), produced: output.count - Int(stream.avail_out), ended: status == Z_STREAM_END)
  }
}
