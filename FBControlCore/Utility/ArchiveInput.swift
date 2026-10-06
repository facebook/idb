/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import zlib

/// Bytes read ahead of an extractor that parses its archive forwards.
struct BufferedInput {
  private let source: ArchiveRead
  private var bytes: [UInt8]
  private var start = 0
  private var end = 0
  private var ended = false

  init(capacity: Int, read: @escaping ArchiveRead) {
    source = read
    bytes = [UInt8](repeating: 0, count: capacity)
  }

  var available: Int { end - start }

  var buffered: Data { Data(bytes[start..<end]) }

  subscript(offset: Int) -> UInt8 { bytes[start + offset] }

  /// Reads more after what is buffered, returning false at the end of the input.
  mutating func fill() throws -> Bool {
    guard !ended else {
      return false
    }
    if start > 0 {
      let (from, count) = (start, available)
      bytes.withUnsafeMutableBytes { bytes in
        guard let base = bytes.baseAddress else {
          return
        }
        memmove(base, base + from, count)
      }
      (start, end) = (0, count)
    }
    let offset = end
    let count = try bytes.withUnsafeMutableBytes { try source(UnsafeMutableRawBufferPointer(rebasing: $0[offset...])) }
    ended = count == 0
    end += count
    return count > 0
  }

  /// Returns whether at least `count` bytes are buffered, reading more if needed.
  mutating func buffer(atLeast count: Int) throws -> Bool {
    while available < count {
      guard try fill() else {
        return false
      }
    }
    return true
  }

  func withAvailable<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
    try bytes.withUnsafeBytes { try body(UnsafeRawBufferPointer(rebasing: $0[start..<end])) }
  }

  mutating func consume(_ count: Int) {
    start += count
  }

  /// Copies out what is buffered or, once that is used up, reads straight into `output`.
  mutating func read(into output: UnsafeMutableRawBufferPointer) throws -> Int {
    guard available > 0 else {
      guard !ended else {
        return 0
      }
      let count = try source(output)
      ended = count == 0
      return count
    }
    let count = min(available, output.count)
    withAvailable { output.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0[0..<count])) }
    start += count
    return count
  }

  /// Drops what is buffered without reading any more.
  mutating func discard() {
    (start, end) = (0, 0)
  }

  /// Reads to the end of the input, discarding it, so a writer is never left
  /// blocked on a pipe that nothing reads.
  mutating func drain() throws {
    repeat {
      discard()
    } while try fill()
  }
}

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
