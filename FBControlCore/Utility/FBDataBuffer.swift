/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Implementations of data buffers. Writes and reads are fully synchronized.
public enum FBDataBuffer {
  /// A data buffer that is only mutated through consuming data.
  public static func accumulatingBuffer() -> AccumulatingBuffer {
    AccumulatingDataBuffer(capacity: 0)
  }

  /// A data buffer that drops bytes from its beginning once `capacity` bytes are exceeded.
  public static func accumulatingBuffer(withCapacity capacity: Int) -> AccumulatingBuffer {
    precondition(capacity > 0)
    return AccumulatingDataBuffer(capacity: capacity)
  }

  /// A data buffer that is appended to by consuming data and can be drained.
  public static func consumableBuffer() -> ConsumableBuffer {
    ConsumableDataBuffer()
  }

  /// Data for a newline.
  public static func newlineTerminal() -> Data {
    newline
  }

  private static let newline = Data("\n".utf8)
}

/// @unchecked Sendable: `buffer` is only touched under `lock`.
private class AccumulatingDataBuffer: AccumulatingBuffer, CustomStringConvertible, @unchecked Sendable {
  let lock = NSLock()
  fileprivate var buffer = Data()
  private let capacity: Int
  let finishedConsuming = AsyncLatch()

  init(capacity: Int) {
    self.capacity = capacity
  }

  var description: String {
    "Accumulating Buffer \(data().count) Bytes"
  }

  func data() -> Data {
    lock.withLock { buffer }
  }

  func lines() -> [String] {
    guard let output = String(data: data(), encoding: .utf8) else {
      return []
    }
    return output.components(separatedBy: .newlines)
  }

  func consumeData(_ data: Data) {
    lock.withLock {
      if finishedConsuming.isOpen {
        return
      }
      buffer.append(data)
      let overrun = buffer.count - capacity
      if capacity > 0, overrun > 0 {
        buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + overrun))
      }
    }
  }

  func consumeEndOfFile() {
    lock.withLock {
      finishedConsuming.open()
    }
  }
}

private final class ConsumableDataBuffer: AccumulatingDataBuffer, ConsumableBuffer, @unchecked Sendable {
  init() {
    super.init(capacity: 0)
  }

  override var description: String {
    "Consumable Buffer \(data().count) Bytes"
  }

  func consumeCurrentData() -> Data {
    lock.withLock {
      let data = buffer
      buffer = Data()
      return data
    }
  }

  func consumeCurrentString() -> String? {
    String(data: consumeCurrentData(), encoding: .utf8)
  }

  func consumeLength(_ length: UInt) -> Data? {
    lock.withLock {
      let length = Int(length)
      guard length <= buffer.count else {
        return nil
      }
      return take(upTo: buffer.startIndex + length, dropping: buffer.startIndex + length)
    }
  }

  func consume(until terminal: Data) -> Data? {
    lock.withLock {
      guard !buffer.isEmpty, let terminalRange = buffer.range(of: terminal) else {
        return nil
      }
      return take(upTo: terminalRange.lowerBound, dropping: terminalRange.upperBound)
    }
  }

  func consumeLineData() -> Data? {
    consume(until: FBDataBuffer.newlineTerminal())
  }

  func consumeLineString() -> String? {
    consumeLineData().flatMap { String(data: $0, encoding: .utf8) }
  }

  /// Removes the bytes before `dropEnd` and returns those before `end`. Must be called under `lock`.
  private func take(upTo end: Data.Index, dropping dropEnd: Data.Index) -> Data {
    let taken = Data(buffer[buffer.startIndex..<end])
    buffer.removeSubrange(buffer.startIndex..<dropEnd)
    return taken
  }
}
