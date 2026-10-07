/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Implementations of data buffers. Writes and reads are fully synchronized.
@objc public final class FBDataBuffer: NSObject {
  /// A data buffer that is only mutated through consuming data.
  @objc public static func accumulatingBuffer() -> AccumulatingBuffer {
    AccumulatingDataBuffer(backing: NSMutableData(), capacity: 0)
  }

  /// A data buffer that drops bytes from its beginning once `capacity` bytes are exceeded.
  @objc public static func accumulatingBuffer(withCapacity capacity: Int) -> AccumulatingBuffer {
    precondition(capacity > 0)
    return AccumulatingDataBuffer(backing: NSMutableData(), capacity: capacity)
  }

  /// A data buffer that appends into the provided data.
  @objc public static func accumulatingBuffer(for data: NSMutableData) -> AccumulatingBuffer {
    AccumulatingDataBuffer(backing: data, capacity: 0)
  }

  /// A data buffer that is appended to by consuming data and can be drained.
  @objc public static func consumableBuffer() -> ConsumableBuffer {
    ConsumableDataBuffer()
  }

  /// Data for a newline.
  @objc public static func newlineTerminal() -> Data {
    newline
  }

  private static let newline = Data("\n".utf8)
}

private class AccumulatingDataBuffer: NSObject, AccumulatingBuffer, @unchecked Sendable {
  let lock = NSLock()
  let buffer: NSMutableData
  private let capacity: Int
  private let finishedConsumingFuture = FBMutableFuture<NSNull>()

  init(backing: NSMutableData, capacity: Int) {
    self.buffer = backing
    self.capacity = capacity
  }

  override var description: String {
    "Accumilating Buffer \(data().count) Bytes"
  }

  func data() -> Data {
    lock.withLock { buffer as Data }
  }

  func lines() -> [String] {
    guard let output = String(data: data(), encoding: .utf8) else {
      return []
    }
    return output.components(separatedBy: .newlines)
  }

  func consumeData(_ data: Data) {
    lock.withLock {
      if finishedConsumingFuture.hasCompleted {
        return
      }
      buffer.append(data)
      let overrun = buffer.length - capacity
      if capacity > 0, overrun > 0 {
        buffer.replaceBytes(in: NSRange(location: 0, length: overrun), withBytes: nil, length: 0)
      }
    }
  }

  func consumeEndOfFile() {
    lock.withLock {
      if finishedConsumingFuture.hasCompleted {
        return
      }
      finishedConsumingFuture.resolve(withResult: NSNull())
    }
  }

  var finishedConsuming: FBFuture<NSNull> {
    finishedConsumingFuture.retyped(FBFuture<NSNull>.self)
  }
}

private final class ConsumableDataBuffer: AccumulatingDataBuffer, ConsumableBuffer, @unchecked Sendable {
  init() {
    super.init(backing: NSMutableData(), capacity: 0)
  }

  override var description: String {
    "Consumable Buffer \(data().count) Bytes"
  }

  func consumeCurrentData() -> Data {
    lock.withLock {
      let data = buffer as Data
      buffer.length = 0
      return data
    }
  }

  func consumeCurrentString() -> String? {
    String(data: consumeCurrentData(), encoding: .utf8)
  }

  func consumeLength(_ length: UInt) -> Data? {
    lock.withLock {
      let length = Int(length)
      guard length <= buffer.length else {
        return nil
      }
      let range = NSRange(location: 0, length: length)
      let data = buffer.subdata(with: range)
      buffer.replaceBytes(in: range, withBytes: nil, length: 0)
      return data
    }
  }

  func consume(until terminal: Data) -> Data? {
    lock.withLock {
      guard buffer.length > 0 else {
        return nil
      }
      let terminalRange = buffer.range(of: terminal, options: [], in: NSRange(location: 0, length: buffer.length))
      guard terminalRange.location != NSNotFound else {
        return nil
      }
      let data = buffer.subdata(with: NSRange(location: 0, length: terminalRange.location))
      buffer.replaceBytes(in: NSRange(location: 0, length: terminalRange.location + terminal.count), withBytes: nil, length: 0)
      return data
    }
  }

  func consumeLineData() -> Data? {
    consume(until: FBDataBuffer.newlineTerminal())
  }

  func consumeLineString() -> String? {
    consumeLineData().flatMap { String(data: $0, encoding: .utf8) }
  }
}
