/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

private let newline = Data("\n".utf8)

/// A buffer that accumulates the data it consumes. All methods are fully synchronized.
/// @unchecked Sendable: `buffer` is only touched under `lock`.
public class AccumulatingBuffer: DataConsumer, DataConsumerLifecycle, CustomStringConvertible, @unchecked Sendable {
  let lock = NSLock()
  fileprivate var buffer = Data()
  private let capacity: Int
  public let finishedConsuming = AsyncLatch()

  /// A buffer that keeps everything it consumes.
  public convenience init() {
    self.init(bound: 0)
  }

  /// A buffer that drops bytes from its beginning once `capacity` bytes are exceeded.
  public convenience init(capacity: Int) {
    precondition(capacity > 0)
    self.init(bound: capacity)
  }

  /// `bound` is the capacity, or 0 for none.
  fileprivate init(bound: Int) {
    self.capacity = bound
  }

  public var description: String {
    "Accumulating Buffer \(data().count) Bytes"
  }

  /// Obtains a copy of the current output data.
  public func data() -> Data {
    lock.withLock { buffer }
  }

  /// The current output split on newlines.
  public func lines() -> [String] {
    guard let output = String(data: data(), encoding: .utf8) else {
      return []
    }
    return output.components(separatedBy: .newlines)
  }

  public func consumeData(_ data: Data) {
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

  public func consumeEndOfFile() {
    lock.withLock {
      finishedConsuming.open()
    }
  }
}

/// A buffer that is appended to by consuming data and can be drained. All methods are fully synchronized.
public final class ConsumableBuffer: AccumulatingBuffer, @unchecked Sendable {
  public init() {
    super.init(bound: 0)
  }

  public override var description: String {
    "Consumable Buffer \(data().count) Bytes"
  }

  /// Consume the remainder of the buffer available, returning it as Data.
  public func consumeCurrentData() -> Data {
    lock.withLock {
      let data = buffer
      buffer = Data()
      return data
    }
  }

  /// Consume the remainder of the buffer available, returning it as a String.
  public func consumeCurrentString() -> String? {
    String(data: consumeCurrentData(), encoding: .utf8)
  }

  /// Consumes an amount of data from the buffer.
  public func consumeLength(_ length: UInt) -> Data? {
    lock.withLock {
      let length = Int(length)
      guard length <= buffer.count else {
        return nil
      }
      return take(upTo: buffer.startIndex + length, dropping: buffer.startIndex + length)
    }
  }

  /// Removes and returns the bytes before the first `terminal` (dropping the terminal), or nil if absent.
  public func consume(until terminal: Data) -> Data? {
    lock.withLock {
      guard !buffer.isEmpty, let terminalRange = buffer.range(of: terminal) else {
        return nil
      }
      return take(upTo: terminalRange.lowerBound, dropping: terminalRange.upperBound)
    }
  }

  /// Consume a line if one is available, returning it as Data.
  public func consumeLineData() -> Data? {
    consume(until: newline)
  }

  /// Consume a line if one is available, returning it as a String.
  public func consumeLineString() -> String? {
    consumeLineData().flatMap { String(data: $0, encoding: .utf8) }
  }

  /// Removes the bytes before `dropEnd` and returns those before `end`. Must be called under `lock`.
  private func take(upTo end: Data.Index, dropping dropEnd: Data.Index) -> Data {
    let taken = Data(buffer[buffer.startIndex..<end])
    buffer.removeSubrange(buffer.startIndex..<dropEnd)
    return taken
  }
}
